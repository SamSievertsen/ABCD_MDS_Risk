#!/usr/bin/env bash
#SBATCH --job-name=su_mixed_logit
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu
#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=long_jobs
#SBATCH --time=4-00:00:00
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
  input = "4_nested_suicidality_mixed_effects_logit.Rmd",
  params = list(
    repo = "/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/4_nested_suicidality_mixed_logit",
    panel_rds = "nested_suic_panel_k2_z_score.rds",
    panel_csv = "nested_suic_panel_k2_z_score.csv",
    outcomes = c("si_passive","si_active","sa","nssi"),
    response_var = "status",
    link_primary = "logit",
    wave_ref = "ses-02A",
    age_linear = "age_wave_gmc",
    bd_timevarying = "any_bsd",
    baseline_fallback = "baseline_status_su",
    fit_gamm = TRUE,
    do_gee_interaction = TRUE
  ),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF
