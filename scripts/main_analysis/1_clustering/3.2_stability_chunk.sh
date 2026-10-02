#!/usr/bin/env bash

## 3.2_stability_chunk.sh ##
## Array script: one task computes one chunk of bootstrap stability replicates for one configuration ##

#SBATCH --job-name=stab_chunk
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G

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
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_chunk${SLURM_ARRAY_TASK_ID}.log"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" >&2)

# Render the Rmd in chunk mode inside the container
cd "${REPO}/scripts/main_analysis/1_clustering"
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript -e "rmarkdown::render('3_cluster_stability_analysis.Rmd', params = list(config = '${CONFIG}', mode = 'chunk', chunk_id = ${SLURM_ARRAY_TASK_ID}L, n_chunks = ${N_CHUNKS}L, n_boot = ${N_BOOT}L, k_value = ${K_VALUE}L, stab_nstart = ${STAB_NSTART}L), output_file = '3_cluster_stability_analysis_${CONFIG}_ns${STAB_NSTART}_chunk${SLURM_ARRAY_TASK_ID}.html', quiet = TRUE)"
