#!/usr/bin/env bash

## 6_risk_vars_vs_cluster_utility.sh ##
## render 6_risk_vars_vs_cluster_utility.Rmd on ARC ##

#SBATCH --job-name=risk_vs_cluster_utility
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=23:59:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err
#SBATCH --export=ALL

# Use strict bash mode
set -euo pipefail
IFS=$'\n\t'

# Paths & environment
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Thread caps for reproducibility / numerical stability
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export BLIS_NUM_THREADS=1
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Logs
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"
echo "$(date +'%F %T')|JOB_START|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"

# Rmd location
RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
RMD_FILE="6_risk_vars_vs_cluster_utility.Rmd"

# Clustering configuration whose labels are analyzed (override at submit time: CONFIG=... sbatch ...)
CONFIG="${CONFIG:-fallback_emo_ace}"

# cd to script directory
cd "${RMD_DIR}"

# Render inside container
stdbuf -oL -eL apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript --vanilla - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    repo = "${REPO}",
    config = "${CONFIG}"
    # Feature lists are not passed: all clustering features come from cluster_configs.R and the MVFS from
    # 5_parsimonious_feature_selection's output, so they cannot drift from the clustering
  ),
  output_file = "6_risk_vars_vs_cluster_utility_${CONFIG}.html",
  encoding = "UTF-8",
  quiet = FALSE
)
EOF

# Completion log
echo "$(date +'%F %T')|JOB_DONE|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"