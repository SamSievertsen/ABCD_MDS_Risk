#!/usr/bin/env bash

## 2.4_k_calc_consensus.sh ##
## Final job: generate consensus plots and summary after merging validations ##

#SBATCH --job-name=kcalc_consensus
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic

#SBATCH --time=04:00:00
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
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.3.sif"
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache"

# Change to the R Markdown script directory
cd "${REPO}/scripts/main_analysis/1_clustering"

# Execute the R Markdown rendering for the "all" validation\_index
apptainer exec \
  -B "${REPO}:${REPO}" \
  /home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.3.sif \
  Rscript - <<'EOF'

# Render full report with consensus and plots
rmarkdown::render(
'2_risk_group_k_calculation.Rmd',
params = list(validation_index = 'all'),
quiet = FALSE
)

# Exit the script
EOF
