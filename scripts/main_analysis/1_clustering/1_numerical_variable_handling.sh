#!/usr/bin/env bash

#SBATCH --job-name=numerical_variable_scaling
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=36
#SBATCH --mem=256G
#SBATCH --time=23:59:00

#SBATCH --chdir /home/exacloud/gscratch/NagelLab
#SBATCH --export=all

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Set paths & env variables
IMG=/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.3.sif
REPO=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk
export APPTAINER_CACHEDIR=/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache

# Prepare log directories grouped by date
TODAY=$(date +%Y-%m-%d)
LOGDIR="${REPO}/slurm_logs/${TODAY}"
USAGEDIR="${REPO}/slurm_usage_logs"
mkdir -p "${LOGDIR}" "${USAGEDIR}"

# Set up detailed + summary logs
export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_detail.log"
: > "${DETAILED_LOG}"

export SUMMARY_CSV="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_summary.csv"

if [[ ! -f "${SUMMARY_CSV}" ]]; then
  echo "method,status,start_time,end_time,duration_min" > "${SUMMARY_CSV}"
fi

# Redirect stdout/stderr into dated logs
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Stamp logs of run with Git commit & container version
GIT_HASH=$(git -C "${REPO}" rev-parse HEAD)
echo "Git commit: ${GIT_HASH}"
echo "Container: ${IMG}"

# Change directory to the appropriate location wherein the script to run is housed
cd "${REPO}/scripts/main_analysis/1_clustering"

# Stream the DETAILED_LOG to the .out to watch in real time (i.e., tracking each method)
tail -F "${DETAILED_LOG}" & TAILPID=$!

# Render the numerical variable scaling assessment RMD inside the container
apptainer exec \
  -B /home/exacloud/gscratch/NagelLab:/home/exacloud/gscratch/NagelLab \
  "${IMG}" Rscript -e "rmarkdown::render('1_numerical_variable_handling.Rmd', quiet = FALSE)"

# Stop the background tail on exit
kill "$TAILPID" 2>/dev/null || true

# Post-run usage accounting (on EXIT) of compute time & resources
function log_usage {
  CSV="${USAGEDIR}/usage.csv"

  # Create header if missing
  if [[ ! -s "${CSV}" ]]; then
    echo "JobIDRaw|JobName|Partition|Elapsed|AllocCPUS|TotalCPU|MaxRSS|CPUHours|CostUSD" \
      > "${CSV}"
  fi

  # Grab the main job step compute cost
  sacct -j "${SLURM_JOB_ID}" \
        --format=JobIDRaw,JobName,Partition,Elapsed,AllocCPUS,TotalCPU,MaxRSS \
        --parsable2 -n |
  grep "^${SLURM_JOB_ID}|" |
  awk -F'|' -v OFS='|' '{
    split($6, t, ":");
    seconds = t[1]*3600 + t[2]*60 + t[3];
    cpu_hours = seconds/3600;
    cost = cpu_hours * 0.025;
    print $0, cpu_hours, cost
  }' >> "${CSV}"

  # Email alert if cost exceeds $10
  last_cost=$(tail -n1 "${CSV}" | awk -F'|' '{print $NF}')
  if (( $(echo "${last_cost} > 10" | bc -l) )); then
    echo "X Job ${SLURM_JOB_ID} cost \$${last_cost}" \
      | mail -s "SLURM cost alert for ${SLURM_JOB_NAME}_${SLURM_JOB_ID}" sievertsen@ohsu.edu
  fi
}

trap log_usage EXIT
