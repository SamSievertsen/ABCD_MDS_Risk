#!/usr/bin/env bash

## 2.7_k2_objective_landscape.sh ##
## Map the k = 2 objective landscape of one configuration from many single-start refits on the full sample ##

#SBATCH --job-name=k2_landscape
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G

#SBATCH --export=ALL

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Allow param overrides at submit time (e.g., CONFIG=backup_cbcl3raw_emo_ace N_RUNS=200 sbatch 2.7_k2_objective_landscape.sh)
CONFIG="${CONFIG:-fallback_emo_ace}"
N_RUNS="${N_RUNS:-200}"

# Paths and environment
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Logging setup
LOGDIR="${REPO}/slurm_logs/$(date +%F)"
mkdir -p "${LOGDIR}"

# Redirect all stdout/stderr into the date stamped log folder
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Stamp run with Git commit & container version
echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
echo "Container: ${IMG} | Config: ${CONFIG} | Runs: ${N_RUNS}"

# Render the landscape report inside the container
cd "${REPO}/scripts/main_analysis/1_clustering"
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript -e "rmarkdown::render('2.7_k2_objective_landscape.Rmd', params = list(config = '${CONFIG}', n_runs = ${N_RUNS}L), output_file = '2.7_k2_objective_landscape_${CONFIG}.html', quiet = TRUE)"
