#!/usr/bin/env python3

import argparse
import json
import math
import nibabel
import sys

def slicetimes_Philips_MB3(nslices, trsec):

    # Multiband factor (hard coded)
    F = 3

    # Number of multislice acquisitions
    M = nslices/F
    if M != int(M):
        raise Exception(f'Number of slice times {M} not a multiple of MB factor {F}')
    M = int(M)

    # List of actual slice acq times in temporal order
    basetimes = [x * trsec/M for x in list(range(M))]

    # Slice positions (1-based) in same order as basetimes
    slice1 = list(range(1, M+1, 2)) + list(range(2, M+1, 2))
    slice2 = [x + M for x in slice1]
    slice3 = [x + 2 * M for x in slice1]

    # Build a dict of slice position and acq time
    d = {
        **dict(zip(slice1, basetimes)),
        **dict(zip(slice2, basetimes)),
        **dict(zip(slice3, basetimes)),
        }

    # Sort slice times by slice position - this is our final BIDS-style
    # list of slice times
    slices = [k for k in sorted(d.keys())]
    if not slices==list(range(1, nslices + 1)):
        raise Exception('Unexpected mismatch in slice numbering')
    times_by_slice = [d[k] for k in sorted(d.keys())]

    return times_by_slice


def slicetimes_Philips_MB2_ASCEND(nslices, trsec):

    # Multiband factor (hard coded)
    F = 2

    # Number of multislice acquisitions
    M = nslices/F
    if M != int(M):
        raise Exception(f'Number of slice times {M} not a multiple of MB factor {F}')
    M = int(M)

    # List of actual slice acq times in temporal order
    basetimes = [x * trsec/M for x in list(range(M))]

    # Slice positions (1-based) in same order as basetimes
    slice1 = list(range(1, M+1, 1))
    slice2 = [x + M for x in slice1]

    # Build a dict of slice position and acq time
    d = {
        **dict(zip(slice1, basetimes)),
        **dict(zip(slice2, basetimes)),
        }

    # Sort slice times by slice position - this is our final BIDS-style
    # list of slice times
    slices = [k for k in sorted(d.keys())]
    if not slices==list(range(1, nslices + 1)):
        raise Exception('Unexpected mismatch in slice numbering')
    times_by_slice = [d[k] for k in sorted(d.keys())]

    return times_by_slice

    
## 

parser = argparse.ArgumentParser()
parser.add_argument('--fmri_niigz')
parser.add_argument('--polarity')
parser.add_argument('--intendedfor', nargs='*')
parser.add_argument('--slicetiming')
args = parser.parse_args()


jsonfile = args.fmri_niigz.replace('.nii.gz','.json')
with open(jsonfile) as f:
    jobj = json.loads(f.read())


## Phase encoding direction/info

# Verify that this is a Philips scan before applying the Philips-
# specific fixes for TotalReadoutTime and PhaseEncodingDirection
if not jobj['Manufacturer'].startswith('Philips'):
    raise Exception(f'Manufacturer is {jobj["Manufacturer"]} - expecting Philips')

# Update readout time
if not 'TotalReadoutTime' in jobj:
    if 'EstimatedTotalReadoutTime' in jobj:
        jobj['TotalReadoutTime'] = jobj['EstimatedTotalReadoutTime']
    else:
        # Use 0 for TotalReadoutTime
        jobj['TotalReadoutTime'] = 0

# Check for bogus PE dir with ? and remove if present
if ('PhaseEncodingDirection' in jobj) and (jobj['PhaseEncodingDirection'].endswith('?')):
    jobj['PhaseEncodingDirection'] = jobj['PhaseEncodingDirection'][:-1]

# Add PE polarity if we have PhaseEncodingAxis
if 'PhaseEncodingAxis' in jobj:
    if args.polarity=='+':
        jobj['PhaseEncodingDirection'] = jobj['PhaseEncodingAxis']
    elif args.polarity=='-':
        jobj['PhaseEncodingDirection'] = jobj['PhaseEncodingAxis'] + '-'
    else:
        raise Exception(f'Unknown polarity {args.polarity}')

if args.intendedfor:
    jobj['IntendedFor'] = args.intendedfor


## Slice timing
# Assumes slices are evenly spaced in the TR (i.e. not a sparse
# acquisition, and any extra inter-TR delay is minimal)

if args.slicetiming:

    # Get number of slices and TR from .nii.gz. Assume
    # slice axis is the third one.
    nii = nibabel.load(args.fmri_niigz)
    nslices = nii.header['dim'][3]
    tr = nii.header['pixdim'][4]

    # Check for existing
    if 'SliceTiming' in jobj:
        raise Exception(f'SliceTiming field exists in {jsonfile}')
    if 'SliceEncodingDirection' in jobj:
        raise Exception(f'SliceEncodingDirection field exists in {jsonfile}')

    # Get repetition time from .json to crosscheck
    tr2 = jobj['RepetitionTime']
    if abs(tr2-tr)>0.001:
        raise Exception(f'TR in {jsonfile} does not match {args.fmri_niigz}')

    # Special handling for Philips multiband factor 3
    if args.slicetiming in ['Philips_MB3_k']:
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = slicetimes_Philips_MB3(nslices, tr)

    # Special handling for Philips multiband factor 2 ASCEND
    elif args.slicetiming in ['Philips_MB2_ASCEND_k']:
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = slicetimes_Philips_MB2_ASCEND(nslices, tr)

    elif args.slicetiming in ['Philips_ASCEND_k', 'Siemens_ascending_k']:
        basetimes = [x / nslices * tr for x in range(0,nslices)]
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = basetimes

    elif args.slicetiming in ['Philips_DESCEND_k', 'Siemens_descending_k']:
        basetimes = [x / nslices * tr for x in range(0,nslices)]
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = list(reversed(basetimes))

    elif args.slicetiming in ['Siemens_interleaved_k']:
        basetimes = [x / nslices * tr for x in range(0,nslices)]
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = [0 for x in basetimes]
        if nslices % 2 == 0:  # Even number of slices
            jobj['SliceTiming'][1::2] = basetimes[0:math.ceil(nslices/2)]
            jobj['SliceTiming'][0::2] = basetimes[math.ceil(nslices/2):]
        else: # Odd number of slices
            jobj['SliceTiming'][0::2] = basetimes[0:math.ceil(nslices/2)]
            jobj['SliceTiming'][1::2] = basetimes[math.ceil(nslices/2):]

    elif args.slicetiming in ['GE_interleaved_k', 'Philips_DEFAULT_k']:
        basetimes = [x / nslices * tr for x in range(0,nslices)]
        jobj['SliceEncodingDirection'] = 'k'
        jobj['SliceTiming'] = [0 for x in basetimes]
        jobj['SliceTiming'][0::2] = basetimes[0:math.ceil(nslices/2)]
        jobj['SliceTiming'][1::2] = basetimes[math.ceil(nslices/2):]
        
    elif args.slicetiming in ['none']:
        pass

    else:
        raise Exception(f'Cannot handle slice timing of {args.slicetiming}')

## Print it out
print(json.dumps(jobj, indent = 4))
