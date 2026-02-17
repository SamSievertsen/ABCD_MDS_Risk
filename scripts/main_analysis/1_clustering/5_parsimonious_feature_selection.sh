#!/usr/bin/env bash
#SBATCH --job-name=mvfs_kproto
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=long_jobs

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=36
#SBATCH --mem=512G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err

#SBATCH --export=ALL

set -euo pipefail
IFS=$'\n\t'

# Paths / environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

RMD_DIR="${REPO}/scripts/main_analysis/1_clustering"
RMD_FILE="${RMD_FILE:-5_parsimonious_feature_selection.Rmd}"  # override if needed

# logs
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_mvfs.log"

# prevent BLAS/thread oversubscription
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

# Sanity checks
KPROTO_RDS="${REPO}/data/data_processed/kproto_results/kproto_z_score.rds"
FI_SUM_DIR="${REPO}/results/main_analysis/1_clustering/4_feature_importance/summary"

for f in \
  "${KPROTO_RDS}" \
  "${FI_SUM_DIR}/centroid_separation_summary.csv" \
  "${FI_SUM_DIR}/shap_global_importance.csv"
do
  if [[ ! -f "${f}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%OS3')|FATAL|missing_file|${f}" >> "${DETAILED_LOG}"
    echo "ERROR: Required file missing: ${f}" 1>&2
    exit 2
  fi
done

# MCR summary can be in one of two filenames; ensure at least one exists
if [[ ! -f "${FI_SUM_DIR}/feature_importance_summary.csv" && ! -f "${FI_SUM_DIR}/feature_importance_summary_feature_spec_mcr.csv" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|FATAL|missing_mcr_summary|${FI_SUM_DIR}" >> "${DETAILED_LOG}"
  echo "ERROR: Missing MCR summary in: ${FI_SUM_DIR}" 1>&2
  exit 2
fi

# Determine P dynamically (num features in anchor frame)
echo "KPROTO_RDS=${KPROTO_RDS}" >> "${DETAILED_LOG}"
apptainer exec -B "${REPO}:${REPO}" "${IMG}" env | grep -E "KPROTO_RDS|K_OPT" >> "${DETAILED_LOG}" || true
ls -lh "${KPROTO_RDS}" >> "${DETAILED_LOG}"

P="$(
  apptainer exec \
    --env KPROTO_RDS="${KPROTO_RDS}" \
    --env K_OPT="${K_OPT:-2}" \
    -B "${REPO}:${REPO}" "${IMG}" \
    Rscript - <<'RS'
kp_any <- readRDS(Sys.getenv("KPROTO_RDS"))
k_target <- as.integer(Sys.getenv("K_OPT", "2"))

pick_kproto <- function(obj, k_target){
  if (inherits(obj, "kproto")) return(obj)
  stopifnot(is.list(obj))
  nm <- names(obj)
  if (!is.null(nm)) {
    hit <- paste0("k", k_target)
    if (hit %in% nm && inherits(obj[[hit]], "kproto")) return(obj[[hit]])
  }
  for (el in obj) {
    if (inherits(el, "kproto")) {
      sz <- tryCatch(el$size, error=function(...) NULL)
      if (!is.null(sz) && length(sz) == k_target) return(el)
    }
  }
  stop("Could not locate kproto object")
}

kp0 <- pick_kproto(kp_any, k_target)
cat(ncol(as.data.frame(kp0$data)))
RS
)" || { echo "ERROR: failed to determine P" >&2; exit 3; }

echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MVFS_JOB_START|P=${P}" >> "${DETAILED_LOG}"

# What to run; these can be overridden at submit time
SEARCHES="${SEARCHES:-forward backward domain}"
LAMBDA_MODES="${LAMBDA_MODES:-estimate anchor_fixed}"
N_PAR="${N_PAR:-18}"   # parallel renders on this node

REPORT_DIR="${REPO}/results/main_analysis/1_clustering/5_parsimonious_feature_selection/reports"
mkdir -p "${REPORT_DIR}"

cd "${RMD_DIR}"

run_one_step () {
  local idx="$1"
  local search="$2"
  local lambda_mode="$3"

  apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<RS
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    mode = "step",
    search = "${search}",
    step_index = as.integer(${idx}),
    k_opt = as.integer(Sys.getenv("K_OPT", "2")),
    lambda_mode = "${lambda_mode}",
    boot_B = as.integer(Sys.getenv("BOOT_B", "1000")),
    boot_seed = as.integer(Sys.getenv("BOOT_SEED", "123")),
    nstart = as.integer(Sys.getenv("NSTART", "8")),
    ari_target = as.numeric(Sys.getenv("ARI_TARGET", "0.80")),
    jaccard_target = as.numeric(Sys.getenv("JACCARD_TARGET", "0.80")),
    silhouette_type = Sys.getenv("SIL_TYPE", "huang")
  ),
  output_dir = "${REPORT_DIR}",
  output_file = sprintf("mvfs_step_%s_%s_%02d.html", "${search}", "${lambda_mode}", ${idx}),
  quiet = FALSE
)
RS
}

export -f run_one_step
export REPO IMG RMD_FILE REPORT_DIR
export KPROTO_RDS
export K_OPT="${K_OPT:-2}"

# Run all step-level jobs (parallel on one node)
for search in ${SEARCHES}; do
  for lambda_mode in ${LAMBDA_MODES}; do
    echo "$(date +'%Y-%m-%d %H:%M:%OS3')|TRACE_START|search=${search}|lambda_mode=${lambda_mode}|P=${P}" >> "${DETAILED_LOG}"
    seq 1 "${P}" | xargs -n 1 -P "${N_PAR}" -I {} bash -lc "run_one_step {} ${search} ${lambda_mode}"
    echo "$(date +'%Y-%m-%d %H:%M:%OS3')|TRACE_DONE|search=${search}|lambda_mode=${lambda_mode}" >> "${DETAILED_LOG}"
  done
done

# Aggregate (single render)
apptainer exec -B "${REPO}:${REPO}" "${IMG}" Rscript - <<RS
rmarkdown::render(
  input = "${RMD_FILE}",
  params = list(
    mode = "aggregate",
    k_opt = as.integer(Sys.getenv("K_OPT", "2")),
    ari_target = as.numeric(Sys.getenv("ARI_TARGET", "0.80")),
    jaccard_target = as.numeric(Sys.getenv("JACCARD_TARGET", "0.80"))
  ),
  output_dir = "${REPORT_DIR}",
  output_file = "mvfs_aggregate.html",
  quiet = FALSE
)
RS

echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MVFS_JOB_DONE" >> "${DETAILED_LOG}"
