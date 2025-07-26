#!/usr/bin/env bash

#SBATCH --job-name=risk_group_k_calc
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sievertsen@ohsu.edu

#SBATCH --account=NagelLab
#SBATCH --partition=batch
#SBATCH --qos=highio
#SBATCH --time=36:00:00

#SBATCH --nodes=1
#SBATCH --ntasks=6               # 5 validations + 1 consensus step
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=32G

#SBATCH --chdir /home/exacloud/gscratch/NagelLab/staff/sam
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

# Change directories to the appropriate script location
cd "${REPO}/scripts/main_analysis/2_risk_group_k_calculation"

# Stream detailed log to watch progress in real time
tail -F "${DETAILED_LOG}" & TAILPID=$!

# Run the five validations in parallel, one srun per index
INDICES=(silhouette cindex gamma ptbiserial tau)
for idx in "${INDICES[@]}"; do
  echo "Starting validation index: $idx" >> "${DETAILED_LOG}"
  srun --exclusive -n1 \
    apptainer exec \
      -B /home/exacloud/gscratch/NagelLab:/home/exacloud/gscratch/NagelLab \
      "${IMG}" \
      Rscript -e "rmarkdown::render(
        '2_risk_group_k_calculation.Rmd',
        params = list(validation_index = '$idx'),
        quiet = FALSE
      )" \
    &>> "${LOGDIR}/${SLURM_JOB_NAME}_${idx}.log" &
done

# Wait for all five to complete
wait

# Run the all job (consensus + plotting) in the same allocation
echo "Starting consensus plot step (idx = all)" >> "${DETAILED_LOG}"
srun -n1 \
  apptainer exec \
    -B /home/exacloud/gscratch/NagelLab:/home/exacloud/gscratch/NagelLab \
    "${IMG}" \
    Rscript -e "rmarkdown::render(
      '2_risk_group_k_calculation.Rmd',
      params = list(validation_index = 'all'),
      quiet = FALSE
    )" \
  &>> "${LOGDIR}/${SLURM_JOB_NAME}_all.log"

# Stop the background tail on exit
kill "$TAILPID" 2>/dev/null || true

#
# 3) Post‐run usage accounting (on EXIT)
#
function log_usage {
  CSV="${USAGEDIR}/usage.csv"
  if [[ ! -s "${CSV}" ]]; then
    echo "JobIDRaw|JobName|Partition|Elapsed|AllocCPUS|TotalCPU|MaxRSS|CPUHours|CostUSD" > "${CSV}"
  fi

  sacct -j "${SLURM_JOB_ID}" \
        --format=JobIDRaw,JobName,Partition,Elapsed,AllocCPUS,TotalCPU,MaxRSS \
        --parsable2 -n \
  | grep "^${SLURM_JOB_ID}|" \
  | awk -F'|' -v OFS='|' '{
      split($6, t, ":");
      seconds = t[1]*3600 + t[2]*60 + t[3];
      cpu_hours = seconds/3600;
      cost = cpu_hours * 0.025;
      print $0, cpu_hours, cost
    }' >> "${CSV}"

  # Email alert if cost exceeds $10
  last_cost=$(tail -n1 "${CSV}" | awk -F'|' '{print $NF}')
  if (( $(echo "${last_cost} > 10" | bc -l) )); then
    echo "Job ${SLURM_JOB_ID} cost \$${last_cost}" \
      | mail -s "SLURM cost alert for ${SLURM_JOB_NAME}_${SLURM_JOB_ID}" sievertsen@ohsu.edu
  fi
}
trap log_usage EXIT

