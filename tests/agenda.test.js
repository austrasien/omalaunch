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
