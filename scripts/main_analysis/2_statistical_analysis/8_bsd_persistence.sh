#!/usr/bin/env bash

## 8_bsd_persistence.sh ##
## render 8_bsd_persistence.Rmd on ARC (Reviewer 1, comment 1) ##

#SBATCH --job-name=bsd_persistence
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err
#SBATCH --export=ALL

# Use strict bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Paths & env
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.9.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Allow a configuration override at submit time (e.g., CONFIG=backup_cbcl3raw_emo_ace sbatch 8_bsd_persistence.sh)
CONFIG="${CONFIG:-fallback_emo_ace}"

# Provenance
echo "Job started on $(hostname) at $(date)"
echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
echo "Container: ${IMG} | Config: ${CONFIG}"

# Render from the Rmd's own directory (avoids the repo-root .Rprofile activating renv)
cd "${REPO}/scripts/main_analysis/2_statistical_analysis"
apptainer exec -B "${REPO}:${REPO}" "${IMG}" \
  Rscript -e "rmarkdown::render('8_bsd_persistence.Rmd', params = list(config = '${CONFIG}'), output_file = '8_bsd_persistence_${CONFIG}.html', quiet = FALSE)"

echo "Job finished at $(date)"
