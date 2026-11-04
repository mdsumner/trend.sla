#!/bin/bash
## commit and push docs/data if the export changed it; a no-op otherwise.
## Unattended pushes need credentials that work without a prompt (a deploy
## key on an ssh remote, as trend.sst uses).
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/..}"
git add docs/data
if git diff --cached --quiet; then
  echo "site data unchanged"
else
  git commit -q -m "site data: regenerated from sums ($(date -u +%F))" && git push -q origin main \
    && echo "site data pushed"
fi
