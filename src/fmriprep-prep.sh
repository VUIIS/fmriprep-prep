#!/usr/bin/env bash
#
# Entrypoint for BIDS formatting

# Initialize default inputs
export t1_niigz=/INPUTS/t1.nii.gz
export fmri_niigzs=/INPUTS/fmri.nii.gz
export rpefwd_niigz=""
export rperev_niigz=""
export slicetiming=""
export bids_dir=/INPUTS/BIDS
export freesurfer_dir=
export sub=01
export ses=01
export task=

# Parse input options. Bit of extra gymnastics to allow multiple files
# for fMRIs. We will assume all .nii.gz have a matching .json sidecar
# in the same location with the same base filename.
t1_list=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in      
        --t1_niigz)       export t1_niigz="$2";       shift; shift ;;
        --rpefwd_niigz)   export rpefwd_niigz="$2";   shift; shift ;;
        --rperev_niigz)   export rperev_niigz="$2";   shift; shift ;;
        --bids_dir)       export bids_dir="$2";       shift; shift ;;
        --freesurfer_dir) export freesurfer_dir="$2"; shift; shift ;;
        --sub)            export sub="$2";            shift; shift ;;
        --ses)            export ses="$2";            shift; shift ;;
        --slicetiming)    export slicetiming="$2";    shift; shift ;;
        --task)           export task="$2";           shift; shift ;;
        --fmri_niigzs)
            next="$2"
            while ! [[ "$next" =~ -.* ]] && [[ $# > 1 ]]; do
                fmri_list+=("$next")
                shift
                next="$2"
            done
            shift ;;
        *) echo "Input ${1} not recognized"; shift ;;
    esac
done

# Count fmris
export num_fmris=${#fmri_list[@]}

# Show a bit of info
echo "Subject ${sub}, session ${ses}"
echo "T1: ${t1_niigz}"
echo "fMRIs (${num_fmris}): ${fmri_list[@]}"
if [ -n "${rpefwd_niigz}" ]; then
    echo "RPE forward: ${rpefwd_niigz}"
    echo "RPE reverse: ${rperev_niigz}"
else
    echo "RPE images not specified"
fi

# If slicetiming is 'ABIDE', use subject label to determine actual ordering
# and update the value of slicetiming
if [ "${slicetiming}" = "ABIDE" ]; then
    export slicetiming=$(slicetiming_ABIDE.py --subject_label "${sub}")
fi

# If subject, session have _ or -, drop it because it's not compatible with BIDS
# file naming
sub=${sub//-/}
sub=${sub//_/}
ses=${ses//-/}
ses=${ses//_/}

# If freesurfer_dir is specified, rename it by the sanitized subject name
if [[ -n "${freesurfer_dir}" ]]; then
    new_fsdir="$(dirname ${freesurfer_dir})/sub-${sub}"
    echo "Renaming ${freesurfer_dir} to ${new_fsdir}"
    mv "${freesurfer_dir}" "${new_fsdir}"
fi

# Rename and relocate files according to bids func/fmap scheme
# https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetic-resonance-imaging-data.html
# #case-4-multiple-phase-encoded-directions-pepolar

# We need to inject the PhaseEncodingDirection value for the +/- PE scans
# because Philips doesn't provide this in the dicoms and therefore dcm2niix
# doesn't either. We start with PhaseEncodingAxis and arbitrarily add
# a '-' on the scan that was labeled 'rev' above. This is done in update_json.py

# T1 scan
mkdir -p "${bids_dir}/sub-${sub}/ses-${ses}/anat"
t1_tag="sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w"
t1_json="${t1_niigz%.nii.gz}.json"
cp "${t1_niigz}" "${bids_dir}/${t1_tag}.nii.gz"
cp "${t1_json}" "${bids_dir}/${t1_tag}.json"

# fMRIs
mkdir -p "${bids_dir}/sub-${sub}/ses-${ses}/func"
intended_tags=
for fmri_niigz in ${fmri_list[@]}; do
    
    fmri_json="${fmri_niigz%.nii.gz}.json"
    if [ -z "${task}" ]; then
        task=$(get_sanitized_series_description.py --jsonfile "${fmri_json}")
    fi
    run=$(get_run.py --jsonfile "${fmri_json}")
    
    intended_tag="ses-${ses}/func/sub-${sub}_ses-${ses}_task-${task}_run-${run}_bold"
    fmri_tag="sub-${sub}/${intended_tag}"

    cp "${fmri_niigz}" "${bids_dir}/${fmri_tag}.nii.gz"
    update_json.py --fmri_niigz ${fmri_niigz} --polarity + --slicetiming "${slicetiming}" \
        > "${bids_dir}/${fmri_tag}.json"

    intended_tags=(${intended_tags[@]} "${intended_tag}.nii.gz")

done

# TOPUP scans if they exist
if [ -n "${rpefwd_niigz}" ]; then

    mkdir -p "${bids_dir}/sub-${sub}/ses-${ses}/fmap"

    rpefwd_json="${rpefwd_niigz%.nii.gz}.json"
    rpefwd_tag="sub-${sub}/ses-${ses}/fmap/sub-${sub}_ses-${ses}_dir-fwd_epi"
    cp "${rpefwd_niigz}" "${bids_dir}/${rpefwd_tag}.nii.gz"
    update_json.py --fmri_niigz ${rpefwd_niigz} --polarity + --intendedfor ${intended_tags[@]} \
        > "${bids_dir}/${rpefwd_tag}.json"

    rperev_json="${rperev_niigz%.nii.gz}.json"
    rperev_tag="sub-${sub}/ses-${ses}/fmap/sub-${sub}_ses-${ses}_dir-rev_epi"
    cp "${rperev_niigz}" "${bids_dir}/${rperev_tag}.nii.gz"
    update_json.py --fmri_niigz ${rperev_niigz} --polarity - --intendedfor ${intended_tags[@]} \
        > "${bids_dir}/${rperev_tag}.json"

fi

# Finally, the required dataset description file
echo '{"Name": "Ready for fmriprep", "BIDSVersion": "1.9.0"}' > "${bids_dir}/dataset_description.json"

