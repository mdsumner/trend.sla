#!/bin/bash
## forensics-zarr.sh -- layered probes of the CMEMS ARCO timeChunked
## store, each isolating ONE layer, so timings assign blame.
## Run in $MYSCRATCH/trend.sla with RUN and R_LIBS_USER set.
## Probes are tiny (a few chunks each); login node is fine.
##
##   bash forensics-zarr.sh 2>&1 | tee forensics-$(date +%H%M).log

set -u
URL="https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr"
RUN=${RUN:?set RUN to the singularity exec line}

echo "==================================================================="
echo "P0: store facts -- confirm chunking really is (1, 720, 512)"
echo "==================================================================="
$RUN python3 - <<EOF
from osgeo import gdal, gdal_array
gdal.UseExceptions()
ds = gdal.OpenEx('ZARR:"/vsicurl/$URL"', gdal.OF_MULTIDIM_RASTER)
a = ds.GetRootGroup().OpenMDArray("sla")
print("dims:", [d.GetSize() for d in a.GetDimensions()])
print("block:", a.GetBlockSize())
print("dtype:", a.GetDataType().GetName())
EOF

echo "==================================================================="
echo "P1: raw HTTP -- one chunk by curl, x3. Bucket latency/throughput"
echo "    baseline with no GDAL anywhere. (zarr v2 keys: t.lat.lon)"
echo "==================================================================="
for i in 1 2 3; do
  curl -s -o /tmp/chunk.bin -w "try $i: %{time_total}s  %{size_download} bytes  connect %{time_connect}s  ttfb %{time_starttransfer}s\n" \
    "$URL/sla/1779.0.0"
done

echo "==================================================================="
echo "P2: four chunks in PARALLEL by curl -- per-connection vs per-IP"
echo "    throttling (the 'it was faster before' question)"
echo "==================================================================="
time ( for k in 1779.0.0 1779.0.1 1779.0.2 1779.1.0; do
  curl -s -o /dev/null "$URL/sla/$k" &
done; wait )

echo "==================================================================="
echo "P3: mdim, open cost vs read cost split"
echo "==================================================================="
$RUN python3 - <<EOF
import time
from osgeo import gdal, gdal_array
gdal.UseExceptions()
t0 = time.time()
ds = gdal.OpenEx('ZARR:"/vsicurl/$URL"', gdal.OF_MULTIDIM_RASTER)
rg = ds.GetRootGroup(); t1 = time.time()
a = rg.OpenMDArray("sla"); t2 = time.time()
v = a[1779].ReadAsArray(); t3 = time.time()
print("open: %.2fs  openarray: %.2fs  read whole day: %.2fs" %
      (t1 - t0, t2 - t1, t3 - t2))
EOF

echo "==================================================================="
echo "P4: classic-view OPEN cost, default vs DELAY=0 -- what band"
echo "    labelling costs per open (every read in the backfill pays it)"
echo "==================================================================="
$RUN python3 - <<EOF
import time
from osgeo import gdal
gdal.UseExceptions()
dsn = 'ZARR:"/vsicurl/$URL":/sla'
t0 = time.time(); ds = gdal.Open(dsn); n = ds.RasterCount
print("default delay: open %.2fs (%d bands)" % (time.time() - t0, n))
ds = None
gdal.SetConfigOption("GDAL_LOAD_EXTRA_DIM_METADATA_DELAY", "0")
t0 = time.time(); ds = gdal.Open(dsn); n = ds.RasterCount
print("DELAY=0:       open %.2fs (%d bands)" % (time.time() - t0, n))
EOF

echo "==================================================================="
echo "P5: HTTP request ACCOUNTING -- how many GETs does each path issue"
echo "    for one day? mdim should be ~12 + metadata; if classic/vrt is"
echo "    far above that, the driver is over-fetching (upstream material)"
echo "==================================================================="
echo "--- P5a mdim slice:"
CPL_DEBUG=ON $RUN python3 - 2>&1 <<EOF | grep -ci "downloading\|range"
from osgeo import gdal, gdal_array
gdal.UseExceptions()
ds = gdal.OpenEx('ZARR:"/vsicurl/$URL"', gdal.OF_MULTIDIM_RASTER)
v = ds.GetRootGroup().OpenMDArray("sla")[1779].ReadAsArray()
EOF
echo "--- P5b vrt band-slice, full day via warp path (DELAY=0, 256MB cache):"
CPL_DEBUG=ON GDAL_LOAD_EXTRA_DIM_METADATA_DELAY=0 GDAL_CACHEMAX=256 \
$RUN Rscript - 2>&1 <<EOF | grep -ci "downloading\|range"
library(grist)
vdsn <- 'vrt://ZARR:"/vsicurl/$URL":/sla?bands=1780'
grid <- list(dimension = c(2880L, 1440L), extent = c(-180, 180, -90, 90))
v1 <- read_rows(vdsn, 1:720, grid)
v2 <- read_rows(vdsn, 721:1440, grid)
EOF

echo "==================================================================="
echo "P6: the engine's exact per-date cost under the round-two knobs,"
echo "    timed, plus GDAL cache actually used (the OOM question)"
echo "==================================================================="
GDAL_LOAD_EXTRA_DIM_METADATA_DELAY=0 GDAL_CACHEMAX=256 GDAL_PAM_ENABLED=NO \
$RUN Rscript - <<EOF
library(grist)
vdsn <- 'vrt://ZARR:"/vsicurl/$URL":/sla?bands=1780'
grid <- list(dimension = c(2880L, 1440L), extent = c(-180, 180, -90, 90))
print(system.time({
  v1 <- read_rows(vdsn, 1:720, grid)
  v2 <- read_rows(vdsn, 721:1440, grid)
}))
cat("finite:", sum(is.finite(v1)) + sum(is.finite(v2)), "\n")
cat("GDAL cache used (MB):",
    vapour::vapour_get_config("GDAL_CACHEMAX"), "cap;",
    round(gc()[2, 2]), "MB R heap\n")
EOF

echo "==================================================================="
echo "done. interpretation guide:"
echo "  P1 slow (>2s/chunk)        -> CloudFerro or route is the story"
echo "  P2 ~= 1x P1                -> parallelism works, backfill scales"
echo "  P3 open >> read            -> per-date open dominates; batch dates"
echo "                                per open in an mdim read branch"
echo "  P4 default >> DELAY=0      -> every backfill read was paying band"
echo "                                labelling; config knob is mandatory"
echo "  P5b >> P5a                 -> classic/warp over-fetches; mdim"
echo "                                branch in grist + upstream note"
echo "  P6 ~30s and flat memory    -> round-two sbatch will hold"
echo "==================================================================="
