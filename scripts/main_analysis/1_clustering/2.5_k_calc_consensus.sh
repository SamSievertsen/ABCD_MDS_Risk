#!/usr/bin/env bash

## 2_5_k_calc_consensus.sh ##
## Final job: render the k-selection report for one configuration from the cached fits and merged silhouette ##

#SBATCH --job-name=kreport
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=06:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Require the configuration to be passed in
: "${CONFIG:?CONFIG must be set}"

# Paths and environment
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_report.log"
export SUMMARY_CSV="${REPO}/slurm_logs/k_calculation_summary.csv"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Stamp run with Git commit & container version
echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
echo "Container: ${IMG}"
echo "Config: ${CONFIG}"

# Render the Rmd in report mode inside the container
cd "${REPO}/scripts/main_analysis/1_clustering"
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript -e "rmarkdown::render('2_risk_group_k_calculation.Rmd', params = list(config = '${CONFIG}', mode = 'report'), output_file = '2_risk_group_k_calculation_${CONFIG}_report.html', quiet = TRUE)"
