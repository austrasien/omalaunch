const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const Calc = require(path.join(__dirname, "..", "plugins", "calculator", "Calc.js"))
const Currency = require(path.join(__dirname, "..", "plugins", "calculator", "Currency.js"))

const ev = (s) => Calc.evaluate(s)

test("basic arithmetic and precedence", () => {
  assert.strictEqual(ev("2+3*4"), 14)
  assert.strictEqual(ev("(2+3)*4"), 20)
  assert.strictEqual(ev("2^3^2"), 512)
  assert.strictEqual(ev("-2^2"), -4)
  assert.strictEqual(ev("10/4"), 2.5)
  assert.strictEqual(ev("7 mod 3"), 1)
})

test("symbols, comma decimals, x as times", () => {
  assert.strictEqual(ev("3,5*2"), 7)
  assert.strictEqual(ev("6 × 7"), 42)
  assert.strictEqual(ev("8÷2"), 4)
  assert.strictEqual(ev("3x4"), 12)
})

test("functions, constants, implicit multiplication", () => {
  assert.strictEqual(ev("sqrt(16)+1"), 5)
  assert.ok(Math.abs(ev("2pi") - 2 * Math.PI) < 1e-12)
  assert.strictEqual(ev("2(3+1)"), 8)
  assert.strictEqual(ev("max(1; 5; 3)+0"), 5)
  assert.strictEqual(ev("5!"), 120)
  assert.strictEqual(ev("50%*80"), 40)
})

test("quiet on non-math", () => {
  for (const s of ["2026", "firefox", "lock", "", "10 usd", "hello+world", "1/0"]) assert.strictEqual(ev(s), null, s)
})

test("format avoids float noise", () => {
  assert.strictEqual(Calc.format(0.1 + 0.2), "0.3")
  assert.strictEqual(Calc.format(1 / 3), "0.333333333333")
  assert.strictEqual(Calc.pretty("1234567.5"), "1 234 567.5")
})

const rates = { USD: 1.1225, GBP: 0.84205, JPY: 177.63, CHF: 0.9261 }

test("currency parsing", () => {
  assert.deepStrictEqual(Currency.parse("100 usd to eur", rates), { amount: 100, from: "USD", to: "EUR" })
  assert.deepStrictEqual(Currency.parse("100$ en €", rates), { amount: 100, from: "USD", to: "EUR" })
  assert.deepStrictEqual(Currency.parse("€50 in gbp", rates), { amount: 50, from: "EUR", to: "GBP" })
  assert.deepStrictEqual(Currency.parse("1,5k chf", rates), { amount: 1500, from: "CHF", to: "" })
  assert.deepStrictEqual(Currency.parse("100 dollars en euros", rates), { amount: 100, from: "USD", to: "EUR" })
  assert.strictEqual(Currency.parse("100 km", rates), null)
  assert.strictEqual(Currency.parse("100 usd to xyz", rates), null)
  assert.strictEqual(Currency.parse("firefox", rates), null)
})

test("currency conversion and formatting", () => {
  assert.ok(Math.abs(Currency.convert(112.25, "USD", "EUR", rates) - 100) < 1e-9)
  assert.ok(Math.abs(Currency.convert(100, "EUR", "JPY", rates) - 17763) < 1e-6)
  assert.strictEqual(Currency.formatMoney(1234.5, "EUR"), "1 234,50 EUR")
})
