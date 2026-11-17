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
    rotate: [155, 10]
  }
};
