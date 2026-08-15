#!/bin/bash
set -e

###############################################################################
# DWI preprocessing pipeline
#
# This script was adapted and modified from the DWI preprocessing utility
# script provided by TractSeg:
#
# https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/utility_scripts/dwi_preprocessing.sh
#
# TractSeg:
# Wasserthal J, Neher P, Maier-Hein KH.
# TractSeg - Fast and accurate white matter tract segmentation.
# NeuroImage. 2018;183:239-253.
#
# The original TractSeg project is distributed under the Apache License 2.0.
# Modifications were made for the DWI preprocessing and fixel-based analysis
# workflow used in the present study.
#
# Input directory structure:
#   <data_path>/<subject_id>/<session>/raw/dwi_raw.mif
#
# Output used for subsequent fixel-based analysis: This file was used as input for the subsequent FBA pipeline.
#   <data_path>/<subject_id>/<session>/brain/dwi_preprocessed.mif
#
###############################################################################


function eddy_correct_extract_mask_denoise() {
    cd $data_path/$1/$2/raw

    echo "Denoising..."
    dwidenoise dwi_raw.mif dwi_denoise.mif -noise dwi_noise.mif -force
    mrcalc dwi_raw.mif dwi_noise.mif -subtract dwi_noise_residual.mif -force

    echo "Unringing..."
    mrdegibbs dwi_denoise.mif dwi_denoise_unr.mif -axes 0,1 -force

    echo "Eddy-current and head-motion correction..."
    #todo: adapt -pe_dir parameter according to the way your data was acquired
    # (see https://mrtrix.readthedocs.io/en/3.0_rc1/reference/scripts/dwipreproc.html for details)
    in_phase=$(mrinfo dwi_raw.mif | grep "PhaseEncodingDirection" | tail -n 1 | awk '{ print $2 }')
    dwifslpreproc dwi_denoise_unr.mif dwi_denoise_unr_eddy.mif -rpe_none -pe_dir ${in_phase} -eddyqc_text eddyqc
    
    echo "Bias correcting..."  # ants strongly recommended over fsl
    dwi2mask dwi_denoise_unr_eddy.mif nodif_brain_mask.mif -force
    dwibiascorrect ants dwi_denoise_unr_eddy.mif dwi_denoise_unr_eddy_bias.mif -mask nodif_brain_mask.mif

    echo "Brain masking..."
    #todo: if brain masks are too big or too small: adjust -f parameter (range: 0.1-0.5)
    dwiextract -bzero dwi_denoise_unr_eddy_bias.mif dwi_b0.mif
    mrconvert dwi_b0.mif dwi_b0.nii.gz

    dwiextract dwi_denoise_unr_eddy_bias.mif - -bzero | mrmath - mean dwi_b0_mean.mif -axis 3
    mrconvert dwi_b0_mean.mif dwi_b0_mean.nii.gz

    dwiextract -no_bzero dwi_denoise_unr_eddy_bias.mif dwi_nobzero.mif
    dwiextract -singleshell dwi_denoise_unr_eddy_bias.mif dwi_singleshell.mif
    bet dwi_b0_mean.nii.gz dwi_bet -f 0.3 -m -n
    
    mrconvert dwi_denoise_unr_eddy_bias.mif Diffusion_raw.nii.gz -export_grad_fsl Diffusion_raw.bvecs Diffusion_raw.bvals
}

