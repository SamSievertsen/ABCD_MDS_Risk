#!/usr/bin/env bash
#SBATCH --job-name=abcd_comorb_sens
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu
#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH --error=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err

set -euo pipefail

REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
CONTAINER="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
RMD_REL="scripts/main_analysis/2_statistical_analysis/5_comorbidity_sensitivity_analysis.Rmd"

cd "${REPO}"

echo "Job started on $(hostname) at $(date)"
echo "Repo: ${REPO}"
echo "RMD: ${RMD_REL}"
echo "Container: ${CONTAINER}"

# Render RMD
apptainer exec --bind /home/exacloud/gscratch/NagelLab:/home/exacloud/gscratch/NagelLab "${CONTAINER}"   bash -lc "bash scripts/main_analysis/render_rmd.sh -i ${RMD_REL}"

echo "Job finished at $(date)"
