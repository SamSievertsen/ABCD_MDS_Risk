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

set -euo pipefail
IFS=$'\n\t'

# Paths and container
PROJECT_DIR="${PROJECT_DIR:-/home/exacloud/gscratch/NagelLab/staff/sam/projects/ABCD_MDS_Risk}"
CONTAINER="${CONTAINER:-/home/exacloud/gscratch/NagelLab/staff/sam/packages/abcd-mds-risk-r_0.1.7.sif}"
APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/home/exacloud/gscratch/NagelLab/staff/sam/.apptainer_cache}"

RMD_DIR="$PROJECT_DIR/scripts/main_analysis/1_clustering"
RMD_FILE="4_feature_importance.rmd"

RMD_PATH="$RMD_DIR/$RMD_FILE"

# SLURM parameters (env-overridable)
ACCOUNT="${ACCOUNT:-basic}"
PARTITION="${PARTITION:-basic}"
N_SEEDS="${N_SEEDS:-50}"
CPUS="${CPUS:-8}"
MEM="${MEM:-64G}"
TIME="${TIME:-23:59:00}"
MAX_PAR="${MAX_PAR:-1}"
MAIL="${MAIL:-sievertsen@ohsu.edu}"
MAILTYPE="${MAILTYPE:-END,FAIL}"

MODE="${1:-submit}"

# Logs
LOGROOT="$PROJECT_DIR/slurm_logs"
DATESTAMP="$(date +%F)"
LOGDIR="$LOGROOT/$DATESTAMP"
mkdir -p "$LOGDIR"

# Local smoke test (seed=1 then aggregate)
if [[ "$MODE" == "local" ]]; then
  cd "$RMD_DIR"
  export DETAILED_LOG="$LOGDIR/fi_local_$(date +%s).log"
  echo "[local] Rendering seed=1 then aggregate..." | tee -a "$DETAILED_LOG"
  apptainer exec --bind "$PROJECT_DIR":"$PROJECT_DIR" "$CONTAINER" \
    Rscript -e "rmarkdown::render('$RMD_FILE', params=list(mode='seed', seed_index=1), output_file='4_feature_importance_seed001.html')"
  apptainer exec --bind "$PROJECT_DIR":"$PROJECT_DIR" "$CONTAINER" \
    Rscript -e "rmarkdown::render('$RMD_FILE', params=list(mode='aggregate'), output_file='4_feature_importance_summary.html')"
  exit 0
fi

# Guards
if [[ ! -f "$RMD_PATH" ]]; then
  echo "ERR: Rmd not found at $RMD_PATH" >&2
  exit 2
fi
if [[ ! -f "$CONTAINER" ]]; then
  echo "ERR: Container not found at $CONTAINER" >&2
  exit 3
fi

# Seedlist (avoid root .Rprofile by working in the Rmd dir)
SEED_SUM_DIR="$PROJECT_DIR/results/main_analysis/1_clustering/4_feature_importance/summary"
SEEDFILE="$SEED_SUM_DIR/seedlist.csv"
mkdir -p "$SEED_SUM_DIR"

if [[ ! -f "$SEEDFILE" ]]; then
  echo "[init] Creating seedlist.csv with set.seed(123) ($N_SEEDS seeds) -> $SEEDFILE"
  cd "$RMD_DIR"
  apptainer exec -B "$PROJECT_DIR:$PROJECT_DIR" "$CONTAINER" Rscript - <<EOF
dir.create("$SEED_SUM_DIR", recursive=TRUE, showWarnings=FALSE)
set.seed(123L)
seeds <- sample.int(.Machine\$integer.max, size = as.integer($N_SEEDS))
df <- data.frame(idx = seq_along(seeds), seed = seeds)
readr::write_csv(df, "$SEEDFILE")
EOF
fi

# Guard seedlist size vs. array size, just in case N_SEEDS changes between runs and the old seedlist.csv lingers
SEED_COUNT=$(awk 'END{print NR-1}' "$SEEDFILE")  # minus header
if [[ "$SEED_COUNT" -ne "$N_SEEDS" ]]; then
  echo "[init] Rebuilding seedlist to match N_SEEDS=$N_SEEDS (was $SEED_COUNT)"
  cd "$RMD_DIR"
  apptainer exec -B "$PROJECT_DIR:$PROJECT_DIR" "$CONTAINER" Rscript - <<EOF
dir.create("$SEED_SUM_DIR", recursive=TRUE, showWarnings=FALSE)
set.seed(123L)
seeds <- sample.int(.Machine\$integer.max, size = as.integer($N_SEEDS))
df <- data.frame(idx = seq_along(seeds), seed = seeds)
readr::write_csv(df, "$SEEDFILE")
EOF
fi

