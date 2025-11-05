#!/usr/bin/env bash

## 4_feature_importance.sh ##

# Orchestrates k-prototypes Feature Importance:
#  1) pre-create reproducible seed list
#  2) submit SLURM array for per-seed runs (mode='seed')
#  3) submit aggregate job dependent on array completion (mode='aggregate')
#
# Usage:
#   bash scripts/main_analysis/1_clustering/4_feature_importance.sh submit   # default
#   bash scripts/main_analysis/1_clustering/4_feature_importance.sh local    # quick smoke test (seed=1)
#
# Notes:
#   - MAX_PAR controls concurrent array tasks (use 1 if each task takes all 36 CPUs)
#   - The RMD internally uses SLURM_CPUS_PER_TASK for future::plan("multicore", workers=...)
#   - We export OMP/MKL/BLAS threads = SLURM_CPUS_PER_TASK for speed in xgboost/BLAS
#   - We set DETAILED_LOG so your RMD writes per-job breadcrumbs

# Set bash strict mode (easy fail-fast)
set -euo pipefail
IFS=$'\n\t'

# Paths and container
PROJECT_DIR="${PROJECT_DIR:-/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk}"
CONTAINER="${CONTAINER:-/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.6.sif}"
APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache}"
RMD_REL="scripts/main_analysis/1_clustering/4_feature_importance.Rmd"
RMD="$PROJECT_DIR/$RMD_REL"

# SLURM parameters (can override via env)
ACCOUNT="${ACCOUNT:-basic}"
PARTITION="${PARTITION:-basic}"
N_SEEDS="${N_SEEDS:-50}"
CPUS="${CPUS:-36}"
MEM="${MEM:-256G}"
TIME="${TIME:-23:59:00}"
MAX_PAR="${MAX_PAR:-1}"
MAIL="${MAIL:-sievertsen@ohsu.edu}"
MAILTYPE="${MAILTYPE:-END,FAIL}"

# Mode: submit (default) vs local
MODE="${1:-submit}"

# Establish log directory setup
LOGROOT="$PROJECT_DIR/slurm_logs"
DATESTAMP="$(date +%F)"
LOGDIR="$LOGROOT/$DATESTAMP"
mkdir -p "$LOGDIR"

# Establish local mode for a quick smoke test (i.e., debugging)
if [[ "$MODE" == "local" ]]; then
  cd "$PROJECT_DIR"
  export DETAILED_LOG="$LOGDIR/fi_local_$(date +%s).log"
  echo "[local] Rendering seed=1 then aggregate..." | tee -a "$DETAILED_LOG"
  apptainer exec -B "$PROJECT_DIR:$PROJECT_DIR" "$CONTAINER" \
    Rscript -e "rmarkdown::render('$RMD_REL', params=list(mode='seed', seed_index=1), output_file='4_feature_importance_seed001.html')"
  apptainer exec -B "$PROJECT_DIR:$PROJECT_DIR" "$CONTAINER" \
    Rscript -e "rmarkdown::render('$RMD_REL', params=list(mode='aggregate'), output_file='4_feature_importance_summary.html')"
  exit 0
fi

# Guard clauses for required files and container
if [[ ! -f "$RMD" ]]; then
  echo "ERR: Rmd not found at $RMD" >&2
  exit 2
fi

if [[ ! -f "$CONTAINER" ]]; then
  echo "ERR: Container not found at $CONTAINER" >&2
  exit 3
fi

# List of seeds file and summary directory
SEED_SUM_DIR="$PROJECT_DIR/results/main_analysis/1_clustering/4_feature_importance/summary"
SEEDFILE="$SEED_SUM_DIR/seedlist.csv"
mkdir -p "$SEED_SUM_DIR"

# Create seedlist.csv with set.seed(123) if missing
if [[ ! -f "$SEEDFILE" ]]; then
  echo "[init] Creating seedlist.csv with set.seed(123) ($N_SEEDS seeds) → $SEEDFILE"
  apptainer exec -B "$PROJECT_DIR:$PROJECT_DIR" "$CONTAINER" Rscript - <<EOF
dir.create("$SEED_SUM_DIR", recursive=TRUE, showWarnings=FALSE)
set.seed(123L)
seeds <- sample.int(.Machine$integer.max, size = as.integer("$N_SEEDS"))
df <- data.frame(idx = seq_along(seeds), seed = seeds)
readr::write_csv(df, "$SEEDFILE")
EOF
fi

# Store SBATCH options to be used across jobs
SBATCH_COMMON=(
  --account="$ACCOUNT"
  --partition="$PARTITION"
  --mail-type="$MAILTYPE"
  --mail-user="$MAIL"
  --export=ALL)

