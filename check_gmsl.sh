#!/bin/bash
## whole-record validation: the daily global mean of the cell sums
## should reproduce the published altimetry sea level record
## (trend ~3.1-3.3 mm/yr over 1993-2025, upward curvature, annual cycle,
## 1997/98 and 2015/16 El Nino peaks). Login node is fine.
set -eu
RUN=${RUN:?export RUN as the singularity exec line}
$RUN Rscript - <<'EOF'
library(arrow); library(grist)
s <- series_stats("sums/sla-cmems")
cat(nrow(s), "dates;", format(min(s$date)), "to", format(max(s$date)), "\n")
fit <- lm(mean ~ as.numeric(date), data = s)
cat(sprintf("trend: %.2f mm/yr\n", coef(fit)[2] * 365.25 * 1000))
png("gmsl-check.png", 1400, 500)
plot(s$date, s$mean * 1000, type = "l", col = "grey40",
     ylab = "global mean SLA (mm)", xlab = "",
     main = "sla-cmems global mean (cell sums, area-weighted)")
abline(fit$coefficients[1] * 1000, fit$coefficients[2] * 1000, col = "red")
dev.off()
EOF
