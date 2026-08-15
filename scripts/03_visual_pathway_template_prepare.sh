#!/bin/bash
set -e

###############################################################################
# Prepare study-specific template space for visual pathway tractography
#
# This script prepares the optic-radiation (OR) anatomical masks in the
# study-specific template space.
#
# Inputs:
#   template/wmfod_template.mif
#   dwinormalise/fa_template.mif
#   template/nifti/FSL_HCP1065_FA_1mm.nii.gz
#   template/nifti/projection/OR_L.nii.gz
#   template/nifti/projection/OR_R.nii.gz
#
# Main steps:
#   1. Extract the first SH coefficient volume from the study-specific FOD
#      template to define its spatial grid.
#   2. Regrid the study-specific FA template to the FOD-template grid
#      (1.3-mm isotropic resolution).
#   3. Regrid HCP-1065 OR masks to the HCP-1065 FA template grid.
#   4. Register the HCP-1065 FA template to the study-specific FA template.
#   5. Transform left and right HCP-1065 OR masks to the study-specific
#      template space.
#   6. Generate dilated and non-dilated bilateral OR masks.
#
# Outputs:
#   template/wmfod_template0.nii.gz
#   template/fa_template0.nii.gz
#   template/OR_left.nii.gz
#   template/OR_right.nii.gz
#   template/OR_Ldil.nii.gz
#   template/OR_Rdil.nii.gz
#   template/OR_initial.nii.gz
###############################################################################


# -----------------------------------------------------------------------------
# Set paths
# -----------------------------------------------------------------------------

data_path="$PWD"
template_dir="${data_path}/template"
dwinorm_dir="${data_path}/dwinormalise"
hcp_dir="${template_dir}/nifti"

cd "${template_dir}"


###############################################################################
# Step 1. Extract the first SH coefficient volume from the FOD template
#
###############################################################################

echo "Extracting FOD-template reference volume..."

mrconvert \
    wmfod_template.mif \
    wmfod_template0.nii.gz \
    -coord 3 0 \
    -force


###############################################################################
# Step 2. Regrid the study-specific FA template to the FOD-template grid
#
###############################################################################

echo "Regridding study-specific FA template to FOD-template space..."

mrgrid \
    "${dwinorm_dir}/fa_template.mif" \
    regrid \
    -template wmfod_template0.nii.gz \
    fa_template0.nii.gz \
    -force


###############################################################################
# Step 3. Regrid HCP-1065 OR masks to the HCP-1065 FA template grid
#
###############################################################################

echo "Regridding HCP-1065 OR masks..."

mrgrid \
    "${hcp_dir}/projection/OR_L.nii.gz" \
    regrid \
    -template "${hcp_dir}/FSL_HCP1065_FA_1mm.nii.gz" \
    -interp nearest \
    "${hcp_dir}/FSL_HCP1065_OR_L.nii.gz" \
    -force

mrgrid \
    "${hcp_dir}/projection/OR_R.nii.gz" \
    regrid \
    -template "${hcp_dir}/FSL_HCP1065_FA_1mm.nii.gz" \
    -interp nearest \
    "${hcp_dir}/FSL_HCP1065_OR_R.nii.gz" \
    -force


###############################################################################
# Step 4. Register the HCP-1065 FA template to the study-specific FA template
#
###############################################################################

echo "Registering HCP-1065 FA template to study-specific FA template..."

antsRegistrationSyNQuick.sh \
    -d 3 \
    -p f \
    -t s \
    -f fa_template0.nii.gz \
    -m "${hcp_dir}/FSL_HCP1065_FA_1mm.nii.gz" \
    -o hcp2fa_template


antsRegistrationSyNQuick.sh \
    -d 3 \
    -p f \
    -t s \
    -f wmfod_template0.nii.gz \
    -m "${hcp_dir}/MNI152_T1_1mm.nii.gz" \
    -o mni2wm_template
    

###############################################################################
# Step 5. Transform HCP-1065 OR masks to the study-specific template space
#

###############################################################################

echo "Transforming HCP-1065 OR masks to study-specific template space..."

antsApplyTransforms \
    -d 3 \
    -i "${hcp_dir}/FSL_HCP1065_OR_L.nii.gz" \
    -r fa_template0.nii.gz \
    -t hcp2fa_template1Warp.nii.gz \
    -t hcp2fa_template0GenericAffine.mat \
    -n NearestNeighbor \
    -o OR_left.nii.gz

antsApplyTransforms \
    -d 3 \
    -i "${hcp_dir}/FSL_HCP1065_OR_R.nii.gz" \
    -r fa_template0.nii.gz \
    -t hcp2fa_template1Warp.nii.gz \
    -t hcp2fa_template0GenericAffine.mat \
    -n NearestNeighbor \
    -o OR_right.nii.gz


###############################################################################
# Step 6. Generate dilated OR masks for tractography constraints
#
###############################################################################

echo "Generating dilated OR masks..."

fslmaths OR_left.nii.gz  -dilD OR_Ldil.nii.gz
fslmaths OR_right.nii.gz -dilD OR_Rdil.nii.gz


echo "=============================================================="
echo "Visual pathway template preparation completed."
echo
echo "Main outputs:"
echo "  ${template_dir}/wmfod_template0.nii.gz"
echo "  ${template_dir}/fa_template0.nii.gz"
echo "  ${template_dir}/OR_left.nii.gz"
echo "  ${template_dir}/OR_right.nii.gz"
echo "  ${template_dir}/OR_Ldil.nii.gz"
echo "  ${template_dir}/OR_Rdil.nii.gz"
echo "  ${template_dir}/OR_initial.nii.gz"
echo "=============================================================="
