import QtQuick
import "Calc.js" as Calc
import "Currency.js" as Currency

// Inline calculator: arithmetic, currencies (ECB daily rates) and, when
// qalc is installed, units and anything else libqalculate understands.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Calculator"
  property string sectionTitle: "Calculator"
  property string placement: "inline"
  property int order: 0

  property var rates: ({})
  property string ratesDate: ""
  property double ratesFetchedAt: 0
  property bool fetching: false
  property bool qalc: false
  readonly property string ratesFile: host ? host.dataDir + "/rates.json" : ""
  readonly property int maxAgeMs: 12 * 3600 * 1000

  function start() {
    root.host.capture(["bash", "-c", "command -v qalc"], function(code) { root.qalc = code === 0 })
    root.host.capture(["cat", root.ratesFile], function(code, out) {
      if (code === 0) loadRates(out)
      refreshRates(false)
    })
  }

  function opened() { refreshRates(false) }

  function loadRates(text) {
    try {
      var data = JSON.parse(text)
      if (data && data.rates) {
        root.rates = data.rates
        root.ratesDate = String(data.date || "")
        root.ratesFetchedAt = Number(data.fetchedAt) || 0
      }
    } catch (e) {}
  }

  function refreshRates(force) {
    if (root.fetching || (!force && Date.now() - root.ratesFetchedAt < root.maxAgeMs)) return
    root.fetching = true
    var script = 'set -e; mkdir -p "$(dirname "$1")"; '
      + 'json=$(curl -fsS --max-time 10 "https://api.frankfurter.dev/v1/latest?base=EUR"); '
      + 'printf "%s" "$json" | sed "s/}\\s*$/,\\"fetchedAt\\":$2}/" > "$1.tmp" && mv "$1.tmp" "$1"; cat "$1"'
    root.host.capture(["bash", "-c", script, "bash", root.ratesFile, String(Date.now())], function(code, out) {
      root.fetching = false
      if (code === 0) loadRates(out)
    }, 15000)
  }

  function query(text, reply) {
    var q = String(text).trim()
    var rows = []

    var v = Calc.evaluate(q)
    if (v !== null) {
      var s = Calc.format(v)
      rows.push({ id: "math", title: Calc.pretty(s), subtitle: q + "  =", icon: "", type: "Calculator", copy: s })
    }

    if (!rows.length) {
      var c = Currency.parse(q, root.rates)
      if (c) {
        var targets = c.to ? [c.to] : (c.from === "EUR" ? ["USD", "GBP", "CHF"] : ["EUR", "USD"].filter(function(t) { return t !== c.from }))
        if (!Object.keys(root.rates).length) {
          rows.push({ id: "fx-pending", title: "Loading exchange rates…", subtitle: "ECB reference rates", icon: "", type: "Currency", copy: "" })
          refreshRates(true)
        }
        for (var i = 0; i < targets.length && Object.keys(root.rates).length; i++) {
          var out = Currency.convert(c.amount, c.from, targets[i], root.rates)
          if (isNaN(out)) continue
          rows.push({
            id: "fx-" + targets[i],
            title: Currency.formatMoney(out, targets[i]),
            subtitle: Currency.formatMoney(c.amount, c.from) + "  →  " + targets[i] + "   ·   ECB " + root.ratesDate,
            icon: "",
            type: "Currency",
            copy: out.toFixed(2)
          })
        }
      }
    }

    if (!rows.length && root.qalc && /\d/.test(q) && /[a-z°]/i.test(q) && q.length <= 80) {
      root.host.capture(["qalc", "-t", "-s", "update_exchange_rates 0", q], function(code, out, err) {
        var r = String(out || "").trim().split("\n").pop()
        if (code !== 0 || !r || /error|warning/i.test(r + err) || r.toLowerCase() === q.toLowerCase()) return
        reply([{ id: "qalc", title: r, subtitle: q + "  =", icon: "", type: "Calculator", copy: r.replace(/^≈\s*/, "") }])
      }, 3000)
    }
    return rows
  }

  function actions(row) {
    if (!row.copy) return [{ id: "refresh", title: "Refresh Exchange Rates" }]
    return [
      { id: "copy", title: "Copy Result" },
      { id: "copy-full", title: "Copy Expression and Result" },
      { id: "refresh", title: "Refresh Exchange Rates" }
    ]
  }

  function run(row, actionId) {
    if (actionId === "refresh") {
      refreshRates(true)
      return { close: false, toast: "Fetching exchange rates…" }
    }
    if (actionId === "copy-full") {
      root.host.copy(row.subtitle.replace(/\s+=\s*$/, "") + " = " + row.title)
      return { close: true }
    }
    root.host.copy(row.copy)
    root.host.notify("Copied", row.copy)
    return { close: true }
  }
}
