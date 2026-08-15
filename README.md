# ADNI Visual Pathway Tractography Pipeline

This repository contains the custom computational pipeline used for
template-based reconstruction of the optic radiation (OR) and optic tract (OT)
and extraction of subject-level diffusion tensor imaging (DTI) measures.

The pipeline was developed for the visual pathway analysis performed in an
Alzheimer's Disease Neuroimaging Initiative (ADNI) study.

## Overview

The analysis consists of five main stages:

1. DWI preprocessing
2. FOD estimation and generation of a study-specific template
3. Preparation of anatomical masks in the study-specific template space
4. Template-based OR and OT tractography
5. Transformation of tract masks to individual diffusion space and extraction
   of diffusion measures

The main diffusion measures extracted from the OR and OT are:

- Fractional anisotropy (FA)
- Mean diffusivity (MD)
- Axial diffusivity (AD; referred to as AxD in the manuscript)
- Radial diffusivity (RD)

## Scripts

### 01_dwi_preproc_adni.sh

Performs DWI preprocessing, including:

- DWI denoising
- Gibbs-ringing correction
- Eddy-current and head-motion correction
- Bias-field correction
- Brain masking
- Rigid registration to MNI space
- Gradient-vector rotation

The resulting `dwi_preprocessed.mif` file is used as the input for the
subsequent FBA-based processing.

This script was adapted and modified from the DWI preprocessing utility script
provided by TractSeg. The original TractSeg project is distributed under the
Apache License 2.0.

### 02_fba_group_template.sh

Performs FOD estimation and generates the study-specific template using
MRtrix3.

The main steps include:

- Tissue response-function estimation
- Group-average response-function estimation
- DWI upsampling to 1.3-mm isotropic resolution
- Brain-mask generation
- Multi-tissue constrained spherical deconvolution (MSMT-CSD)
- Multi-tissue intensity normalization
- Study-specific unbiased FOD template generation
- Subject-to-template and template-to-subject nonlinear registration
- Study-specific FA template generation

The study-specific FOD template was generated from a balanced subset of
30 participants: 10 cognitively normal controls, 10 participants with mild
cognitive impairment, and 10 participants with Alzheimer's disease.

### 03_visual_pathway_template_prepare.sh

Prepares the anatomical reference masks for visual pathway tractography.

An optic-radiation anatomical mask derived from the HCP-1065 Young Adult
Fiber Template is transformed to the study-specific template space using
nonlinear registration between the HCP-1065 FA template and the
study-specific FA template.

The transformed left and right OR masks are used as anatomical constraints
for subsequent OR tractography.

### 04_visual_pathway_tractography.sh

Performs probabilistic tractography of the OR and OT in the study-specific
FOD template space.

The bilateral lateral geniculate nuclei (LGN) and optic chiasm (OC) were
manually identified in the study-specific template space based on anatomical
landmarks.

For the OR:

- A 4-mm-radius spherical LGN seed is used.
- The HCP-1065-derived OR anatomical mask is used as the tract constraint.
- 5,000 streamlines are generated for each hemisphere.

For the OT:

- A 4-mm-radius spherical LGN seed is used.
- The manually delineated OC is used as an inclusion region.
- 500 streamlines are generated for each hemisphere.

Probabilistic tractography is performed using the iFOD2 algorithm.

A two-stage tractography procedure is used to refine the spatial extent of
the reconstructed tracts. First-stage tractograms are converted to
track-density images (TDI).

For the OR, the TDI is directly binarized without an additional
streamline-density threshold.

For the OT, voxels below 10% of the maximum TDI value are removed before
binarization.

The resulting binary masks are used as spatial constraints for the
second-stage tractography.

### 05_subject_level_visual_pathway_metrics.sh

Transforms the final template-space OR and OT masks to each participant's
1.3-mm upsampled diffusion space using the template-to-subject nonlinear
transform generated during the FBA workflow.

Diffusion tensors are fitted to the 1.3-mm upsampled DWI data, and FA, MD,
AD, and RD maps are generated.

Mean FA, MD, AD, and RD values are then calculated within the left and right
OR and OT masks.

The final subject-level diffusion measures are written to a CSV file.


## Software requirements

The original analysis was performed in a Linux environment (Ubuntu 20.04 LTS)
using the following software:

- MRtrix3
- FSL
- ANTs
- TractSeg
- ITK-SNAP

Software versions that could be verified from the original analysis records
are documented in:

`docs/software_versions.md`


## External resources

The optic-radiation anatomical masks were derived from the HCP-1065 Young
Adult Fiber Template:

https://brain.labsolver.org/hcp_template.html

The FOD-template generation workflow was based on the MRtrix3 fixel-based
analysis framework.

The DWI preprocessing script was adapted from the preprocessing utility
distributed with TractSeg:

https://github.com/MIC-DKFZ/TractSeg

## Data availability

Imaging data are not distributed with this repository.

The imaging data used in the study were obtained from the Alzheimer's Disease
Neuroimaging Initiative (ADNI) and remain subject to the applicable ADNI
data-use and access requirements.

The repository contains analysis scripts only and does not contain
participant-level imaging data or identifying information.

## Reproducibility notes

The pipeline reflects the computational workflow used for the visual pathway
analysis in the associated study.

Manual identification of the bilateral LGN and delineation of the optic
chiasm are required before visual pathway tractography.

Users should verify image orientation, spatial registration, brain masks,
tract reconstruction, and transformed tract masks when applying the pipeline
to other datasets.

## Citation

Citation information for this software is provided in `CITATION.cff`.

A permanent DOI for the archived release will be provided through Zenodo.

## License

See the `LICENSE` file for licensing information and attribution of
third-party code.

