#!/usr/bin/env bash

## 3_nested_suicidality_discrete_time_hazard.sh ##
## render 3_nested_suicidality_discrete_time_hazard.Rmd on ARC ##

#SBATCH --job-name=nested_suic_dth
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

# Strict bash mode
set -euo pipefail
IFS=$'\n\t'

# Paths & env
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.5.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Thread caps for numeric stability/repro
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 BLIS_NUM_THREADS=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Logs
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"
echo "$(date +'%F %T')|JOB_START|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"

# Rmd location
RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
RMD_FILE="3_nested_suicidality_discrete_time_hazard.Rmd"

# Allow param overrides at submit time
LINK_PRIMARY="${LINK_PRIMARY:-logit}"
WAVE_REF="${WAVE_REF:-ses-04A}"
AGES_PRESET="${AGES_PRESET:-}"
SEED="${SEED:-123}"

# Optional overrides for dataset filenames (usually no need to change)
SUIC_PPRDS="${SUIC_PPRDS:-nested_suic_person_period_k2_robust.rds}"
SUIC_PPCSV="${SUIC_PPCSV:-nested_suic_person_period_k2_robust.csv}"

# Change directory to the relevant Rmd directory
cd "${RMD_DIR}"

# Build R expression for ages: if AGES_PRESET empty, pass NULL so R uses empirical medians
if [[ -n "${AGES_PRESET}" ]]; then
  AGES_R="c(${AGES_PRESET})"
else
  AGES_R="NULL"
fi

# Execute Rmd via Apptainer
apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    repo = "${REPO}",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/3_nested_suic_dth",
    suic_pp_rds = "${SUIC_PPRDS}",
    suic_pp_csv = "${SUIC_PPCSV}",
    link_primary = "${LINK_PRIMARY}",
    wave_ref = "${WAVE_REF}",
    ages_pred = ${AGES_R},
    seed = as.integer("${SEED}")
  ),
  encoding = "UTF-8",
  quiet = FALSE
)

# Exit once script is completed
EOF

# Print the completion of the job
echo "$(date +'%F %T')|JOB_DONE|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"