# List of array job wrap script (per-seed)
ARRAY_WRAP=$(cat <<'EOS'
set -euo pipefail
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export BLIS_NUM_THREADS=1
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export APPTAINER_CACHEDIR="%APPTAINER_CACHEDIR%"
cd "%PROJECT_DIR%"
export DETAILED_LOG="%LOGDIR%/fi_detail_\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}.log"
# Sanity check on kproto RDS (anchor)
KPROTO_RDS="%PROJECT_DIR%/data/data_processed/kproto_results/kproto_robust.rds"
if [[ ! -f "$KPROTO_RDS" ]]; then
  echo "$(date +'%F %T')|FATAL|missing_kproto|$KPROTO_RDS" >> "$DETAILED_LOG"
  exit 4
fi
# Render single seed
apptainer exec -B "%PROJECT_DIR%:%PROJECT_DIR%" "%CONTAINER%" \
  Rscript -e "rmarkdown::render('%RMD_REL%', params=list(mode='seed', seed_index=as.integer(Sys.getenv('SLURM_ARRAY_TASK_ID'))), output_file=sprintf('4_feature_importance_seed%03d.html', as.integer(Sys.getenv('SLURM_ARRAY_TASK_ID'))), quiet=FALSE)"
EOS
)

# Replace placeholders in ARRAY_WRAP
ARRAY_WRAP="${ARRAY_WRAP//%PROJECT_DIR%/$PROJECT_DIR}"
ARRAY_WRAP="${ARRAY_WRAP//%CONTAINER%/$CONTAINER}"
ARRAY_WRAP="${ARRAY_WRAP//%RMD_REL%/$RMD_REL}"
ARRAY_WRAP="${ARRAY_WRAP//%LOGDIR%/$LOGDIR}"
ARRAY_WRAP="${ARRAY_WRAP//%APPTAINER_CACHEDIR%/$APPTAINER_CACHEDIR}"

# Submit array job for per-seed runs
ARRAY_JOBID=$(sbatch --parsable \
  "${SBATCH_COMMON[@]}" \
  --job-name=fi_kproto \
  --nodes=1 --ntasks=1 \
  --cpus-per-task="$CPUS" \
  --mem="$MEM" \
  --time="$TIME" \
  --array=1-"$N_SEEDS"%$MAX_PAR \
  --output="$LOGDIR/fi_kproto_%A_%a.out" \
  --error="$LOGDIR/fi_kproto_%A_%a.err" \
  --wrap "$ARRAY_WRAP")
echo "Submitted array job: $ARRAY_JOBID"

# Submit aggregate job dependent on array completion
AGG_WRAP=$(cat <<'EOS'
set -euo pipefail
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export BLIS_NUM_THREADS=8
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export APPTAINER_CACHEDIR="%APPTAINER_CACHEDIR%"
cd "%PROJECT_DIR%"
export DETAILED_LOG="%LOGDIR%/fi_detail_\${SLURM_JOB_ID}.log"
apptainer exec -B "%PROJECT_DIR%:%PROJECT_DIR%" "%CONTAINER%" \
  Rscript -e "rmarkdown::render('%RMD_REL%', params=list(mode='aggregate'), output_file='4_feature_importance_summary.html', quiet=FALSE)"
EOS
)

# Replace placeholders in AGG_WRAP
AGG_WRAP="${AGG_WRAP//%PROJECT_DIR%/$PROJECT_DIR}"
AGG_WRAP="${AGG_WRAP//%CONTAINER%/$CONTAINER}"
AGG_WRAP="${AGG_WRAP//%RMD_REL%/$RMD_REL}"
AGG_WRAP="${AGG_WRAP//%LOGDIR%/$LOGDIR}"
AGG_WRAP="${AGG_WRAP//%APPTAINER_CACHEDIR%/$APPTAINER_CACHEDIR}"

# Submit aggregate job
AGG_JOBID=$(sbatch --parsable \
  "${SBATCH_COMMON[@]}" \
  --job-name=fi_kproto_agg \
  --nodes=1 --ntasks=1 \
  --cpus-per-task=8 \
  --mem=64G \
  --time=04:00:00 \
  --dependency=afterok:"$ARRAY_JOBID" \
  --output="$LOGDIR/fi_kproto_agg_%j.out" \
  --error="$LOGDIR/fi_kproto_agg_%j.err" \
  --wrap "$AGG_WRAP"
)
echo "Submitted aggregate job (afterok): $AGG_JOBID"
