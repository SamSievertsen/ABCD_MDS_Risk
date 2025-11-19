#!/usr/bin/env bash

## 2.3_merge_k_calc_validation.sh ##
## Merge the silhouette and any other partial (index x k) validations that already exist into a full validation_kproto object ##

#SBATCH --job-name=merge_val
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --time=04:00:00

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

#SBATCH --export=ALL,IDX

# Use strict Bash mode (fast failure)
set -euo pipefail
IFS=$'\n\t'

# Paths & env 
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export PROTO_FILE="${REPO}/data/data_processed/kproto_results/kproto_z_score.rds"
export PARTIAL_DIR="${REPO}/data/data_processed/validation_results/partial_results_in_progress"
export VALID_DIR="${REPO}/data/data_processed/validation_results"

# Ensure output directory exists
mkdir -p "${VALID_DIR}"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_merge_${IDX}.log"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# GUARD 1: skip if this merge result already exists
MERGED_FILE="${VALID_DIR}/val_z_score_${IDX}.rds"
if [[ -f "${MERGED_FILE}" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_SKIP_EXISTS|idx=${IDX}" \
    >> "${DETAILED_LOG}"
  exit 0
fi

# GUARD 2: only merge silhouette here; others will be picked up if already present
if [[ "${IDX}" != "silhouette" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_SKIP_NON_SIL|idx=${IDX}" \
    >> "${DETAILED_LOG}"
  exit 0
fi

# Mark the start of the current merge
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_START|idx=${IDX}" \
  >> "${DETAILED_LOG}"

# Run merge in R
apptainer exec \
  -B "${REPO}:${REPO}" \
  /home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif \
  Rscript - <<'EOF'

# Load necessary packages
library(clustMixType)
library(dplyr)

# Pull in the full kproto list
kp_list <- readRDS(Sys.getenv("PROTO_FILE"))

# Read in each of the 7 partial validations that actually exist
k_vals=(2 3 4 5 6 7 8)
idx="$IDX"
partial <- lapply(k_vals, function(k) {
  fn <- sprintf("val_z_score_%s_k%s.rds", idx, k)
  pth <- file.path(Sys.getenv("PARTIAL_DIR"), fn)
  if (!file.exists(pth)) return(NULL)
  readRDS(pth)
})

# Drop any NULLs (i.e., indices that do not exist)
partial <- partial[!vapply(partial, is.null, logical(1))]
names(partial) <- names(partial) %||% as.character(k_vals)[!vapply(partial, is.null, logical(1))]

# Assemble the named vector of index values
indices <- unlist(partial)

# Decide whether lower=better (none for silhouette)
k_opt <- as.integer(names(which.max(indices)))
index_opt <- max(indices)

# Rebuild the kp_obj list, embedding each kproto solution
kp_obj <- lapply(k_vals, function(k) {
  list(
    index = indices[as.character(k)],
    k = as.integer(k),
    object = kp_list[[paste0("k", k)]]
  )
})

# Stitch it all together
vr_all <- list(
  k_opt = k_opt,
  index_opt = index_opt,
  indices = indices,
  kp_obj = kp_obj
)

# Save the merged object
out_fn <- file.path(Sys.getenv("VALID_DIR"), sprintf("val_z_score_%s.rds", idx))
saveRDS(vr_all, out_fn)

# Exit script
EOF

# Mark the end of the current merge
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|MERGE_DONE|idx=${IDX}" \
  >> "${DETAILED_LOG}"
