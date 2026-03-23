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
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.8.sif"
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

# Optional submit-time overrides
DTH_LINK="${DTH_LINK:-logit}"
GEE_LINK="${GEE_LINK:-logit}"
GEE_CORSTR="${GEE_CORSTR:-exchangeable}"
WAVE_REF_DTH="${WAVE_REF_DTH:-ses-04A}"
WAVE_REF_PREV="${WAVE_REF_PREV:-ses-02A}"

# cd to script directory
cd "${RMD_DIR}"

# Render inside container
stdbuf -oL -eL apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript --vanilla - <<EOF
rmarkdown::render(
  input = "${RMD_FILE}",
    params = list(
    repo = "${REPO}",
    data_dir = "data/data_processed/analysis_datasets",
    risk_data_rel = "data/data_processed/risk_variable_data.csv",
    out_dir = "results/main_analysis/2_statistical_analysis/6_risk_vars_vs_cluster_utility",
    bd_pp_rds = "bd_person_period_k2_z_score.rds",
    bd_pp_csv = "bd_person_period_k2_z_score.csv",
    bd_panel_rds = "bd_panel_k2_z_score.rds",
    bd_panel_csv = "bd_panel_k2_z_score.csv",
    outcomes = c("bipolar_I", "bipolar_II", "bd_nos", "any_bsd"),
    dth_link = "${DTH_LINK}",
    gee_link = "${GEE_LINK}",
    do_gee_interaction = TRUE,
    gee_corstr = "${GEE_CORSTR}",
    wave_ref_dth = "${WAVE_REF_DTH}",
    wave_ref_prev = "${WAVE_REF_PREV}",
    seed = 123,
    run_qic = FALSE,
    save_full_gee_objects = FALSE,
    progress_log_file = "run_progress.log",
    risk_vars = c(
      "mh_p_cbcl__dsm__dep_tscore",
      "mh_p_cbcl__dsm__anx_tscore",
      "mh_p_cbcl__synd__attn_tscore",
      "mh_p_cbcl__synd__aggr_tscore",
      "mh_p_gbi_sum",
      "mh_y_upps__nurg_sum",
      "mh_y_upps__purg_sum",
      "le_l_coi__addr1__coi__total__national_zscore",
      "fc_p_nsc__ns_mean",
      "sds_total",
      "family_history_depression",
      "family_history_mania",
      "bullying",
      "nc_y_nihtb__lswmt__uncor_score",
      "nc_y_nihtb__flnkr__uncor_score",
      "nc_y_nihtb__pttcp__uncor_score",
      "ACE_index_sum_score"
    ),
    mvfs_vars = c(
    "mh_p_cbcl__dsm__dep_tscore",
    "mh_p_cbcl__synd__aggr_tscore",
    "mh_p_cbcl__synd__attn_tscore",
    "mh_p_cbcl__dsm__anx_tscore",
    "mh_p_gbi_sum",
    "sds_total",
    "family_history_depression")
  ),
  encoding = "UTF-8",
  quiet = FALSE
)
EOF

# Completion log
echo "$(date +'%F %T')|JOB_DONE|${SLURM_JOB_NAME}" >> "${DETAILED_LOG}"