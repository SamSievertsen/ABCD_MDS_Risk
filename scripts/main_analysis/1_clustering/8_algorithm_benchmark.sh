#!/usr/bin/env bash

#SBATCH --job-name=alg_benchmark
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=basic
#SBATCH --partition=basic
#SBATCH --nodes=1
#SBATCH --ntasks=1

#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=23:59:00

#SBATCH --chdir /home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk/
#SBATCH --export=all

# Strict Bash mode
set -euo pipefail
IFS=$'\n\t'

# Set paths
IMG=/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.8.sif
REPO=/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk

# Rmd location inside repo
RMD_REL="scripts/main_analysis/1_clustering/8_algorithm_benchmark.Rmd"

export REPO
export APPTAINER_CACHEDIR=/home/exacloud/gscratch/NagelLab/staff/${USER}/.apptainer_cache

# Threading controls
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export VECLIB_MAXIMUM_THREADS="${SLURM_CPUS_PER_TASK}"
export NUMEXPR_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

# Log directories grouped by date
TODAY=$(date +%Y-%m-%d)
LOGDIR="${REPO}/slurm_logs/${TODAY}"
USAGEDIR="${REPO}/slurm_usage_logs"
mkdir -p "${LOGDIR}" "${USAGEDIR}"

export DETAILED_LOG="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_detail.log"
: > "${DETAILED_LOG}"

export SUMMARY_CSV="${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}_summary.csv"
if [[ ! -f "${SUMMARY_CSV}" ]]; then
  echo "method,status,start_time,end_time,duration_min" > "${SUMMARY_CSV}"
fi

# Redirect stdout/stderr into dated logs
exec > >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out") \
     2> >(tee -a "${LOGDIR}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" >&2)

# Stamp logs with Git commit & container version
GIT_HASH=$(git -C "${REPO}" rev-parse HEAD || echo "NA")
echo "Git commit: ${GIT_HASH}"
echo "Container: ${IMG}"
echo "Rmd: ${REPO}/${RMD_REL}"
echo "REPO env: ${REPO}"
echo "CPUs: ${SLURM_CPUS_PER_TASK} | Mem: ${SLURM_MEM_PER_NODE:-NA} | Time: ${SLURM_TIMELIMIT:-NA}"

# Move to script directory
cd "${REPO}/scripts/main_analysis/1_clustering"

# Stream detailed log to stdout if the Rmd writes to it later
tail -F "${DETAILED_LOG}" & TAILPID=$!

# Render Rmd inside Apptainer
apptainer exec \
  -B /home/exacloud/gscratch/NagelLab:/home/exacloud/gscratch/NagelLab \
  "${IMG}" \
  Rscript -e "rmarkdown::render('${REPO}/${RMD_REL}', quiet = FALSE)"

# Stop background tail
kill "${TAILPID}" 2>/dev/null || true

# Post-run usage accounting on EXIT
function log_usage {
  CSV="${USAGEDIR}/usage.csv"

  if [[ ! -s "${CSV}" ]]; then
    echo "JobIDRaw|JobName|Partition|Elapsed|AllocCPUS|TotalCPU|MaxRSS|CPUHours|CostUSD" > "${CSV}"
  fi

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

  last_cost=$(tail -n1 "${CSV}" | awk -F'|' '{print $NF}')
  if command -v bc >/dev/null 2>&1; then
    if (( $(echo "${last_cost} > 10" | bc -l) )); then
      echo "X Job ${SLURM_JOB_ID} cost \$${last_cost}" \
        | mail -s "SLURM cost alert for ${SLURM_JOB_NAME}_${SLURM_JOB_ID}" sievertsen@ohsu.edu
    fi
  fi
}

trap log_usage EXIT