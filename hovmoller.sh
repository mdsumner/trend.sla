#!/bin/bash
## Kelvin-wave Hovmoller: daily SLA along the equatorial Pacific, 2026.
## Equatorial cells (centre within 3 deg of the equator), Pacific
## longitudes, one column per cell longitude, one row per day. An
## eastward-propagating Kelvin wave shows as a diagonal band of positive
## anomaly. Answers the climate.us 2026 El Nino Kelvin wave animation
## from this store. Reads local sums; login node is fine.
##   bash hovmoller.sh [start-date]      # default 2026-01-01
set -eu
RUN=${RUN:?export RUN as the singularity exec line}
START=${1:-2026-01-01}
$RUN Rscript - "$START" <<'EOF'
library(arrow); library(dplyr)
start <- as.Date(commandArgs(TRUE)[1])
reg <- read_parquet("s2_registry.parquet")
eq <- reg |> mutate(lon360 = ifelse(lon < 0, lon + 360, lon)) |>
  filter(abs(lat) <= 3, lon360 >= 120, lon360 <= 282)
d <- open_dataset("sums/sla-cmems") |>
  filter(date >= start, cell %in% eq$cell) |>
  select(cell, date, sumw, sumwx) |> collect() |>
  inner_join(eq[c("cell", "lon360")], by = "cell") |>
  mutate(lonb = round(lon360, 1)) |>
  group_by(lonb, date) |>
  summarise(sla = sum(sumwx) / sum(sumw) * 1000, .groups = "drop")
## subtract each day's GLOBAL mean: removes the long-term rise (~100 mm
## since the 1993-2012 reference) and the global seasonal cycle, leaving
## the equatorial structure itself -- what regional anomaly maps show
gm <- open_dataset("sums/sla-cmems") |> filter(date >= start) |>
  group_by(date) |> summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |> mutate(g = sumwx / sumw * 1000)
d <- d |> inner_join(gm[c("date", "g")], by = "date") |> mutate(sla = sla - g)
lons <- sort(unique(d$lonb)); days <- sort(unique(d$date))
cat(sprintf("%i equatorial cells, %i longitude columns, %s to %s\n",
            nrow(eq), length(lons), min(days), max(days)))
dl <- diff(lons); hw <- c(dl[1], dl) / 2; hw2 <- c(dl, dl[length(dl)]) / 2
xl <- (lons - hw)[match(d$lonb, lons)]; xr <- (lons + hw2)[match(d$lonb, lons)]
lim <- 250
pal <- colorRampPalette(c("#2166ac", "#67a9cf", "#f7f7f7", "#ef8a62", "#b2182b"))(101)
cl <- pal[round((pmax(-lim, pmin(lim, d$sla)) + lim) / (2 * lim) * 100) + 1]
png("kelvin-hovmoller.png", 900, 1100)
par(mar = c(5, 6, 4, 2))
plot(NA, xlim = range(c(xl, xr)), ylim = rev(range(days)), axes = FALSE,
     xlab = "longitude", ylab = "",
     main = sprintf("Equatorial Pacific sea level anomaly minus global mean (mm), %s to %s",
                    min(days), max(days)))
rect(xl, as.numeric(d$date) - 0.5, xr, as.numeric(d$date) + 0.5,
     col = cl, border = NA)
at <- seq(120, 280, by = 20)
axis(1, at = at, labels = ifelse(at > 180, paste0(360 - at, "W"),
                                 ifelse(at == 180, "180", paste0(at, "E"))))
mo <- seq(as.Date(format(min(days), "%Y-%m-01")), max(days), by = "month")
axis(2, at = as.numeric(mo), labels = format(mo, "%b %Y"), las = 1)
box()
mtext(sprintf("colour: -%i to +%i mm; S2 level-5 cells within 3 deg of the equator", lim, lim),
      side = 1, line = 3.5, cex = 0.8)
dev.off()
cat("wrote kelvin-hovmoller.png\n")
EOF
