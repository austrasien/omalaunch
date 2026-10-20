const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const C = require(path.join(__dirname, "..", "plugins", "clock", "Clock.js"))
const now = new Date(2026, 9, 20, 17, 0)
const zones = ["Asia/Tokyo", "America/New_York", "Europe/Paris", "America/Argentina/Buenos_Aires"]

test("clock: places", () => {
  assert.strictEqual(C.zoneFor("Tokyo", zones), "Asia/Tokyo")
  assert.strictEqual(C.zoneFor("new york", zones), "America/New_York")
  assert.strictEqual(C.zoneFor("Genève", zones), "Europe/Zurich")
  assert.strictEqual(C.zoneFor("nowhere", zones), null)
})

test("clock: queries", () => {
  assert.deepStrictEqual(C.parse("heure à Tokyo", now), { kind: "zone", place: "tokyo" })
  assert.deepStrictEqual(C.parse("heure", now), { kind: "zone", place: "" })
  assert.deepStrictEqual(C.parse("15h30 paris en tokyo", now), { kind: "convert", h: 15, m: 30, from: "paris", to: "tokyo" })
  assert.deepStrictEqual(C.parse("3pm london to tokyo", now), { kind: "convert", h: 15, m: 0, from: "london", to: "tokyo" })
  assert.strictEqual(C.parse("dans 3 jours", now).date.getDate(), 23)
  assert.strictEqual(C.parse("in 2 weeks", now).date.getDate(), 3)
  assert.strictEqual(C.parse("il y a 1 mois", now).date.getMonth(), 8)
  assert.strictEqual(C.daysBetween(now, C.parse("jusqu'au 25/12", now).date), 66)
  assert.strictEqual(C.daysBetween(now, C.parse("1/1 - today", now).date), 73)
  assert.deepStrictEqual(C.parse("timer 25 café", now), { kind: "timer", minutes: 25, label: "café" })
  assert.deepStrictEqual(C.parse("minuteur 1h30 thé vert", now), { kind: "timer", minutes: 90, label: "thé vert" })
  assert.strictEqual(C.parse("bonjour", now), null)
  assert.strictEqual(C.frenchDate(now), "mardi 20 octobre 2026")
})
