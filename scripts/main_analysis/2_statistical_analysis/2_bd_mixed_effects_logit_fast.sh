#!/usr/bin/env bash
#SBATCH --job-name=bd_mixed_logit_fast
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
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export BLIS_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export LANG=C.UTF-8 LC_ALL=C.UTF-8

RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
cd "${RMD_DIR}"

apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<'EOF'
rmarkdown::render(
  input = "2_bd_mixed_effects_logit.Rmd",
  params = list(
    repo = "/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/2_bd_mixed_logit",
    bd_panel_rds = "bd_panel_k2_z_score.rds",
    bd_panel_csv = "bd_panel_k2_z_score.csv",
    outcomes = c("bipolar_I","bipolar_II","bd_nos","any_bsd"),
    response_var = "status",
    link_primary = "logit",
    wave_ref = "ses-02A",
    ages_pred = NULL,
    reuse_fits = TRUE,
    gamm_engine = "bam",
    gamm_basis = "cr",
    k_age = 6,
    age_round = 0.1,
    bam_discrete = TRUE,
    mgcv_gamma = 1.4
  ),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF
