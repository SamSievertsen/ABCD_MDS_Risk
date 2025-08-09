#!/usr/bin/env bash

## 3_cluster_stability_analysis.sh ##
## Render the cluster stability Rmd (Rand + Jaccard bootstraps) ##

#SBATCH --job-name=stability_k
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=long_jobs

#SBATCH --time=72:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

## Establish paths & environment ##

# Container & repo
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.4.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_stability.log"

# Rmd location
RMD_DIR="${REPO}/scripts/main_analysis/1_clustering"
RMD_FILE="3_cluster_stability_analysis.Rmd"

# Data & cached objects sanity check: fail early if kproto file is missing, proceed if present
KPROTO_RDS="${REPO}/data/data_processed/kproto_results/kproto_robust.rds"
if [[ ! -f "${KPROTO_RDS}" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|FATAL|missing_kproto|${KPROTO_RDS}" >> "${DETAILED_LOG}"
  echo "ERROR: Required kproto RDS not found: ${KPROTO_RDS}" 1>&2
  exit 2
fi

## Parameter overrides for future jobs / k solutions ##

# Defaults match Rmd params and can be overridden at submit-time via: sbatch --export=ALL,K_VALUE=2,N_BOOT=1000,SCALING_METHOD=robust,SEED=123,OVERWRITE=false 3.1_run_cluster_stability.sh
K_VALUE="${K_VALUE:-2}"
N_BOOT="${N_BOOT:-1000}"
SCALING_METHOD="${SCALING_METHOD:-robust}"
SEED="${SEED:-123}"
OVERWRITE="${OVERWRITE:-false}"

## Run stability analysis job ##

# Mark start in detailed log
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|STABILITY_JOB_START|k=${K_VALUE}|B=${N_BOOT}|scale=${SCALING_METHOD}" >> "${DETAILED_LOG}"

# Change to the directory with the Rmd so relative paths work
cd "${RMD_DIR}"

# Render the stability report inside the container
apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    scaling_method = "${SCALING_METHOD}",
    k_value = as.integer("${K_VALUE}"),
    n_boot = as.integer("${N_BOOT}"),
    seed = as.integer("${SEED}"),
    overwrite = as.logical("${OVERWRITE}")
  ),
  quiet = FALSE
)

# Exit container & job once script completes
EOF

# Mark end of job in detailed log
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|STABILITY_JOB_DONE|k=${K_VALUE}|B=${N_BOOT}|scale=${SCALING_METHOD}" >> "${DETAILED_LOG}"
