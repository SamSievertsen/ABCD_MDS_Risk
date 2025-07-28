#!/usr/bin/env bash

## 2.1_run_k_calculation_pipeline.sh ##
## Master submission script: launches partial array -> merges -> final consensus ##

# Use strict Bash mode (fast error out)
set -euo pipefail
IFS=$'\n\t'

# Submit the 35 task array for one index x one k partial validations
PARTIAL_JID=$(sbatch --parsable 2.2_partial_k_calc_validation.sh)

# For each of the 5 indices, submit a merge job that depends on that index's 7
# partial tasks finishing successfully
declare -a MERGE_JIDS
INDICES=(silhouette cindex gamma ptbiserial tau)

# Run each of the indices in a nested loop
for i in "${!INDICES[@]}"; do
  idx="${INDICES[$i]}"

  # Compute the 7 array-task IDs for this index
  start=$(( i * 7 + 1 ))
  end=$(( i * 7 + 7 ))
  deps=""
  for t in $(seq "$start" "$end"); do
    deps+="${PARTIAL_JID}_$t:"
  done
  deps=${deps%:}

  # Merge the products of the partial jobs
  MERGE_JIDS[$i]=$(sbatch --parsable \
    --export=ALL,IDX="${idx}" \
    --dependency=afterok:"${deps}" \
    2.3_merge_k_calc_validation.sh)
done

# Once all partial jobs are completed & merged, submit the consensus & plot job
ALL_MERGE_DEPS=$(IFS=:; echo "${MERGE_JIDS[*]}")
sbatch --dependency=afterok:"${ALL_MERGE_DEPS}" 2.4_k_calc_consensus.sh

# Print statements describing the partial and whole jobs' status
echo "Partial array job: $PARTIAL_JID"
echo "Merge jobs: ${MERGE_JIDS[*]}"
echo "Final consensus will run after merges."

