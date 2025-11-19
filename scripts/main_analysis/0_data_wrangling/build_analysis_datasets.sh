#!/usr/bin/env bash

# build_analysis_datasets.sh ##
# Render the analysis dataset(s) creation Rmd ##

#SBATCH --job-name=analysis_datasets_build
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --time=02:00:00

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G

#SBATCH --chdir=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/scripts/main_analysis/0_data_wrangling

#SBATCH -o /home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.out
#SBATCH -e /home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/slurm_logs/%x_%j.err

#SBATCH --export=ALL

# Use strict bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Threading hygiene (let SLURM control true parallelism)
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export VECLIB_MAXIMUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export R_PARALLEL_BACKEND_THREADS="${SLURM_CPUS_PER_TASK:-1}"

# Establish paths
REPO="/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk"
IMG="/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif"
RMD="build_analysis_datasets.Rmd"

# Ensure log dir exists
mkdir -p "${REPO}/slurm_logs"

# Apptainer cache (kept on scratch, not $HOME)
export APPTAINER_CACHEDIR="/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache"
mkdir -p "${APPTAINER_CACHEDIR}"

# Set parameter knobs (can also override at submit time: SCALING_METHOD=..., etc.)
: "${SCALING_METHOD:=z_score}"
: "${K_VALUE:=2}"
: "${OVERWRITE:=false}"
: "${BASELINE_WAVE:=ses-00A}"
: "${START_WAVE:=ses-02A}"
: "${WAVES_CSV:=ses-00A,ses-02A,ses-04A,ses-06A}"
: "${MAX_SUIC_END_WAVE:=ses-04A}"
: "${COVARIATES_FILE:=${REPO}/data/data_raw/dataset.csv}"

# Version + provenance logging
echo "Job: ${SLURM_JOB_NAME:-NA}  ID: ${SLURM_JOB_ID:-NA}"
echo "Date: $(date -Iseconds)"
echo "Host: $(hostname)"
echo "Apptainer: $(apptainer --version || true)"
echo "Repo: ${REPO}"
if command -v git >/dev/null 2>&1; then
  if git -C "${REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git commit: $(git -C "${REPO}" rev-parse HEAD)"
    echo "Git dirty:  $(test -n "$(git -C "${REPO}" status --porcelain)" && echo yes || echo no)"
  fi
fi

# Run render inside the container via srun for SLURM tracking
srun apptainer exec \
  --cleanenv \
  -B "${REPO}:${REPO}" \
  --env SCALING_METHOD="${SCALING_METHOD}" \
  --env K_VALUE="${K_VALUE}" \
  --env OVERWRITE="${OVERWRITE}" \
  --env BASELINE_WAVE="${BASELINE_WAVE}" \
  --env START_WAVE="${START_WAVE}" \
  --env WAVES_CSV="${WAVES_CSV}" \
  --env MAX_SUIC_END_WAVE="${MAX_SUIC_END_WAVE}" \
  --env COVARIATES_FILE="${COVARIATES_FILE}" \
  "${IMG}" \
  Rscript - <<'EOF'

# Print R + Pandoc versions
cat("R version:", R.version.string, "\n", sep=" ")
pver <- tryCatch(rmarkdown::pandoc_version(), error = function(e) NA)
cat("Pandoc version:", as.character(pver), "\n", sep=" ")

waves_vec <- strsplit(Sys.getenv("WAVES_CSV"), ",", fixed = TRUE)[[1]]
waves_vec <- trimws(waves_vec)

# Render the script
rmarkdown::render(
  input  = "build_analysis_datasets.Rmd",
  params = list(
    scaling_method = Sys.getenv("SCALING_METHOD"),
    k_value = as.integer(Sys.getenv("K_VALUE")),
    overwrite = tolower(Sys.getenv("OVERWRITE")) %in% c("true","1","t","yes","y"),
    baseline_wave = Sys.getenv("BASELINE_WAVE"),
    start_wave = Sys.getenv("START_WAVE"),
    waves = waves_vec,
    max_suic_end_wave = Sys.getenv("MAX_SUIC_END_WAVE"),
    covariates_file = Sys.getenv("COVARIATES_FILE")
  ),
  quiet = FALSE
)

# Exit container & script when done
EOF

echo "Done."