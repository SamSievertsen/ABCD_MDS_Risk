#!/usr/bin/env bash

## 2.1_run_k_calculation_pipeline.sh ##
## Master submission script: for each configuration, fit -> silhouette array -> merge -> report ##
## Usage: bash 2.1_run_k_calculation_pipeline.sh [config ...]   (defaults to all three configurations) ##

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Run from the clustering scripts directory so the relative sbatch paths resolve,
# regardless of whether this launcher is invoked with bash or sbatch
cd "/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/scripts/main_analysis/1_clustering"

# Configurations to run: arguments if given, otherwise primary, backup, and emotional-abuse fallback concurrently
if [[ $# -gt 0 ]]; then
  CONFIGS=("$@")
else
  CONFIGS=(fallback_emo_ace backup_cbcl3raw_emo_ace)
fi

# Submit an independent dependency chain per configuration, so configurations run concurrently
for cfg in "${CONFIGS[@]}"; do

  # Fit k = 2:8 once and cache with an embedded fingerprint
  FIT_JID=$(sbatch --parsable --job-name="kfit_${cfg}" --export=ALL,CONFIG="${cfg}" 2.2_fit_kproto.sh)
  FIT_JID=${FIT_JID%%;*}

  # One array task per k computes individual silhouette widths from the cached fits (only after a successful fit)
  SIL_JID=$(sbatch --parsable --job-name="ksil_${cfg}" --export=ALL,CONFIG="${cfg}" \
    --dependency=afterok:"${FIT_JID}" 2.3_partial_silhouette.sh)
  SIL_JID=${SIL_JID%%;*}

  # Merge runs after the whole array ends either way, so a task lost to resources falls back to the exact computation
  MERGE_JID=$(sbatch --parsable --job-name="kmerge_${cfg}" --export=ALL,CONFIG="${cfg}" \
    --dependency=afterany:"${SIL_JID}" 2.4_merge_silhouette.sh)
  MERGE_JID=${MERGE_JID%%;*}

  # Report renders only if the merge succeeded
  REPORT_JID=$(sbatch --parsable --job-name="kreport_${cfg}" --export=ALL,CONFIG="${cfg}" \
    --dependency=afterok:"${MERGE_JID}" 2.5_k_calc_consensus.sh)
  REPORT_JID=${REPORT_JID%%;*}

  # Print the chain for this configuration
  echo "${cfg}: fit=${FIT_JID} silhouette_array=${SIL_JID} merge=${MERGE_JID} report=${REPORT_JID}"
done
