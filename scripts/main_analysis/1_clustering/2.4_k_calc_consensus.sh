#!/usr/bin/env bash

## 2.4_k_calc_consensus.sh ##
## Final job: generate consensus plots and summary after merging validations ##

#SBATCH --job-name=kcalc_consensus
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Paths and environment
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_consensus.log"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Mark the start of the consensus k calculation
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|CONSENSUS_START|" \
  >> "${DETAILED_LOG}"

# Change to script directory
cd "${REPO}/scripts/main_analysis/1_clustering"

# Render the modified Rmd
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript - <<'EOF'

# Render full report with all available validation indices (silhouette + any others found)
rmarkdown::render(
  input = "2_risk_group_k_calculation.Rmd",
  params = list(validation_index = "all"),
  quiet = FALSE
)

# Exit the script once completed
EOF

# Mark the end of the consensus k calculation for the detailed log
echo "$(date +'%Y-%m-%d %H:%M:%OS3')|CONSENSUS_DONE|" \
  >> "${DETAILED_LOG}"
