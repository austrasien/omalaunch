const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const A = require(path.join(__dirname, "..", "plugins", "agenda", "Agenda.js"))
const now = new Date(2026, 9, 20, 10, 0)

test("agenda: queries", () => {
  assert.deepStrictEqual(A.parse("agenda"), { filter: "", day: "" })
  assert.deepStrictEqual(A.parse("rdv demain"), { filter: "", day: "tomorrow" })
  assert.deepStrictEqual(A.parse("cal Airbus"), { filter: "airbus", day: "" })
  assert.strictEqual(A.parse("calculer"), null)
})

test("agenda: labels and next", () => {
  assert.strictEqual(A.dayLabel(new Date(2026, 9, 20, 15), now), "aujourd'hui")
  assert.strictEqual(A.dayLabel(new Date(2026, 9, 21, 9), now), "demain")
  assert.strictEqual(A.dayLabel(new Date(2026, 9, 22, 9), now), "jeudi 22 oct.")
  assert.strictEqual(A.relative(new Date(2026, 9, 20, 10, 25), new Date(2026, 9, 20, 11), now), "dans 25 min")
  assert.strictEqual(A.relative(new Date(2026, 9, 20, 9, 30), new Date(2026, 9, 20, 10, 30), now), "en cours")
  const evs = [
    { title: "Salon", allDay: true, start: "2026-10-20T00:00:00+02:00", end: "2026-10-21T00:00:00+02:00" },
    { title: "Fini", allDay: false, start: "2026-10-20T08:00:00+02:00", end: "2026-10-20T09:00:00+02:00" },
    { title: "Point", allDay: false, start: "2026-10-20T11:00:00+02:00", end: "2026-10-20T11:30:00+02:00" }
  ]
  assert.strictEqual(A.next(evs, new Date("2026-10-20T10:00:00+02:00")).title, "Point")
})

test("agenda: spans", () => {
  const d = (day, h, m) => new Date(2026, 9, day, h, m || 0)
  assert.strictEqual(A.span(d(29, 11), d(29, 11, 45), false), "11:00–11:45")
  assert.strictEqual(A.span(d(29, 22), d(30, 0), false), "22:00–00:00")
  assert.strictEqual(A.span(d(28, 11, 39), d(29, 16, 19), false), "mer. 11:39 → jeu. 16:19")
  assert.strictEqual(A.span(d(28, 9), d(5 + 31, 18), false), "mer. 28 oct. 09:00 → jeu. 5 nov. 18:00")
  assert.strictEqual(A.span(d(29, 0), d(30, 0), true), "Toute la journée")
  assert.strictEqual(A.span(d(29, 0), d(1 + 31, 0), true), "Jusqu'au sam. 31 oct.")
  assert.strictEqual(A.multiDay(d(29, 22), d(30, 0)), false)
  assert.strictEqual(A.multiDay(d(28, 11), d(29, 9)), true)
})
