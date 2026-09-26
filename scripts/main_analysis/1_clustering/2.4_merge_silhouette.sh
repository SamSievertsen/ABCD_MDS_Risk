#!/usr/bin/env bash

## 2.4_merge_silhouette.sh ##
## Merge the seven per-k silhouette results for one configuration into a single validation object ##
## Prefers kproto2silhouette(); falls back to the exact closed form only if a package task did not complete, and records which ##

#SBATCH --job-name=kmerge
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --time=01:00:00

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G

#SBATCH --export=ALL

# Use strict Bash mode (fast failure)
set -euo pipefail
IFS=$'\n\t'

# Require the configuration to be passed in
: "${CONFIG:?CONFIG must be set}"

# Paths & env 
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"
export SCALING="z_score"
export PARTIAL_DIR="${REPO}/data/data_processed/validation_results/partial_results_in_progress"
export VALID_DIR="${REPO}/data/data_processed/validation_results"
mkdir -p "${VALID_DIR}"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Mark the start of the merge
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_START|config=${CONFIG}" >> "${DETAILED_LOG}"

# Run merge in R
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript - <<'RSCRIPT'

# Environment
cfg <- Sys.getenv("CONFIG"); scaling <- Sys.getenv("SCALING"); partial_dir <- Sys.getenv("PARTIAL_DIR")
k_vals <- 2:8

# Collect one result per k, preferring the verified package estimator
results <- lapply(k_vals, function(k) {
  stem <- file.path(partial_dir, sprintf("sil_%s_%s_k%d", cfg, scaling, k))
  pkg_path <- paste0(stem, "_pkg.rds"); exact_path <- paste0(stem, "_exact.rds")
  if (file.exists(pkg_path)) {
    r <- readRDS(pkg_path)
    if (!isTRUE(r$agree)) stop(sprintf("k=%d: kproto2silhouette disagreed with the exact computation (max abs diff %.3e); not merging", k, r$max_abs_diff_vs_exact))
    return(r)
  }
  if (file.exists(exact_path)) {
    r <- readRDS(exact_path)
    r$max_abs_diff_vs_exact <- NA_real_; r$n_neighbor_mismatch <- NA_integer_
    warning(sprintf("k=%d: package task did not complete; using the exact closed-form result", k))
    return(r)
  }
  stop(sprintf("k=%d: no silhouette result found for config %s", k, cfg))
})
names(results) <- paste0("k", k_vals)

# Assemble the mean silhouette index per k and the optimum (higher is better)
indices <- vapply(results, `[[`, numeric(1), "mean_silhouette")
names(indices) <- as.character(k_vals)
k_opt <- as.integer(names(which.max(indices)))

# Provenance and verification table for the report
provenance <- data.frame(
  k = k_vals,
  source = vapply(results, `[[`, character(1), "source"),
  mean_silhouette = as.numeric(indices),
  max_abs_diff_vs_exact = vapply(results, function(r) as.numeric(r$max_abs_diff_vs_exact), numeric(1)),
  n_neighbor_mismatch = vapply(results, function(r) as.integer(r$n_neighbor_mismatch), integer(1)),
  seconds = vapply(results, function(r) as.numeric(r$seconds), numeric(1)),
  row.names = NULL
)

# Stitch together, keeping the structure the report expects plus the individual-level widths
vr_all <- list(
  method = "silhouette",
  config = cfg,
  k_opt = k_opt,
  index_opt = max(indices),
  indices = indices,
  provenance = provenance,
  individual = lapply(results, function(r) list(source = r$source, table = r$table))
)

# Save the merged object
saveRDS(vr_all, file.path(Sys.getenv("VALID_DIR"), sprintf("val_%s_%s_silhouette.rds", cfg, scaling)))
print(provenance)

RSCRIPT

# Mark the end of the merge
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_DONE|config=${CONFIG}" >> "${DETAILED_LOG}"
