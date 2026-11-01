#!/bin/bash
#SBATCH --job-name=sla-backfill
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=32 --exclusive
#SBATCH --mem=0
#SBATCH --time=06:00:00
#SBATCH --output=%x-%j.out

## refresh the catalog, backfill (missing + changed-source dates), then
## publish sums, mapping, catalog and manifest to the bucket.
##   sbatch backfill-sla.sh      # from the repo root on Setonix

module load singularity/4.1.0-slurm
module load rclone/1.68.1
export RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}

## per-WORKER GDAL limits: the defaults assume one process per machine
export GDAL_CACHEMAX=256                      # MB block cache per process
export GDAL_LOAD_EXTRA_DIM_METADATA_DELAY=0   # don't label 12k bands per open
export GDAL_PAM_ENABLED=NO                    # no .aux sidecar probing

cd "$SLURM_SUBMIT_DIR"
BUCKET=pawsey1197:aad-derived/trend-sla

bash build_catalog.sh || { echo "catalog FAILED" >&2; exit 1; }

## workers must equal --cpus-per-task (~600 MB each with the cache cap)
$RUN Rscript - <<'EOF'
library(arrow)      # FIRST, before anything loads GDAL
library(grist)
reg <- arrow::read_parquet("s2_registry.parquet")
files <- arrow::read_parquet("slafiles.parquet")
src <- stat_source("sla-cmems", files)
backfill(src, reg, workers = 32)
EOF

rclone copy --checksum sums/ $BUCKET/sums/ || echo "WARNING: sums copy FAILED" >&2
rclone copy --checksum mapping/ $BUCKET/mapping/ || echo "WARNING: mapping copy FAILED" >&2
for f in s2_registry.parquet slafiles.parquet; do
  rclone copyto --checksum $f $BUCKET/$f || echo "WARNING: $f copy FAILED" >&2
done
$RUN Rscript -e 'grist::write_manifest(".")' \
  && rclone copyto manifest.json $BUCKET/manifest.json \
  || echo "WARNING: manifest FAILED" >&2
