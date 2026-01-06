#!/usr/bin/env bash

## supplementary_outcome_variable_data_wrangling.sh ##
## Render the supplementary diagnosis outcome wrangling Rmd ##

#SBATCH --job-name=sup_outcome_data_wrangle
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G

#SBATCH -o /home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH -e /home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err

#SBATCH --export=ALL

# Set strict bash mode (quick error out)
set -euo pipefail
IFS=$'\n\t'

# Establish paths and env
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache"

# Set script location
SCRIPT="${REPO}/scripts/main_analysis/0_data_wrangling/supplementary_outcome_variable_data_wrangling.Rmd"

# Make sure log dir exists (for -o/-e targets)
mkdir -p "${REPO}/slurm_logs"

# Change directory to script location
cd "$(dirname "${SCRIPT}")"

# Execute outcome data wrangling script
apptainer exec \
  -B "${REPO}:${REPO}" \
  "${IMG}" \
  Rscript - <<'EOF'
rmarkdown::render(
  input = "supplementary_outcome_variable_data_wrangling.Rmd",
  quiet = FALSE
)

# Exit container and script once finished
EOF
