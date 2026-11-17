// trend.sla site config, read by the shared kit (kit/, synced from
// AustralianAntarcticDivision/trend with tools/kit-sync). Units, metric
// scales and code-generator text for each record are in kit/records.js.
window.TREND_SITE = {
  record: "sla",
  title: "trend.sla",
  repo: "https://github.com/mdsumner/trend.sla",
  tabs: [["index.html", "Explorer"], ["status.html", "Status"],
         ["method.html", "Method"], ["modes.html", "Modes"],
         ["mechanics.html", "Mechanics"]],
  explorer: {
    sources: ["sla-cmems"],
    family: [],
    view: "world",           // Equal Earth; every view is in the menu
    rotate: [155, 10],       // Equal Earth and globe centred on 155W
    // transverse Mercator on 115E (+proj=tmerc +lon_0=115), its own
    // meridian, framed on both polar caps: the poles lie on the central
    // meridian, so one map runs pole to pole through the Indian Ocean and
    // the western Pacific, as trend.ice's sea ice view
    tmerc: { frame: "both", radius: 50, lon0: 115 }
  }
};
