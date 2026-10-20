const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const S = require(path.join(__dirname, "..", "plugins", "snippets", "Snippets.js"))
const now = new Date(2026, 9, 20, 17, 5, 9) // mardi 20 octobre 2026, 17:05:09
const fixed = () => 0.5

test("snippets: dates", () => {
  const x = (t) => S.expand(t, { now, rand: fixed }).text
  assert.strictEqual(x("{date}"), "2026-10-20")
  assert.strictEqual(x("{date:DD/MM/YYYY}"), "20/10/2026")
  assert.strictEqual(x("{date:dddd D MMMM}"), "mardi 20 octobre")
  assert.strictEqual(x("{date+3d:dddd}"), "vendredi")
  assert.strictEqual(x("{date-1w}"), "2026-10-13")
  assert.strictEqual(x("{date+1m:MMMM YYYY}"), "novembre 2026")
  assert.strictEqual(x("{time} {datetime}"), "17:05 2026-10-20 17:05")
  assert.strictEqual(x("{weekday} S{week}"), "mardi S43")
  assert.strictEqual(x("{date:[le] D}"), "le 20")
})

test("snippets: values, inputs, cursor, unknown", () => {
  const r = S.expand("Bonjour {input:Nom},{cursor}\n{fullname} <{email}>", { now, values: { fullname: "T L", email: "t@x" }, inputs: { Nom: "Luc" } })
  assert.strictEqual(r.text, "Bonjour Luc,\nT L <t@x>")
  assert.strictEqual(r.cursor, 10)
  assert.strictEqual(S.expand("{nope}", { now }).text, "{nope}")
  assert.strictEqual(S.expand("{random:6}", { now, rand: fixed }).text.length, 6)
  assert.match(S.expand("{uuid}", { now }).text, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
})

test("snippets: needs, inline, names", () => {
  assert.deepStrictEqual(S.needs("{clipboard} {input:A} {input:A} {shell:date} {snippet:sig} {date}"),
    { values: ["clipboard"], inputs: ["A"], commands: ["date"], snippets: ["sig"] })
  assert.strictEqual(S.inline("x {snippet:a}", { a: "[{snippet:b}]", b: "B" }), "x [B]")
  assert.strictEqual(S.inline("{snippet:a}", { a: "{snippet:a}" }), "{snippet:a}")
  assert.strictEqual(S.nameFrom(";Sig"), "sig")
  assert.strictEqual(S.nameFrom(";"), "")
  assert.strictEqual(S.nameFrom("; x"), null)
  assert.strictEqual(S.nameFrom("sig"), null)
})
