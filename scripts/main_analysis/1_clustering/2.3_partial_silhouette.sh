#!/usr/bin/env bash

## 2.3_partial_silhouette.sh ##
## Array script: one task per k computes individual silhouette widths for one configuration from the cached fits ##
## kproto2silhouette() is the reported estimator; a closed-form computation is saved first and used to verify it ##

#SBATCH --job-name=ksil
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=08:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G

#SBATCH --array=1-7

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Require the configuration to be passed in
: "${CONFIG:?CONFIG must be set}"

# Paths and environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"
export SCALING="z_score"
export PROTO_FILE="${REPO}/data/data_processed/kproto_results/kproto_${CONFIG}_${SCALING}.rds"
export PARTIAL_DIR="${REPO}/data/data_processed/validation_results/partial_results_in_progress"
export CLUSTER_DIR="${REPO}/scripts/main_analysis/1_clustering"
mkdir -p "${PARTIAL_DIR}"

# Map array task -> k
KVALS=(2 3 4 5 6 7 8)
export KVAL=${KVALS[$(( SLURM_ARRAY_TASK_ID - 1 ))]}

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_k${KVAL}.log"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" >&2)

# GUARD: skip if the verified package result for this (config, k) already exists
PKG_FILE="${PARTIAL_DIR}/sil_${CONFIG}_${SCALING}_k${KVAL}_pkg.rds"
if [[ -f "${PKG_FILE}" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|SIL_SKIP_EXISTS|config=${CONFIG}|k=${KVAL}" >> "${DETAILED_LOG}"
  exit 0
fi

# Mark the start
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|SIL_START|config=${CONFIG}|k=${KVAL}" >> "${DETAILED_LOG}"

# Compute silhouette widths for this one k inside the container
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript - <<'RSCRIPT'

# Load necessary packages and the exact closed-form helper
suppressPackageStartupMessages(library(clustMixType))
source(file.path(Sys.getenv("CLUSTER_DIR"), "silhouette_helpers.R"))

# Environment
cfg <- Sys.getenv("CONFIG"); k <- as.integer(Sys.getenv("KVAL")); scaling <- Sys.getenv("SCALING")
partial_dir <- Sys.getenv("PARTIAL_DIR")
stem <- file.path(partial_dir, sprintf("sil_%s_%s_k%d", cfg, scaling, k))
log_event <- function(...) cat(sprintf("%s|%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%OS3"), paste(..., sep = "|")),
                               file = Sys.getenv("DETAILED_LOG"), append = TRUE)

# Load the cached fits and extract this k, confirming the fingerprint belongs to this configuration
kp_list <- readRDS(Sys.getenv("PROTO_FILE"))
fp <- attr(kp_list, "fingerprint")
if (is.null(fp) || !identical(fp$config, cfg)) stop("kproto cache fingerprint does not match config ", cfg)
kp <- kp_list[[paste0("k", k)]]
ids <- rownames(kp$data)
stopifnot(identical(ids, fp$participant_id))

# Build a tidy per-participant table from a silhouette object
as_table <- function(sil) data.frame(participant_id = ids, cluster = as.integer(sil[, "cluster"]),
                                     neighbor = as.integer(sil[, "neighbor"]), sil_width = as.numeric(sil[, "sil_width"]))

# 1. Closed-form computation first: seconds and ~0.1 GB, saved as the fallback and used to verify the package
t0 <- Sys.time()
sil_exact <- silhouette_exact_huang(kp)
sec_exact <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
saveRDS(list(config = cfg, k = k, source = "exact_closed_form", table = as_table(sil_exact),
             mean_silhouette = mean(sil_exact[, "sil_width"], na.rm = TRUE), seconds = sec_exact),
        paste0(stem, "_exact.rds"))
log_event("SIL_EXACT_DONE", sprintf("k=%d", k), sprintf("mean=%.8f", mean(sil_exact[, "sil_width"])), sprintf("sec=%.2f", sec_exact))

# 2. The reported estimator: kproto2silhouette() on the cached fit
t1 <- Sys.time()
sil_pkg <- kproto2silhouette(kp)
sec_pkg <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

# 3. Verify the two agree; widths must match to numerical precision, neighbor ties are reported but not fatal
max_diff <- max(abs(sil_pkg[, "sil_width"] - sil_exact[, "sil_width"]))
n_neighbor_mismatch <- sum(sil_pkg[, "neighbor"] != sil_exact[, "neighbor"])
agree <- max_diff < 1e-10

# 4. Always save the package result with its verification, then fail loudly if they disagree
saveRDS(list(config = cfg, k = k, source = "kproto2silhouette", table = as_table(sil_pkg),
             mean_silhouette = mean(sil_pkg[, "sil_width"], na.rm = TRUE), seconds = sec_pkg,
             max_abs_diff_vs_exact = max_diff, n_neighbor_mismatch = n_neighbor_mismatch, agree = agree),
        paste0(stem, "_pkg.rds"))
log_event("SIL_PKG_DONE", sprintf("k=%d", k), sprintf("mean=%.8f", mean(sil_pkg[, "sil_width"])),
          sprintf("sec=%.1f", sec_pkg), sprintf("max_abs_diff=%.2e", max_diff), sprintf("agree=%s", agree))
if (!agree) stop(sprintf("kproto2silhouette and exact closed form disagree at k=%d (max abs diff %.3e)", k, max_diff))

RSCRIPT

# Mark the end
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|SIL_DONE|config=${CONFIG}|k=${KVAL}" >> "${DETAILED_LOG}"
