#!/usr/bin/env bash

## 3.3_stability_report.sh ##
## Final job: pool the bootstrap chunks for one configuration and render the stability report ##

#SBATCH --job-name=stab_report
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Require the launcher's settings
: "${CONFIG:?CONFIG must be set}"
: "${N_BOOT:?N_BOOT must be set}"
: "${N_CHUNKS:?N_CHUNKS must be set}"
K_VALUE="${K_VALUE:-2}"
STAB_NSTART="${STAB_NSTART:-25}"

# Paths and environment
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_stability.log"

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
  Rscript -e "rmarkdown::render('3_cluster_stability_analysis.Rmd', params = list(config = '${CONFIG}', mode = 'report', n_chunks = ${N_CHUNKS}L, n_boot = ${N_BOOT}L, k_value = ${K_VALUE}L, stab_nstart = ${STAB_NSTART}L), output_file = '3_cluster_stability_analysis_${CONFIG}_ns${STAB_NSTART}_report.html', quiet = TRUE)"