# Common SBATCH flags
SBATCH_COMMON=(
  --account="$ACCOUNT"
  --partition="$PARTITION"
  --mail-type="$MAILTYPE"
  --mail-user="$MAIL"
  --export=ALL
)

# Array wrapper (per-seed) 
ARRAY_WRAP=$(cat <<'EOS'
set -eu

# Enable pipefail only in bash shells
if [ -n "${BASH_VERSION-}" ]; then set -o pipefail; fi

# Guard SLURM vars for set -u contexts (fallbacks are safe)
: "${SLURM_CPUS_PER_TASK:=1}"
: "${SLURM_ARRAY_JOB_ID:=0}"
: "${SLURM_ARRAY_TASK_ID:=1}"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export BLIS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export APPTAINER_CACHEDIR="%APPTAINER_CACHEDIR%"
export DETAILED_LOG="%LOGDIR%/fi_detail_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.log"

# Localize paths/filenames to avoid relying on caller env (fixes: RMD_FILE unbound with set -u)
RMD_DIR="%RMD_DIR%"
RMD_FILE="%RMD_FILE%"

# Work in the Rmd directory (prevents root .Rprofile -> renv autoload)
cd "$RMD_DIR"

# Sanity check kproto anchor
KPROTO_RDS="%PROJECT_DIR%/data/data_processed/kproto_results/kproto_z_score.rds"
if [[ ! -f "$KPROTO_RDS" ]]; then
  echo "$(date +'%F %T')|FATAL|missing_kproto|$KPROTO_RDS" >> "$DETAILED_LOG"
  exit 4
fi

# Render single seed (write each job to a temp HTML and delete to avoid per-seed HTML clutter)
apptainer exec -B "%PROJECT_DIR%:%PROJECT_DIR%" "%CONTAINER%" \
  Rscript -e "seed <- as.integer(Sys.getenv('SLURM_ARRAY_TASK_ID'));
              out <- tempfile(pattern = sprintf('fi_seed_%03d_', seed), fileext = '.html');
              rmarkdown::render('$RMD_FILE', params = list(mode='seed', seed_index = seed),
              	output_file = out, quiet = TRUE, clean = TRUE);
              unlink(out, force = TRUE)"
EOS
)

ARRAY_WRAP="${ARRAY_WRAP//%PROJECT_DIR%/$PROJECT_DIR}"
ARRAY_WRAP="${ARRAY_WRAP//%CONTAINER%/$CONTAINER}"
ARRAY_WRAP="${ARRAY_WRAP//%RMD_DIR%/$RMD_DIR}"
ARRAY_WRAP="${ARRAY_WRAP//%RMD_FILE%/$RMD_FILE}"
ARRAY_WRAP="${ARRAY_WRAP//%LOGDIR%/$LOGDIR}"
ARRAY_WRAP="${ARRAY_WRAP//%APPTAINER_CACHEDIR%/$APPTAINER_CACHEDIR}"

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

# Aggregate wrapper (depends on array ok)
AGG_WRAP=$(cat <<'EOS'
set -eu
if [ -n "${BASH_VERSION-}" ]; then set -o pipefail; fi

: "${SLURM_JOB_ID:=0}"

export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export BLIS_NUM_THREADS=8
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export APPTAINER_CACHEDIR="%APPTAINER_CACHEDIR%"
export DETAILED_LOG="%LOGDIR%/fi_detail_${SLURM_JOB_ID}.log"

# Localize paths/filenames (see note above)
RMD_DIR="%RMD_DIR%"
RMD_FILE="%RMD_FILE%"

cd "$RMD_DIR"

apptainer exec -B "%PROJECT_DIR%:%PROJECT_DIR%" "%CONTAINER%" \
  Rscript -e "rmarkdown::render('$RMD_FILE', params=list(mode='aggregate'),
                                output_file='4_feature_importance_summary.html', quiet=FALSE)"
EOS
)

AGG_WRAP="${AGG_WRAP//%PROJECT_DIR%/$PROJECT_DIR}"
AGG_WRAP="${AGG_WRAP//%CONTAINER%/$CONTAINER}"
AGG_WRAP="${AGG_WRAP//%RMD_DIR%/$RMD_DIR}"
AGG_WRAP="${AGG_WRAP//%RMD_FILE%/$RMD_FILE}"
AGG_WRAP="${AGG_WRAP//%LOGDIR%/$LOGDIR}"
AGG_WRAP="${AGG_WRAP//%APPTAINER_CACHEDIR%/$APPTAINER_CACHEDIR}"

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
  --wrap "$AGG_WRAP")
echo "Submitted aggregate job (afterok): $AGG_JOBID"
