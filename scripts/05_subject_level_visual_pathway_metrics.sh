#!/bin/bash
set -e

###############################################################################
# Subject-level visual pathway diffusion metric extraction
#
# This script:
#
#   1. Calculates subject-specific diffusion tensor maps:
#        FA, MD, AD, and RD
#
#   2. Transforms the final template-space visual pathway masks
#      (OR_L, OR_R, OT_L, OT_R) into each subject's diffusion space
#      using the template-to-subject nonlinear warp generated during FBA.
#
#   3. Calculates the mean FA, MD, AD, and RD values within each
#      subject-specific visual pathway mask.
#
# Required subject-level inputs:
#
#   subjects/<subject>/
#       dwi_denoised_unringed_preproc_unbiased_upsampled.mif
#       dwi_mask_upsampled.mif
#       template2subject_warp.mif
#
# Required template-space tract masks:
#
#   template/
#       tck_OR_L2_bin.nii.gz
#       tck_OR_R2_bin.nii.gz
#       tck_OT_L2_bin.nii.gz
#       tck_OT_R2_bin.nii.gz
#
# Outputs:
#
#   subjects/<subject>/diffusion_metrics/
#       FA.mif
#       MD.mif
#       AD.mif
#       RD.mif
#
#   subjects/<subject>/visual_pathway_native/
#       OR_L.nii.gz
#       OR_R.nii.gz
#       OT_L.nii.gz
#       OT_R.nii.gz
#
#   visual_pathway_diffusion_metrics.csv
#
# NOTE:
# AD corresponds to axial diffusivity (AxD) in the manuscript.
###############################################################################


# -----------------------------------------------------------------------------
# Set paths
# -----------------------------------------------------------------------------

data_path="$PWD"

subjects_dir="${data_path}/subjects"
template_dir="${data_path}/template"

output_csv="${data_path}/visual_pathway_diffusion_metrics.csv"


# -----------------------------------------------------------------------------
# Check template-space tract masks
# -----------------------------------------------------------------------------

template_masks=(
    "tck_OR_L2_bin.nii.gz"
    "tck_OR_R2_bin.nii.gz"
    "tck_OT_L2_bin.nii.gz"
    "tck_OT_R2_bin.nii.gz"
)

for mask in "${template_masks[@]}"; do
    if [[ ! -f "${template_dir}/${mask}" ]]; then
        echo "ERROR: Template-space tract mask not found:"
        echo "  ${template_dir}/${mask}"
        exit 1
    fi
done


# -----------------------------------------------------------------------------
# Initialize output CSV
# -----------------------------------------------------------------------------

echo "Subject,OR_L_FA,OR_L_MD,OR_L_AD,OR_L_RD,OR_R_FA,OR_R_MD,OR_R_AD,OR_R_RD,OT_L_FA,OT_L_MD,OT_L_AD,OT_L_RD,OT_R_FA,OT_R_MD,OT_R_AD,OT_R_RD" \
    > "${output_csv}"


###############################################################################
# Process each subject
#
###############################################################################

