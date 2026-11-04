#!/bin/bash
#SBATCH --job-name=sla-memprobe
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2 --mem=32G --time=00:30:00
#SBATCH --output=%x-%j.out
## one worker's memory and time across 10 dates, read from inside the
## container: flat after date 1 = fixed per-worker cost (set workers by
## it); climbing = a leak. Run from the repo root: sbatch tools/memprobe.sh
## Setonix modules: singularity/4.1.0-slurm needs pawseyenv/2024.05 (the
## default pawseyenv moved on), and a non-login shell needs Lmod first
if ! type module >/dev/null 2>&1; then _u=${-//[^u]/}; set +u; source /etc/profile; [ -n "$_u" ] && set -u; fi
module load pawseyenv/2024.05 singularity/4.1.0-slurm
command -v singularity >/dev/null || { echo "singularity not found after module load" >&2; exit 1; }
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}
export GDAL_CACHEMAX=256 GDAL_LOAD_EXTRA_DIM_METADATA_DELAY=0 GDAL_PAM_ENABLED=NO
cd "$SLURM_SUBMIT_DIR"
$RUN Rscript - <<'EOF'
library(arrow); library(grist)
rss <- function() as.numeric(gsub("[^0-9]+", "", grep("^VmRSS",
                  readLines("/proc/self/status"), value = TRUE))) / 1024
reg <- arrow::read_parquet("s2_registry.parquet")
f <- arrow::read_parquet("slafiles.parquet")
src <- stat_source("sla-cmems", f)
cat(sprintf("start: %.0f MB\n", rss()))
for (i in 2001:2010) {
  t <- system.time(accumulate_date(f$dsn[i], f$date[i], src, reg,
                   band = f$band[i], out_path = "probe-sums"))[3]
  cat(sprintf("date %i: %.0f MB after, %.1f s\n", i, rss(), t))
}
EOF
rm -rf probe-sums
