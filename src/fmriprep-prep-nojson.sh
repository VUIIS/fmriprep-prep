#!/usr/bin/env bash
#
# Entrypoint for BIDS formatting

# Initialize default inputs
export t1_niigz=/INPUTS/t1.nii.gz
export fmri_niigzs=/INPUTS/fmri.nii.gz
export rpefwd_niigz=""
export rperev_niigz=""
export slicetiming=""
export fmritask=fmritask
export bids_dir=/INPUTS/BIDS
export freesurfer_dir=
export sub=01
export ses=01

# Parse input options. Bit of extra gymnastics to allow multiple files
# for fMRIs. We will assume no .nii.gz have the matching .json sidecar,
# so will create those from scratch in the same location with the same 
# base filename.
t1_list=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in      
        --t1_niigz)       export t1_niigz="$2";       shift; shift ;;
        --rpefwd_niigz)   export rpefwd_niigz="$2";   shift; shift ;;
        --rperev_niigz)   export rperev_niigz="$2";   shift; shift ;;
        --bids_dir)       export bids_dir="$2";       shift; shift ;;
        --sub)            export sub="$2";            shift; shift ;;
        --ses)            export ses="$2";            shift; shift ;;
        --slicetiming)    export slicetiming="$2";    shift; shift ;;
        --fmritask)       export fmritask="$2";       shift; shift ;;
        --freesurfer_dir) export freesurfer_dir="$2"; shift; shift ;;
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


# If slicetiming is 'ABIDE', use subject label to determine actual ordering
# and update the value of slicetiming
if [ "${slicetiming}" = "ABIDE" ]; then
    export slicetiming=$(slicetiming_ABIDE.py --subject_label "${sub}")
fi

# If subject, session have _, drop it because it's not compatible with BIDS
# file naming
sub=${sub//_/}
sub=${sub//-/}
ses=${ses//_/}
ses=${ses//-/}

# If freesurfer_dir is specified, rename it by the sanitized subject name
if [[ -n "${freesurfer_dir}" ]]; then
    new_fsdir="$(dirname ${freesurfer_dir})/sub-${sub}"
    echo "Renaming ${freesurfer_dir} to ${new_fsdir}"
    mv "${freesurfer_dir}" "${new_fsdir}"
fi

# Rename and relocate files according to bids scheme

# T1 scan
mkdir -p "${bids_dir}/sub-${sub}/ses-${ses}/anat"
t1_tag="sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w"
cp "${t1_niigz}" "${bids_dir}/${t1_tag}.nii.gz"

# fMRIs
fmrirun=$((0))
mkdir -p "${bids_dir}/sub-${sub}/ses-${ses}/func"
for fmri_niigz in ${fmri_list[@]}; do
    
    fmri_json="${fmri_niigz%.nii.gz}.json"
    
    # Start run at 1 and count up since we don't have json to get it from
    (( fmrirun++ ))
    intended_tag="ses-${ses}/func/sub-${sub}_ses-${ses}_task-${fmritask}_run-${fmrirun}_bold"
    fmri_tag="sub-${sub}/${intended_tag}"

    cp "${fmri_niigz}" "${bids_dir}/${fmri_tag}.nii.gz"
    create_json.py --fmri_niigz ${fmri_niigz} --slicetiming "${slicetiming}" \
        > "${bids_dir}/${fmri_tag}.json"

done

# Finally, the required dataset description file
echo '{"Name": "Ready for fmriprep", "BIDSVersion": "1.9.0"}' > "${bids_dir}/dataset_description.json"