for subject_dir in "${subjects_dir}"/*; do

    [[ -d "${subject_dir}" ]] || continue

    subject=$(basename "${subject_dir}")

    echo
    echo "=============================================================="
    echo "Processing subject: ${subject}"
    echo "=============================================================="


    # -------------------------------------------------------------------------
    # Required subject-level files
    # -------------------------------------------------------------------------

    dwi="${subject_dir}/dwi_denoised_unringed_preproc_unbiased_upsampled.mif"
    brain_mask="${subject_dir}/dwi_mask_upsampled.mif"
    warp="${subject_dir}/template2subject_warp.mif"

    for f in "${dwi}" "${brain_mask}" "${warp}"; do
        if [[ ! -f "${f}" ]]; then
            echo "ERROR: Required file not found:"
            echo "  ${f}"
            exit 1
        fi
    done


    # -------------------------------------------------------------------------
    # Output directories
    # -------------------------------------------------------------------------

    metric_dir="${subject_dir}/diffusion_metrics"
    tract_dir="${subject_dir}/visual_pathway_native"

    mkdir -p "${metric_dir}"
    mkdir -p "${tract_dir}"


    ###########################################################################
    # Step 1. Fit the diffusion tensor
    ###########################################################################

    echo "Fitting diffusion tensor..."

    dwi2tensor \
        "${dwi}" \
        "${metric_dir}/tensor.mif" \
        -mask "${brain_mask}" \
        -force


    ###########################################################################
    # Step 2. Calculate FA, MD, AD, and RD maps
    #
    # MRtrix3 tensor2metric options:
    #
    #   -fa   : fractional anisotropy
    #   -adc  : mean diffusivity / apparent diffusion coefficient
    #   -ad   : axial diffusivity
    #   -rd   : radial diffusivity
    ###########################################################################

    echo "Generating diffusion tensor metric maps..."

    tensor2metric \
        "${metric_dir}/tensor.mif" \
        -fa  "${metric_dir}/FA.mif" \
        -adc "${metric_dir}/MD.mif" \
        -ad  "${metric_dir}/AD.mif" \
        -rd  "${metric_dir}/RD.mif" \
        -mask "${brain_mask}" \
        -force


    ###########################################################################
    # Step 3. Transform final template-space tract masks to subject space
    # The upsampled subject DWI is used as the target image grid.
    ###########################################################################

    echo "Transforming visual pathway masks to subject diffusion space..."


    # OR - Left
    mrtransform \
        "${template_dir}/tck_OR_L2_bin.nii.gz" \
        -warp "${warp}" \
        -template "${dwi}" \
        -interp nearest \
        -datatype bit \
        "${tract_dir}/OR_L.nii.gz" \
        -force


    # OR - Right
    mrtransform \
        "${template_dir}/tck_OR_R2_bin.nii.gz" \
        -warp "${warp}" \
        -template "${dwi}" \
        -interp nearest \
        -datatype bit \
        "${tract_dir}/OR_R.nii.gz" \
        -force


    # OT - Left
    mrtransform \
        "${template_dir}/tck_OT_L2_bin.nii.gz" \
        -warp "${warp}" \
        -template "${dwi}" \
        -interp nearest \
        -datatype bit \
        "${tract_dir}/OT_L.nii.gz" \
        -force


    # OT - Right
    mrtransform \
        "${template_dir}/tck_OT_R2_bin.nii.gz" \
        -warp "${warp}" \
        -template "${dwi}" \
        -interp nearest \
        -datatype bit \
        "${tract_dir}/OT_R.nii.gz" \
        -force


    ###########################################################################
    # Step 4. Extract mean diffusion metrics within each tract
    ###########################################################################

    echo "Extracting tract-specific mean diffusion measures..."


    # -------------------------------------------------------------------------
    # OR Left
    # -------------------------------------------------------------------------

    OR_L_FA=$(mrstats "${metric_dir}/FA.mif" \
        -mask "${tract_dir}/OR_L.nii.gz" \
        -output mean)

    OR_L_MD=$(mrstats "${metric_dir}/MD.mif" \
        -mask "${tract_dir}/OR_L.nii.gz" \
        -output mean)

    OR_L_AD=$(mrstats "${metric_dir}/AD.mif" \
        -mask "${tract_dir}/OR_L.nii.gz" \
        -output mean)

    OR_L_RD=$(mrstats "${metric_dir}/RD.mif" \
        -mask "${tract_dir}/OR_L.nii.gz" \
        -output mean)


    # -------------------------------------------------------------------------
    # OR Right
    # -------------------------------------------------------------------------

    OR_R_FA=$(mrstats "${metric_dir}/FA.mif" \
        -mask "${tract_dir}/OR_R.nii.gz" \
        -output mean)

    OR_R_MD=$(mrstats "${metric_dir}/MD.mif" \
        -mask "${tract_dir}/OR_R.nii.gz" \
        -output mean)

    OR_R_AD=$(mrstats "${metric_dir}/AD.mif" \
        -mask "${tract_dir}/OR_R.nii.gz" \
        -output mean)

    OR_R_RD=$(mrstats "${metric_dir}/RD.mif" \
        -mask "${tract_dir}/OR_R.nii.gz" \
        -output mean)


    # -------------------------------------------------------------------------
    # OT Left
    # -------------------------------------------------------------------------

    OT_L_FA=$(mrstats "${metric_dir}/FA.mif" \
        -mask "${tract_dir}/OT_L.nii.gz" \
        -output mean)

    OT_L_MD=$(mrstats "${metric_dir}/MD.mif" \
        -mask "${tract_dir}/OT_L.nii.gz" \
        -output mean)

    OT_L_AD=$(mrstats "${metric_dir}/AD.mif" \
        -mask "${tract_dir}/OT_L.nii.gz" \
        -output mean)

    OT_L_RD=$(mrstats "${metric_dir}/RD.mif" \
        -mask "${tract_dir}/OT_L.nii.gz" \
        -output mean)


    # -------------------------------------------------------------------------
    # OT Right
    # -------------------------------------------------------------------------

    OT_R_FA=$(mrstats "${metric_dir}/FA.mif" \
        -mask "${tract_dir}/OT_R.nii.gz" \
        -output mean)

    OT_R_MD=$(mrstats "${metric_dir}/MD.mif" \
        -mask "${tract_dir}/OT_R.nii.gz" \
        -output mean)

    OT_R_AD=$(mrstats "${metric_dir}/AD.mif" \
        -mask "${tract_dir}/OT_R.nii.gz" \
        -output mean)

    OT_R_RD=$(mrstats "${metric_dir}/RD.mif" \
        -mask "${tract_dir}/OT_R.nii.gz" \
        -output mean)


    ###########################################################################
    # Step 5. Save subject-level results
    ###########################################################################

    echo "${subject},${OR_L_FA},${OR_L_MD},${OR_L_AD},${OR_L_RD},${OR_R_FA},${OR_R_MD},${OR_R_AD},${OR_R_RD},${OT_L_FA},${OT_L_MD},${OT_L_AD},${OT_L_RD},${OT_R_FA},${OT_R_MD},${OT_R_AD},${OT_R_RD}" \
        >> "${output_csv}"


    # Optional subject-specific result file
    subject_csv="${subject_dir}/visual_pathway_diffusion_metrics.csv"

    echo "Tract,FA,MD,AD,RD" > "${subject_csv}"

    echo "OR_L,${OR_L_FA},${OR_L_MD},${OR_L_AD},${OR_L_RD}" \
        >> "${subject_csv}"

    echo "OR_R,${OR_R_FA},${OR_R_MD},${OR_R_AD},${OR_R_RD}" \
        >> "${subject_csv}"

    echo "OT_L,${OT_L_FA},${OT_L_MD},${OT_L_AD},${OT_L_RD}" \
        >> "${subject_csv}"

    echo "OT_R,${OT_R_FA},${OT_R_MD},${OT_R_AD},${OT_R_RD}" \
        >> "${subject_csv}"


    echo "Completed: ${subject}"

done


echo
echo "=============================================================="
echo "Subject-level visual pathway analysis completed."
echo
echo "Group-level output:"
echo "  ${output_csv}"
echo
echo "Per-subject outputs:"
echo "  subjects/<subject>/diffusion_metrics/"
echo "  subjects/<subject>/visual_pathway_native/"
echo "  subjects/<subject>/visual_pathway_diffusion_metrics.csv"
echo "=============================================================="
