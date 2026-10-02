#!/usr/bin/env bash

## 3.1_run_stability_pipeline.sh ##
## Launcher (run with bash, not sbatch): for each configuration, bootstrap chunk array -> pooled report ##
## Usage: bash 3.1_run_stability_pipeline.sh [config ...]   (defaults to the adopted primary and backup) ##

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Run from the clustering scripts directory so the relative sbatch paths resolve
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
cd "${REPO}/scripts/main_analysis/1_clustering"

# Configurations to run: arguments if given, otherwise the adopted primary and backup
if [[ $# -gt 0 ]]; then
  CONFIGS=("$@")
else
  CONFIGS=(fallback_emo_ace backup_cbcl3raw_emo_ace)
fi

# Shared settings; override at launch, e.g. N_BOOT=1000 N_CHUNKS=10 STAB_NSTART=25 bash 3.1_run_stability_pipeline.sh
N_BOOT="${N_BOOT:-1000}"
N_CHUNKS="${N_CHUNKS:-10}"
K_VALUE="${K_VALUE:-2}"
STAB_NSTART="${STAB_NSTART:-25}"
if (( N_BOOT % N_CHUNKS != 0 )); then
  echo "ERROR: N_BOOT (${N_BOOT}) must be divisible by N_CHUNKS (${N_CHUNKS})" 1>&2
  exit 2
fi

# Fail before submitting anything if any configuration's k-calculation has not produced its cached fit yet
for cfg in "${CONFIGS[@]}"; do
  KPROTO_RDS="${REPO}/data/data_processed/kproto_results/kproto_${cfg}_z_score.rds"
  if [[ ! -f "${KPROTO_RDS}" ]]; then
    echo "ERROR: ${cfg}: cached fit not found (${KPROTO_RDS}); run the k-calculation pipeline first" 1>&2
    exit 2
  fi
done

# Submit an independent chain per configuration
for cfg in "${CONFIGS[@]}"; do

  # One array task per chunk of bootstraps
  CHUNK_JID=$(sbatch --parsable --job-name="stab_${cfg}" --array=1-"${N_CHUNKS}" \
    --export=ALL,CONFIG="${cfg}",N_BOOT="${N_BOOT}",N_CHUNKS="${N_CHUNKS}",K_VALUE="${K_VALUE}",STAB_NSTART="${STAB_NSTART}" \
    3.2_stability_chunk.sh)
  CHUNK_JID=${CHUNK_JID%%;*}

  # Pooled report only if every chunk succeeded
  REPORT_JID=$(sbatch --parsable --job-name="stabrep_${cfg}" \
    --export=ALL,CONFIG="${cfg}",N_BOOT="${N_BOOT}",N_CHUNKS="${N_CHUNKS}",K_VALUE="${K_VALUE}",STAB_NSTART="${STAB_NSTART}" \
    --dependency=afterok:"${CHUNK_JID}" 3.3_stability_report.sh)
  REPORT_JID=${REPORT_JID%%;*}

  # Print the chain for this configuration
  echo "${cfg}: chunk_array=${CHUNK_JID} (${N_CHUNKS} x $(( N_BOOT / N_CHUNKS )) bootstraps, nstart=${STAB_NSTART}) report=${REPORT_JID}"
done
