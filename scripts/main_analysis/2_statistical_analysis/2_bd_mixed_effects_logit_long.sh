#!/usr/bin/env bash
#SBATCH --job-name=bd_mixed_logit_long
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu
#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=long_jobs
#SBATCH --time=4-00:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=256G
#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err
#SBATCH --export=ALL

set -euo pipefail
IFS=$'\n\t'

REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"

export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache"
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export BLIS_NUM_THREADS=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Allow param overrides at submit time (e.g., CONFIG=backup_cbcl3raw_emo_ace DO_GAMM=false sbatch 2_bd_mixed_effects_logit_long.sh)
export CONFIG="${CONFIG:-fallback_emo_ace}"
export DO_GAMM="${DO_GAMM:-false}"
echo "Config: ${CONFIG} | do_gamm: ${DO_GAMM}"

RMD_DIR="${REPO}/scripts/main_analysis/2_statistical_analysis"
cd "${RMD_DIR}"

# Sanitize common Unicode punctuation to ASCII to avoid parse errors in code chunks
perl -CSDA -pe 's/\x{2018}|\x{2019}/\x27/g; s/\x{201C}|\x{201D}/\x22/g; s/\x{2013}|\x{2014}/-/g; s/\x{00D7}/x/g; s/\x{2212}/-/g;' \
  -i 2_bd_mixed_effects_logit.Rmd

apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<'EOF'
rmarkdown::render(
  input = "2_bd_mixed_effects_logit.Rmd",
  output_file = paste0("2_bd_mixed_effects_logit_", Sys.getenv("CONFIG"), ".html"),
  params = list(
    repo = "/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk",
    data_dir = "data/data_processed/analysis_datasets/",
    out_dir = "results/main_analysis/2_statistical_analysis/2_bd_mixed_logit",
    config = Sys.getenv("CONFIG"),
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
    do_gamm = tolower(Sys.getenv("DO_GAMM")) %in% c("true", "1", "t", "yes", "y"),
    do_gee_interaction = TRUE),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF
