#!/usr/bin/env bash

## 7_included_vs_excluded_comparison.sh ##
## render 7_included_vs_excluded_comparison.Rmd on ARC (Reviewer 2, comment 2) ##

#SBATCH --job-name=incl_vs_excl
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=NagelLab
#SBATCH --partition=interactive

#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G

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

# Provenance
echo "Job started on $(hostname) at $(date)"
echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
echo "Container: ${IMG}"

# Render from the Rmd's own directory (avoids the repo-root .Rprofile activating renv)
cd "${REPO}/scripts/main_analysis/2_statistical_analysis"
apptainer exec -B "${REPO}:${REPO}" "${IMG}" \
  Rscript -e "rmarkdown::render('7_included_vs_excluded_comparison.Rmd', quiet = FALSE)"

echo "Job finished at $(date)"
