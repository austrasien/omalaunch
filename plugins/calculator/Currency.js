// Currency conversion for the calculator plugin. Rates are the ECB daily
// reference rates (via frankfurter.dev), quoted against EUR.
//
// Understands: "100 usd", "100 usd to eur", "100$ en €", "€50 in gbp",
// "1,5k chf to jpy", "100 dollars en euros".

var SYMBOLS = { "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY", "₪": "ILS", "₱": "PHP", "฿": "THB", "zł": "PLN", "kr": "SEK" }
var NAMES = {
  euro: "EUR", euros: "EUR", eur: "EUR",
  dollar: "USD", dollars: "USD", usd: "USD", "us$": "USD",
  pound: "GBP", pounds: "GBP", livre: "GBP", livres: "GBP", sterling: "GBP",
  yen: "JPY", yens: "JPY", franc: "CHF", francs: "CHF", "franc suisse": "CHF", "francs suisses": "CHF",
  yuan: "CNY", renminbi: "CNY", roupie: "INR", roupies: "INR", rupee: "INR", rupees: "INR",
  "dollar canadien": "CAD", "dollars canadiens": "CAD", "dollar australien": "AUD", "dollars australiens": "AUD"
}
var CONNECTORS = "to|in|en|vers|->|=>|=|→|into"

function codeFor(token, rates) {
  if (!token) return ""
  var t = String(token).trim().toLowerCase()
  if (SYMBOLS[t]) return SYMBOLS[t]
  if (NAMES[t]) return NAMES[t]
  var up = t.toUpperCase()
  if (up.length === 3 && (up === "EUR" || (rates && rates[up] !== undefined))) return up
  return ""
}

function parseAmount(s) {
  var m = /^([\d\s.,]*\d)\s*([kKmM])?$/.exec(String(s).trim())
  if (!m) return NaN
  var n = m[1].replace(/\s/g, "")
  // "1.234,5" or "1,5" → comma is the decimal mark; "1,234.5" → comma groups.
  if (n.indexOf(",") >= 0 && n.indexOf(".") >= 0) {
    n = n.lastIndexOf(",") > n.lastIndexOf(".") ? n.replace(/\./g, "").replace(",", ".") : n.replace(/,/g, "")
  } else if (n.indexOf(",") >= 0) {
    n = /,\d{3}$/.test(n) && n.split(",").length > 2 ? n.replace(/,/g, "") : n.replace(",", ".")
  }
  var v = parseFloat(n)
  if (m[2]) v *= m[2].toLowerCase() === "k" ? 1e3 : 1e6
  return v
}

// Returns { amount, from, to } or null. `to` may be "" (caller picks).
function parse(text, rates) {
  var s = String(text || "").trim().replace(/\s+/g, " ")
  if (!s || s.length > 60) return null
  var cur = "([a-zA-Z€$£¥₹₩₺₪₱฿]{1,3}|[a-zA-Z]+(?: [a-zA-Z]+)?)"
  var re1 = new RegExp("^([\\d\\s.,]*\\d\\s*[kKmM]?)\\s*" + cur + "(?:\\s*(?:" + CONNECTORS + ")\\s*" + cur + ")?$", "i")
  var re2 = new RegExp("^([€$£¥₹₩₺₪₱฿])\\s*([\\d\\s.,]*\\d\\s*[kKmM]?)(?:\\s*(?:" + CONNECTORS + ")\\s*" + cur + ")?$", "i")
  var amount, from, to
  var m = re1.exec(s)
  if (m) {
    amount = parseAmount(m[1]); from = codeFor(m[2], rates); to = codeFor(m[3], rates)
    if (m[3] && !to) return null
  } else {
    m = re2.exec(s)
    if (!m) return null
    amount = parseAmount(m[2]); from = codeFor(m[1], rates); to = codeFor(m[3], rates)
    if (m[3] && !to) return null
  }
  if (!from || isNaN(amount)) return null
  return { amount: amount, from: from, to: to }
}

// rates: { USD: 1.12, ... } against EUR.
function convert(amount, from, to, rates) {
  function perEur(code) { return code === "EUR" ? 1 : rates[code] }
  var a = perEur(from), b = perEur(to)
  if (a === undefined || b === undefined) return NaN
  return amount / a * b
}

function formatMoney(v, code) {
  var digits = Math.abs(v) >= 100 ? 2 : (Math.abs(v) >= 1 ? 2 : 4)
  var s = v.toFixed(digits)
  var parts = s.split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return parts.join(",") + " " + code
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse, convert: convert, formatMoney: formatMoney, parseAmount: parseAmount, codeFor: codeFor }
}
