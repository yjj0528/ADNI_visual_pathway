#!/bin/bash
set -e

###############################################################################
# Visual pathway tractography in the study-specific template space
#
# Manual ROI preparation:
#
# The bilateral lateral geniculate nuclei (LGN) and optic chiasm (OC) were
# manually identified in the study-specific template space based on anatomical
# landmarks.
#
# The center coordinates of the manually identified LGN were used to define
# 4-mm-radius spherical seed regions for both optic radiation (OR) and optic
# tract (OT) tractography.
#
# The optic chiasm was manually delineated using ITK-SNAP and saved as:
#   OC.nii.gz
#
# The OC ROI was used as an inclusion/waypoint region for OT tractography.
#
# OR tractography:
#   Seed       : 4-mm-radius LGN sphere
#   Constraint : HCP-1065-derived OR anatomical mask
#
# OT tractography:
#   Seed       : 4-mm-radius LGN sphere
#   Waypoint   : manually delineated OC ROI
#
# A two-stage tractography procedure was used.
# For the OR, the initial track-density images were binarized without applying
# an additional streamline-density threshold. For the OT, the initial track-density images were thresholded at 10% of
# their maximum TDI value before binarization to reduce low-density peripheral
# voxels. The resulting binary masks were used as spatial constraints for
# second-stage tractography.
#
# Tractography algorithm:
#   The original analysis used the default probabilistic iFOD2 algorithm.
#   No explicit -step option was specified. Because the study-specific FOD
#   template had 1.3-mm isotropic voxel size, the default iFOD2 step size was
#   0.65 mm (0.5 x voxel size).
#
# Final outputs:
#   seg_ORs.nii.gz
#   seg_OTs.nii.gz
#
# Label convention:
#   Left  = 1
#   Right = 2
###############################################################################


# -----------------------------------------------------------------------------
# Set paths
# -----------------------------------------------------------------------------

data_path="$PWD"
template_dir="${data_path}/template"

cd "${template_dir}"


# -----------------------------------------------------------------------------
# Manually identified LGN center coordinates in study-specific template space
# -----------------------------------------------------------------------------

LGN_L="-22.8769,-22.6809,-7.66732"
LGN_R="24.9393,-20.4004,-8.15803"
LGN_RADIUS=4


# -----------------------------------------------------------------------------
# Check required inputs
# -----------------------------------------------------------------------------

required_files=(
    "wmfod_template.mif"
    "wmfod_template0.nii.gz"
    "OR_Ldil.nii.gz"
    "OR_Rdil.nii.gz"
    "OC.nii.gz"
)

for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required file not found: $f"
        exit 1
    fi
done


###############################################################################
# Step 1. First-stage optic radiation (OR) tractography
#
###############################################################################

echo "Running first-stage OR tractography..."

tckgen \
    wmfod_template.mif \
    tck_OR_L1.tck \
    -seed_sphere ${LGN_L},${LGN_RADIUS} \
    -mask OR_Ldil.nii.gz \
    -select 5000 \
    -maxlength 120 \
    -minlength 70 \
    -angle 22.5 \
    -cutoff 0.05 \
    -seed_unidirectional

tckgen \
    wmfod_template.mif \
    tck_OR_R1.tck \
    -seed_sphere ${LGN_R},${LGN_RADIUS} \
    -mask OR_Rdil.nii.gz \
    -select 5000 \
    -maxlength 120 \
    -minlength 70 \
    -angle 22.5 \
    -cutoff 0.05 \
    -seed_unidirectional


###############################################################################
# Step 2. First-stage optic tract (OT) tractography
#
###############################################################################

echo "Running first-stage OT tractography..."

tckgen \
    wmfod_template.mif \
    tck_OT_L1.tck \
    -seed_sphere ${LGN_L},${LGN_RADIUS} \
    -include OC.nii.gz \
    -select 500 \
    -maxlength 50 \
    -angle 45 \
    -cutoff 0.05 \
    -seed_unidirectional

tckgen \
    wmfod_template.mif \
    tck_OT_R1.tck \
    -seed_sphere ${LGN_R},${LGN_RADIUS} \
    -include OC.nii.gz \
    -select 500 \
    -maxlength 50 \
    -angle 45 \
    -cutoff 0.05 \
    -seed_unidirectional


echo "Generating first-stage tract-density images and binary masks..."


###############################################################################
# Step 3A. OR: binarization without additional density threshold
#
###############################################################################

or_tracks=(
    "tck_OR_L1.tck"
    "tck_OR_R1.tck"
)

for g in "${or_tracks[@]}"; do

    base="${g%.tck}"

    echo "Processing OR: ${g}"

    tckmap \
        "${g}" \
        "${base}.mif" \
        -template wmfod_template0.nii.gz

    mrconvert \
        "${base}.mif" \
        "${base}.nii.gz"

    # Retain every voxel traversed by at least one streamline
    fslmaths \
        "${base}.nii.gz" \
        -bin \
        "${base}_bin.nii.gz"

