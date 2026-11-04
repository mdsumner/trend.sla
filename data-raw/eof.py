#!/usr/bin/env python3
"""data-raw/eof.py -- empirical orthogonal functions (EOFs) of monthly SLA.

  python3 data-raw/eof.py [data_dir] [n_modes]

Reads the site's own exports in data_dir (default docs/data):
  cells-sla-cmems.json   cell order, lon/lat, month labels
  monthly-sla-cmems.bin  Float32 cell x month means (mm), cell-major
  status.json            last date, to drop a partial final month
and writes data_dir/eof-sla-cmems.json for docs/modes.html.

The monthly means are exact projections of the grist sums (ratio of
summed sumwx to summed sumw per cell and month), so this is EOF analysis
of the published record with nothing re-read from the source.

Method, all per cell:
  1. drop the partial final month (status.json last date not a month end)
  2. mask inland water that is in the product grid but is not ocean
     (the Caspian Sea, see MASKS below)
  3. remove mean, linear trend and the mean seasonal cycle (12 monthly
     offsets), fitted jointly by least squares
  4. SVD of the month x cell anomaly matrix, cells equally weighted (S2
     level-5 cells are roughly equal area)
Each mode is reported as a pattern in mm per standard deviation of its
principal component (PC), and the PC in standard units, so pattern * PC
is the mode's contribution in mm. Sign convention: mode 1 is positive
where the Nino 3.4 box loads; other modes are positive at their largest
loading.
"""
import json
import os
import sys

import numpy as np

SRC = "sla-cmems"
## cells to exclude: (label, lat_min, lat_max, lon360_min, lon360_max).
## The Caspian is in the CMEMS grid; its level history (a ~1.5 m fall
## 1995-2021, then a ~1.2 m rise from 2022-09) dominated the first
## unmasked analysis as a mode of its own (12% of variance).
MASKS = [("Caspian Sea", 36.0, 48.0, 46.0, 56.0)]
NINO34 = (-5.0, 5.0, 190.0, 240.0)


def month_end(iso):
    y, m, d = (int(x) for x in iso.split("-"))
    nxt = (y + (m == 12), m % 12 + 1)
    import datetime as dt
    return (dt.date(*nxt, 1) - dt.timedelta(days=1)).day == d


def main():
    data = sys.argv[1] if len(sys.argv) > 1 else "docs/data"
    k = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    meta = json.load(open(os.path.join(data, "cells-%s.json" % SRC)))
    status = json.load(open(os.path.join(data, "status.json")))
    cells = meta["cells"]
    months = list(meta["months"])
    m = np.fromfile(os.path.join(data, "monthly-%s.bin" % SRC), "<f4")
    m = m.reshape(len(cells), len(months)).astype(float)

    last = status["sources"][SRC]["last"]
    if months[-1] == last[:7] and not month_end(last):
        months = months[:-1]
        m = m[:, :len(months)]

    lat = np.array([c["lat"] for c in cells])
    lon = (np.array([c["lon"] for c in cells]) + 360.0) % 360.0
    keep = np.isfinite(m).all(axis=1)
    masked = []
    for label, a0, a1, o0, o1 in MASKS:
        s = (lat > a0) & (lat < a1) & (lon > o0) & (lon < o1)
        masked.append({"label": label, "cells": int(s.sum())})
        keep &= ~s
    X = m[keep].T                                 # month x cell, mm

    nt = len(months)
    t = np.arange(nt) / nt
    moy = np.array([int(s[5:]) - 1 for s in months])
    A = np.column_stack([np.ones(nt), t] +
                        [(moy == j).astype(float) for j in range(1, 12)])
    beta = np.linalg.lstsq(A, X, rcond=None)[0]
    R = X - A @ beta

    U, S, Vt = np.linalg.svd(R, full_matrices=False)
    var = S ** 2 / np.sum(S ** 2)
    la, lo = lat[keep], lon[keep]
    a0, a1, o0, o1 = NINO34
    box = (la >= a0) & (la <= a1) & (lo >= o0) & (lo <= o1)
    n34 = R[:, box].mean(axis=1)

    modes = []
    for j in range(k):
        pc = U[:, j] * S[j]
        sd = pc.std()
        pat = Vt[j] * sd                          # mm per PC standard deviation
        sign = np.sign(pat[box].mean()) if j == 0 else np.sign(pat[np.argmax(np.abs(pat))])
        sign = sign or 1.0
        pc, pat = pc * sign / sd, pat * sign
        full = [None] * len(cells)
        for i, v in zip(np.flatnonzero(keep), pat):
            full[i] = round(float(v), 2)
        modes.append({
            "mode": j + 1,
            "variance": round(float(var[j]), 4),
            "r_nino34_box": round(float(np.corrcoef(pc, n34)[0, 1]), 3),
            "pc": [round(float(v), 3) for v in pc],
            "pattern_mm": full,
        })
        print("mode %i: %.1f%% of variance, r with Nino 3.4 box SLA %.2f"
              % (j + 1, 100 * var[j], modes[-1]["r_nino34_box"]))

    out = {
        "source": SRC,
        "months": months,
        "cells_used": int(keep.sum()),
        "masked": masked,
        "method": ("per-cell mean, linear trend and mean seasonal cycle removed; "
                   "SVD of month x cell anomalies, cells equally weighted"),
        "variance_first10": [round(float(v), 4) for v in var[:10]],
        "modes": modes,
    }
    path = os.path.join(data, "eof-%s.json" % SRC)
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("wrote %s: %i modes, %i months x %i cells"
          % (path, k, nt, int(keep.sum())))


if __name__ == "__main__":
    main()
