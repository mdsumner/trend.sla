#!/bin/bash
#SBATCH --job-name=sla-backfill
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=32 --exclusive
#SBATCH --mem=0
#SBATCH --time=06:00:00
#SBATCH --output=%x-%j.out

## refresh the catalog, backfill (missing + changed-source dates), then
## publish sums, mapping, catalog and manifest to the bucket.
##   sbatch backfill-sla.sh      # from the repo root on Setonix

## Setonix modules: singularity/4.1.0-slurm needs pawseyenv/2024.05 (the
## default pawseyenv moved on), and a non-login shell needs Lmod first
if ! type module >/dev/null 2>&1; then _u=${-//[^u]/}; set +u; source /etc/profile; [ -n "$_u" ] && set -u; fi
module load pawseyenv/2024.05 singularity/4.1.0-slurm
command -v singularity >/dev/null || { echo "singularity not found after module load" >&2; exit 1; }
module load rclone/1.68.1
export RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}

## per-WORKER GDAL limits: the defaults assume one process per machine
export GDAL_CACHEMAX=256                      # MB block cache per process
export GDAL_LOAD_EXTRA_DIM_METADATA_DELAY=0   # don't label 12k bands per open
export GDAL_PAM_ENABLED=NO                    # no .aux sidecar probing

## sbatch sets SLURM_SUBMIT_DIR; scrontab uses --chdir
cd "${SLURM_SUBMIT_DIR:-$PWD}"
BUCKET=pawsey1197:aad-derived/trend-sla

bash build_catalog.sh || { echo "catalog FAILED" >&2; exit 1; }

## workers = allocated CPUs (~600 MB each with the cache cap)
$RUN Rscript - <<'EOF'
library(arrow)      # FIRST, before anything loads GDAL
library(grist)
reg <- arrow::read_parquet("s2_registry.parquet")
files <- arrow::read_parquet("slafiles.parquet")
src <- stat_source("sla-cmems", files)
backfill(src, reg, workers = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "32")))
EOF

rclone copy --checksum sums/ $BUCKET/sums/ || echo "WARNING: sums copy FAILED" >&2
rclone copy --checksum mapping/ $BUCKET/mapping/ || echo "WARNING: mapping copy FAILED" >&2
for f in s2_registry.parquet slafiles.parquet; do
  rclone copyto --checksum $f $BUCKET/$f || echo "WARNING: $f copy FAILED" >&2
done
$RUN Rscript -e 'grist::write_manifest(".")' \
  && rclone copyto manifest.json $BUCKET/manifest.json \
  || echo "WARNING: manifest FAILED" >&2
