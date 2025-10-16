#!/usr/bin/env bash
#SBATCH --job-name=bd_mixed_logit_vNEXT_long
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
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.5.sif"

export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache"
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export BLIS_NUM_THREADS=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8

RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
cd "${RMD_DIR}"

# Sanitize common Unicode punctuation to ASCII to avoid parse errors in code chunks
perl -CSDA -pe 's/\x{2018}|\x{2019}/\x27/g; s/\x{201C}|\x{201D}/\x22/g; s/\x{2013}|\x{2014}/-/g; s/\x{00D7}/x/g; s/\x{2212}/-/g;' \
  -i 2_bd_mixed_effects_logit_vNEXT.Rmd

apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<'EOF'
rmarkdown::render(
  input = "2_bd_mixed_effects_logit_vNEXT.Rmd",
  params = list(
    repo = "/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/2_bd_mixed_logit",
    bd_panel_rds = "bd_panel_k2_robust.rds",
    bd_panel_csv = "bd_panel_k2_robust.csv",
    outcomes = c("bipolar_I","bipolar_II","bd_nos","any_bsd"),
    response_var = "status",
    link_primary = "logit",
    wave_ref = "ses-02A",
    ages_pred = NULL,
    show_code = FALSE,
    gamm_basis = "tp",
    k_age = 6,
    bam_discrete = TRUE,
    mgcv_gamma = 1.4,
    do_gamm = FALSE,
    do_gee_interaction = TRUE),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF
