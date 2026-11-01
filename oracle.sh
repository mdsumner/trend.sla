#!/bin/bash
## onboarding oracle: one date, mapped. 1997-11-15 is the peak of the
## 1997/98 El Nino: expect positive SLA along the central-eastern
## equatorial Pacific, negative in the west Pacific warm pool. Tests
## orientation (both axes) and band-to-date alignment at once.
set -eu
RUN=${RUN:?export RUN as the singularity exec line}
$RUN Rscript - <<'EOF'
library(arrow); library(grist)
reg <- read_parquet("s2_registry.parquet")
files <- read_parquet("slafiles.parquet")
src <- stat_source("sla-cmems", files)
d <- as.Date("1997-11-15")
i <- which(as.Date(files$date) == d)
out <- accumulate_date(files$dsn[i], d, src, reg, band = files$band[i],
                       out_path = "oracle-sums")
s <- read_parquet(out)
s$mean <- s$sumwx / s$sumw
cat(sprintf("cells %i; sla %.3f .. %.3f m; global mean %.4f m\n",
            nrow(s), min(s$mean), max(s$mean), sum(s$sumwx) / sum(s$sumw)))
ii <- match(s$cell, reg$cell)
png("oracle-1997-11-15.png", 1400, 700)
pal <- colorRampPalette(c("#2166ac", "#f7f7f7", "#b2182b"))(99)
cl <- pal[cut(pmax(-.3, pmin(.3, s$mean)), seq(-.3, .3, length.out = 100),
              labels = FALSE)]
plot(reg$lon[ii], reg$lat[ii], col = cl, pch = 15, cex = .6, asp = 1,
     main = "sla-cmems 1997-11-15: expect El Nino tongue, east eq. Pacific")
dev.off()
EOF
rm -rf oracle-sums