function  register_DWI_to_MNI() {
    echo "Registering to MNI..."
    mkdir -p $data_path/$1/$2/preproc
    mkdir -p $data_path/$1/$2/brain
    cd $data_path/$1/$2
    cd preproc

    cp -v $data_path/$1/$2/raw/Diffusion_raw.bvals Diffusion_denoise_unr_eddy_bias_brain.bvals
    cp -v $data_path/$1/$2/raw/Diffusion_raw.bvecs Diffusion_denoise_unr_eddy_bias_brain.bvecs
    cp -v $data_path/$1/$2/raw/dwi_bet_mask.nii.gz nodif_brain_mask.nii.gz
    fslmaths $data_path/$1/$2/raw/Diffusion_raw.nii.gz -mul nodif_brain_mask.nii.gz Diffusion_denoise_unr_eddy_bias_brain.nii.gz
        
    calc_FA -i Diffusion_denoise_unr_eddy_bias_brain.nii.gz -o FA.nii.gz --bvals Diffusion_denoise_unr_eddy_bias_brain.bvals --bvecs Diffusion_denoise_unr_eddy_bias_brain.bvecs --brain_mask nodif_brain_mask.nii.gz   # calc_FA is part of TractSeg
    dwi_spacing=$(get_image_spacing Diffusion_denoise_unr_eddy_bias_brain.nii.gz)  # get_image_spacing is part of TractSeg
    atlas=$FSLDIR/data/standard/FMRIB58_FA_1mm.nii.gz

    #B0 2mm to MNI - mutualinfo working better
    flirt -ref $atlas -in FA.nii.gz -out FA_MNI.nii.gz -omat FA_2_MNI.mat -dof 6 -cost mutualinfo -searchcost mutualinfo -interp spline

    #Register DWI to MNI
    flirt -ref $atlas -in Diffusion_denoise_unr_eddy_bias_brain.nii.gz -out Diffusion_denoise_unr_eddy_bias_brain_MNI.nii.gz -applyisoxfm "$dwi_spacing" -init FA_2_MNI.mat -dof 6 -interp spline
    cp -v Diffusion_denoise_unr_eddy_bias_brain.bvals Diffusion_denoise_unr_eddy_bias_brain_MNI.bvals
    rotate_bvecs -i Diffusion_denoise_unr_eddy_bias_brain.bvecs -t FA_2_MNI.mat -o Diffusion_denoise_unr_eddy_bias_brain_MNI.bvecs

    # Transform brain mask to MNI space using the FA-to-MNI rigid transform
    flirt -ref $atlas -in nodif_brain_mask.nii.gz \
    -out nodif_brain_mask_MNI.nii.gz -applyisoxfm "$dwi_spacing" -init FA_2_MNI.mat -dof 6
    fslmaths nodif_brain_mask_MNI.nii.gz -thr 0.5 -bin nodif_brain_mask_MNI.nii.gz

    #Remove negative values (introduced by spline interpolation) is part of TractSeg
    remove_negative_values Diffusion_denoise_unr_eddy_bias_brain_MNI.nii.gz Diffusion_denoise_unr_eddy_bias_brain_MNI.nii.gz

    # Generate the final preprocessed DWI image and copy it to the brain directory.
    # The resulting brain/dwi_preprocessed.mif file was used as the input
    # for the subsequent fixel-based analysis (FBA) pipeline.

    cp -v Diffusion_denoise_unr_eddy_bias_brain_MNI.bvals ../brain/Diffusion.bvals
    cp -v Diffusion_denoise_unr_eddy_bias_brain_MNI.bvecs ../brain/Diffusion.bvecs
    cp -v Diffusion_denoise_unr_eddy_bias_brain_MNI.nii.gz ../brain/Diffusion.nii.gz
    mrconvert Diffusion_denoise_unr_eddy_bias_brain_MNI.nii.gz dwi_preprocessed.mif -fslgrad Diffusion_denoise_unr_eddy_bias_brain_MNI.bvecs Diffusion_denoise_unr_eddy_bias_brain_MNI.bvals -nthreads 8
    cp -v dwi_preprocessed.mif ../brain/dwi_preprocessed.mif
    cp -v nodif_brain_mask_MNI.nii.gz ../brain/nodif_brain_mask.nii.gz
}

function preprocessing_pipeline() {
    eddy_correct_extract_mask_denoise $1 $2
    register_DWI_to_MNI $1 $2
}

#todo: install the following
# - FSL
# - Ants (needed for dwibiascorrect)
# - mrtrix
# - tractseg

#todo: set path to your data (the folder you specify here must contain one folder for each subject)
data_path="$PWD"

#todo: list of all subject ID_session
while read -r i; do
    id="${i%_*}"
    ses="${i##*_}"

    echo "processing $i $id $ses"
    preprocessing_pipeline "$id" "$ses"
done < list
