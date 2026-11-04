#!/bin/bash
## daily refresh of trend.sla, in one allocation (run by scrontab.txt):
## catalog + backfill + publish sums, then site export, then push docs/data.
## A failed step is reported and the later ones still run.
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export SLURM_SUBMIT_DIR="$PWD"
echo "trend.sla daily: $(date -u +%FT%TZ) in $PWD"
status=0
bash backfill-sla.sh         || { echo "backfill FAILED" >&2; status=1; }
bash data-raw/export_site.sh || { echo "site export FAILED" >&2; status=1; }
bash tools/publish_site.sh   || { echo "site push FAILED" >&2; status=1; }
echo "trend.sla daily: done $(date -u +%FT%TZ), status $status"
exit $status
