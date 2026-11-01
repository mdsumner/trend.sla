#!/bin/bash
#SBATCH --job-name=sla-site
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=16G --time=01:00:00
#SBATCH --output=%x-%j.out
## regenerate docs/data from the local sums (repo root is the cache
## layout: sums/, s2_registry.parquet, slafiles.parquet). Then commit
## and push docs/data with your usual credentials:
##   sbatch data-raw/export_site.sh
##   git add docs/data && git commit -m "site data" && git push
module load singularity/4.1.0-slurm
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}
cd "${SLURM_SUBMIT_DIR:-$PWD}"
$RUN Rscript data-raw/export_site.R . || { echo "export FAILED" >&2; exit 1; }
