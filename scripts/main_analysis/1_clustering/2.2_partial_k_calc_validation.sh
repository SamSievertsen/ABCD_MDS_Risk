#!/usr/bin/env bash

## 2.2_partial_k_calc_validation.sh ##
## Array script: run one (index x k) validation and write partial RDS ##

#SBATCH --job-name=partial_val
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=long_jobs

#SBATCH --time=168:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G

#SBATCH --array=1-35%7

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Paths and environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.3.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"
export PROTO_FILE="${REPO}/data/data_processed/kproto_results/kproto_robust.rds"
export PARTIAL_DIR="${REPO}/data/data_processed/validation_results/partial_results_in_progress"

# Ensure partial-results directory exists
mkdir -p "${PARTIAL_DIR}"

# Map array-task -> (index, k)
INDICES=(silhouette cindex gamma ptbiserial tau)
KVALS=(2 3 4 5 6 7 8)
TASK=$(( SLURM_ARRAY_TASK_ID - 1 ))
I=$(( TASK / ${#KVALS[@]} ))
K=$(( TASK % ${#KVALS[@]} ))
export IDX=${INDICES[$I]}
export KVAL=${KVALS[$K]}

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_partial_${SLURM_ARRAY_TASK_ID}.log"

# Place where the output will go
OUT_RDS="${PARTIAL_DIR}/val_robust_${IDX}_k${KVAL}.rds"

# GUARD: skip if this partial result already exists
PARTIAL_FILE="${PARTIAL_DIR}/val_robust_${IDX}_k${KVAL}.rds"
if [[ -f "${PARTIAL_FILE}" ]]; then
  echo "Skipping ${IDX} k=${KVAL}, already done at ${PARTIAL_FILE}"
  exit 0
fi

# Mark the start of the current index in the log
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_START|idx=${IDX}|k=${KVAL}" \
  >> "${DETAILED_LOG}"

# Run the one-(index x k) validation inside the container
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript - <<'EOF'

# Load necessary packages
library(dplyr)
library(clustMixType)

# Load k-prototype list and extract the single k solution
kp_list <- readRDS(Sys.getenv("PROTO_FILE"))
one_kp <- kp_list[[paste0("k", Sys.getenv("KVAL"))]]

# Compute validation index for this one k
val <- validation_kproto(
  method = Sys.getenv("IDX"),
  object = one_kp,
  kp_obj = "optimal",
  verbose = FALSE
)

# Save the partial result
saveRDS(
  val,
  file.path(
    Sys.getenv("PARTIAL_DIR"),
    sprintf("val_robust_%s_k%s.rds", Sys.getenv("IDX"), Sys.getenv("KVAL"))
  )
)

# Exit out once completed
EOF

# Mark the end of the current index
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_DONE|idx=${IDX}|k=${KVAL}" \
  >> "${DETAILED_LOG}"
