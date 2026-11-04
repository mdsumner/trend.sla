#!/bin/bash
#SBATCH --job-name=sla-site
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=16G --time=01:00:00
#SBATCH --output=%x-%j.out
## regenerate docs/data from the local sums (repo root is the cache
## layout: sums/, s2_registry.parquet, slafiles.parquet). Then commit
## and push docs/data with your usual credentials:
##   sbatch data-raw/export_site.sh
##   git add docs/data && git commit -m "site data" && git push
## Setonix modules: singularity/4.1.0-slurm needs pawseyenv/2024.05 (the
## default pawseyenv moved on), and a non-login shell needs Lmod first
if ! type module >/dev/null 2>&1; then _u=${-//[^u]/}; set +u; source /etc/profile; [ -n "$_u" ] && set -u; fi
module load pawseyenv/2024.05 singularity/4.1.0-slurm
command -v singularity >/dev/null || { echo "singularity not found after module load" >&2; exit 1; }
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}
cd "${SLURM_SUBMIT_DIR:-$PWD}"
$RUN Rscript data-raw/export_site.R . || { echo "export FAILED" >&2; exit 1; }
## modes page: EOFs of the monthly export just written (numpy only);
## a failure here leaves the previous eof-sla-cmems.json in place
$RUN python3 data-raw/eof.py docs/data || echo "WARNING: eof.py FAILED" >&2
