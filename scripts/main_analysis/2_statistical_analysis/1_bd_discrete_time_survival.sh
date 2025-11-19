#!/usr/bin/env bash

## 1_bd_discrete_time_survival.sh ##
## render 1_bd_discrete_time_survival.Rmd on ARC ##

#SBATCH --job-name=bd_survival
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=23:59:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err
#SBATCH --export=ALL

# Use strict bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Paths & env
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Thread caps for numeric stability/repro
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 BLIS_NUM_THREADS=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Set-up logs
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"
echo "$(date +'%F %T')|JOB_START|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"

# Establish the location of the Rmd
RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
RMD_FILE="1_bd_discrete_time_survival.Rmd"

# Allow param overrides at submit time
K_VALUE="${K_VALUE:-2}"
LINK_PRIMARY="${LINK_PRIMARY:-logit}"
WAVE_REF="${WAVE_REF:-ses-04A}"
AGES_PRESET="${AGES_PRESET:-}"

# cd to Rmd directory
cd "${RMD_DIR}"

# Build the R expression for ages: if AGES_PRESET empty, pass NULL so R uses empirical medians
if [[ -n "${AGES_PRESET}" ]]; then
  AGES_R="c(${AGES_PRESET})"
else
  AGES_R="NULL"
fi

# Execute the Rmd using the Apptainer container
apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    repo = "${REPO}",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/1_bd_survival",
    bd_pp_rds = "bd_person_period_k2_z_score.rds",
    bd_pp_csv = "bd_person_period_k2_z_score.csv",
    k_value = as.integer("${K_VALUE}"),
    link_primary= "${LINK_PRIMARY}",
    ages_pred = ${AGES_R},
    wave_ref = "${WAVE_REF}"
  ),
  encoding = "UTF-8",
  quiet = FALSE
)

# Exit script once completed
EOF

# Print the completion of the job
echo "$(date +'%F %T')|JOB_DONE|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"