done


###############################################################################
# Step 3B. OT: apply 10% of maximum TDI threshold before binarization
#
###############################################################################

OT_THRESHOLD_PERCENT=10

ot_tracks=(
    "tck_OT_L1.tck"
    "tck_OT_R1.tck"
)

for g in "${ot_tracks[@]}"; do

    base="${g%.tck}"

    echo "Processing OT: ${g}"

    tckmap \
        "${g}" \
        "${base}.mif" \
        -template wmfod_template0.nii.gz

    mrconvert \
        "${base}.mif" \
        "${base}.nii.gz"

    # Obtain maximum streamline-density value
    maxval=$(mrstats "${base}.mif" -output max)

    # Calculate 10% of the maximum
    threshold=$(awk \
        -v max="${maxval}" \
        -v pct="${OT_THRESHOLD_PERCENT}" \
        'BEGIN {printf "%.8f", max*pct/100}')

    echo "  Maximum TDI value : ${maxval}"
    echo "  OT threshold      : ${threshold} (${OT_THRESHOLD_PERCENT}% of maximum)"

    # Retain voxels with TDI >= 10% of the maximum and binarize
    fslmaths \
        "${base}.nii.gz" \
        -thr "${threshold}" \
        -bin \
        "${base}_bin.nii.gz"

done



###############################################################################
# Step 4. Second-stage optic radiation (OR) tractography
#
# The first-stage tractography-derived binary masks are used as spatial
# constraints. The same tracking parameters and number of selected streamlines
# as in the first-stage tractography are retained.
###############################################################################

echo "Running second-stage OR tractography..."

tckgen \
    wmfod_template.mif \
    tck_OR_L2.tck \
    -seed_sphere ${LGN_L},${LGN_RADIUS} \
    -mask tck_OR_L1_bin.nii.gz \
    -select 5000 \
    -maxlength 120 \
    -minlength 70 \
    -angle 22.5 \
    -cutoff 0.05 \
    -seed_unidirectional

tckgen \
    wmfod_template.mif \
    tck_OR_R2.tck \
    -seed_sphere ${LGN_R},${LGN_RADIUS} \
    -mask tck_OR_R1_bin.nii.gz \
    -select 5000 \
    -maxlength 120 \
    -minlength 70 \
    -angle 22.5 \
    -cutoff 0.05 \
    -seed_unidirectional


###############################################################################
# Step 5. Second-stage optic tract (OT) tractography
#
# The manually delineated OC remains the inclusion/waypoint region, while
# the first-stage OT binary masks are additionally used as spatial constraints.
###############################################################################

echo "Running second-stage OT tractography..."

tckgen \
    wmfod_template.mif \
    tck_OT_L2.tck \
    -seed_sphere ${LGN_L},${LGN_RADIUS} \
    -include OC.nii.gz \
    -mask tck_OT_L1_bin.nii.gz \
    -select 500 \
    -maxlength 50 \
    -angle 45 \
    -cutoff 0.05 \
    -seed_unidirectional

tckgen \
    wmfod_template.mif \
    tck_OT_R2.tck \
    -seed_sphere ${LGN_R},${LGN_RADIUS} \
    -include OC.nii.gz \
    -mask tck_OT_R1_bin.nii.gz \
    -select 500 \
    -maxlength 50 \
    -angle 45 \
    -cutoff 0.05 \
    -seed_unidirectional


###############################################################################
# Step 6. Generate final binary tract masks
###############################################################################

echo "Generating final tract-density images and binary masks..."

second_stage_tracks=(
    "tck_OR_L2.tck"
    "tck_OR_R2.tck"
    "tck_OT_L2.tck"
    "tck_OT_R2.tck"
)

for g in "${second_stage_tracks[@]}"; do

    base="${g%.tck}"

    echo "Processing ${g}"

    tckmap \
        "${g}" \
        "${base}.mif" \
        -template wmfod_template0.nii.gz

    mrconvert \
        "${base}.mif" \
        "${base}.nii.gz"

    fslmaths \
        "${base}.nii.gz" \
        -bin \
        "${base}_bin.nii.gz"

done


###############################################################################
# Step 7. Merge left and right final tract masks
#   Left  = 1
#   Right = 2
###############################################################################

echo "Generating bilateral OR and OT masks..."

fslmaths \
    tck_OR_R2_bin.nii.gz \
    -mul 2 \
    -add tck_OR_L2_bin.nii.gz \
    seg_ORs.nii.gz

fslmaths \
    tck_OT_R2_bin.nii.gz \
    -mul 2 \
    -add tck_OT_L2_bin.nii.gz \
    seg_OTs.nii.gz


echo "=============================================================="
echo "Visual pathway tractography completed."
echo
echo "Final outputs:"
echo "  ${template_dir}/seg_ORs.nii.gz"
echo "  ${template_dir}/seg_OTs.nii.gz"
echo
echo "Label convention:"
echo "  Left  = 1"
echo "  Right = 2"
echo "=============================================================="


