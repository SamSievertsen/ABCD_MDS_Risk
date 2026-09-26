#!/usr/bin/env bash

## 2.2_fit_kproto.sh ##
## Fit k-prototypes for k = 2:8 once for one configuration and cache the fits with an embedded fingerprint ##

#SBATCH --job-name=kfit
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=32G

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Require the configuration to be passed in
: "${CONFIG:?CONFIG must be set, e.g. sbatch --export=ALL,CONFIG=primary 2.2_fit_kproto.sh}"

# Paths and environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.log"
export SUMMARY_CSV="${REPO}/slurm_logs/k_calculation_summary.csv"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Stamp run with Git commit & container version
echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
echo "Container: ${IMG}"
echo "Config: ${CONFIG}"

# Render the Rmd in fit mode inside the container
cd "${REPO}/scripts/main_analysis/1_clustering"
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript -e "rmarkdown::render('2_risk_group_k_calculation.Rmd', params = list(config = '${CONFIG}', mode = 'fit'), output_file = '2_risk_group_k_calculation_${CONFIG}_fit.html', quiet = TRUE)"
