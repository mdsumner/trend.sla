#!/bin/bash
## build_catalog.sh -- write slafiles.parquet, one row per date:
## delayed-time (MY) rows, then near-real-time (NRT) rows for dates
## after MY ends (the interleave rule raad uses for the same product).
## Stores are found through cmemsarco; both time axes are read from the
## stores themselves. Light: login node is fine. Needs RUN exported.
set -eu
RUN=${RUN:?export RUN as the singularity exec line}

$RUN Rscript - <<'EOF'
library(dplyr); library(cmemsarco)
sl <- cmems_catalog_data |> cmems_arco_only() |>
  filter(grepl("SEALEVEL_GLO_PHY_L4", product_id))
pick <- function(pat) {
  x <- sl |> filter(grepl(pat, dataset_id)) |> cmems_latest()
  if (nrow(x) != 1) {
    print(as.data.frame(x[c("product_id", "dataset_id")]))
    stop("pick: ", pat)
  }
  sub('^ZARR:"/vsicurl/(.*)"$', "\\1", x$timeChunked_gdal)
}
urls <- c(my  = pick("ssh_my_allsat-l4-duacs-0.125deg_P1D$"),
          nrt = pick("ssh_nrt_allsat-l4-duacs-0.125deg_P1D$"))
writeLines(urls, "store_urls.txt")
## the NRT grid must equal the MY grid: the mapping is shared
g <- lapply(urls, function(u)
  vapour::vapour_raster_info(sprintf('ZARR:"/vsicurl/%s":/sla', u))[c("dimension", "extent")])
stopifnot(identical(g$my$dimension, g$nrt$dimension),
          isTRUE(all.equal(g$my$extent, g$nrt$extent)))
cat("grids match:", g$my$dimension, "\n")
EOF

$RUN python3 - <<'EOF'
from osgeo import gdal
gdal.UseExceptions()
for name, url in zip(("my", "nrt"), open("store_urls.txt").read().split()):
    ds = gdal.OpenEx('ZARR:"/vsicurl/%s"' % url, gdal.OF_MULTIDIM_RASTER)
    v = ds.GetRootGroup().OpenMDArray("time").ReadAsArray()
    open("time_%s.txt" % name, "w").write("\n".join(str(float(x)) for x in v))
    print(name, v.size)
EOF

$RUN Rscript - <<'EOF'
library(arrow)
urls <- readLines("store_urls.txt")
## the stores' time variable carries no CF units; days since 1950-01-01
## was verified at both ends against the documented record span
one <- function(url, file) {
  raw <- scan(file, quiet = TRUE)
  stopifnot(all(diff(raw) == 1))           # daily, no holes
  data.frame(date = as.Date("1950-01-01") + raw,
             dsn = sprintf('vrt://ZARR:"/vsicurl/%s":/sla?bands=%i', url, seq_along(raw)),
             band = 1L)
}
my  <- one(urls[1], "time_my.txt")
nrt <- one(urls[2], "time_nrt.txt")
files <- rbind(my, nrt[nrt$date > max(my$date), ])
stopifnot(!anyDuplicated(files$date), all(diff(files$date) == 1))
cat(sprintf("MY %s..%s (%i)  NRT tail %s..%s (%i)  total %i\n",
            min(my$date), max(my$date), nrow(my),
            min(nrt$date[nrt$date > max(my$date)]), max(files$date),
            nrow(files) - nrow(my), nrow(files)))
## report (not block) source changes against the previous catalog:
## grist re-plans exactly these dates from recorded provenance
if (file.exists("slafiles.parquet")) {
  old <- read_parquet("slafiles.parquet")
  m <- match(as.character(old$date), as.character(files$date))
  chg <- sum(!is.na(m) & old$dsn != files$dsn[m])
  cat(sprintf("vs previous catalog: %i dates changed source, %i new dates\n",
              chg, sum(!as.character(files$date) %in% as.character(old$date))))
}
write_parquet(files, "slafiles.parquet")
EOF
