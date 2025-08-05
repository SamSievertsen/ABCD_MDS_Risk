#!/usr/bin/env bash

## 2.2_partial_k_calc_validation.sh ##
## Array script: run one (index x k) validation and write partial RDS ##

#SBATCH --job-name=partial_val
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

#SBATCH --array=1-35%7

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Paths and environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.4.sif"
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

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Where the output RDS will go
PARTIAL_FILE="${PARTIAL_DIR}/val_robust_${IDX}_k${KVAL}.rds"

# GUARD 1: skip if this partial result already exists
if [[ -f "${PARTIAL_FILE}" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_SKIP_EXISTS|idx=${IDX}|k=${KVAL}" \
    >> "${DETAILED_LOG}"
  exit 0
fi

# GUARD 2: only compute silhouette here & bail for all other indices since we will load in any that exist from previous runs but otherwise skip their calculation
if [[ "${IDX}" != "silhouette" ]]; then
  echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_SKIP_NON_SIL|idx=${IDX}|k=${KVAL}" \
    >> "${DETAILED_LOG}"
  exit 0
fi

# Mark the start of the silhouette validation
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_START|idx=${IDX}|k=${KVAL}" \
  >> "${DETAILED_LOG}"

# Run the singular silhouette (index x k) validation inside the container
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

# Compute silhouette validation for this one k
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

# Exit the R script once completed
EOF

# Mark the end of the silhouette validation
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|PARTIAL_DONE|idx=${IDX}|k=${KVAL}" \
  >> "${DETAILED_LOG}"
