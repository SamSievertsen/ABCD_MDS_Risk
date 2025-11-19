#!/usr/bin/env bash

## 2_bd_mixed_effects_logit.sh ##
## render 2_bd_mixed_effects_logit.Rmd on ARC ##

#SBATCH --job-name=bd_mixed_logit
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=23:59:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=36
#SBATCH --mem=256G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err
#SBATCH --export=ALL

set -euo pipefail
IFS=$'\n\t'

REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache"

# faster (allow BLAS to use cores; still 1 task)
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OPENBLAS_NUM_THREADS=$SLURM_CPUS_PER_TASK
export BLIS_NUM_THREADS=$SLURM_CPUS_PER_TASK

export LANG=C.UTF-8 LC_ALL=C.UTF-8

LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"
echo "$(date +'%F %T')|JOB_START|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"

RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
RMD_FILE="2_bd_mixed_effects_logit.Rmd"

OUTCOMES="bipolar_I,bipolar_II,bd_nos,any_bsd"
RESPVAR="status"
LINK_PRIMARY="logit"
WAVE_REF="ses-02A"
AGES_PRESET=""

cd "${RMD_DIR}"

if [[ -n "${AGES_PRESET}" ]]; then
  AGES_R="c(${AGES_PRESET})"
else
  AGES_R="NULL"
fi

apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    repo = "${REPO}",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/2_bd_mixed_logit",
    bd_panel_rds = "bd_panel_k2_robust.rds",
    bd_panel_csv = "bd_panel_k2_robust.csv",
    outcomes = strsplit("${OUTCOMES}", ",")[[1]],
    response_var = "${RESPVAR}",
    link_primary = "${LINK_PRIMARY}",
    wave_ref = "${WAVE_REF}",
    ages_pred = ${AGES_R}
  ),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF

echo "$(date +'%F %T')|JOB_DONE|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"
