const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const E = require(path.join(__dirname, "..", "plugins", "emojis", "Emoji.js"))
const items = E.prepare(require(path.join(__dirname, "..", "plugins", "emojis", "emojis.json")))
const first = (q) => E.search(items, E.termsFrom(q), 5)[0].e

test("emojis: prefix and folding", () => {
  assert.deepStrictEqual(E.termsFrom(":Cœur  rouge"), ["coeur", "rouge"])
  assert.deepStrictEqual(E.termsFrom(":"), [])
  assert.strictEqual(E.termsFrom("feu"), null)
})

test("emojis: French and English names", () => {
  assert.strictEqual(first(":feu"), "🔥")
  assert.strictEqual(first(":fire"), "🔥")
  assert.strictEqual(first(":coeur rouge"), "❤️")
  assert.strictEqual(first(":drapeau france"), "🇫🇷")
  assert.ok(E.search(items, ["pouce"], 5).some((x) => x.e === "👍"))
})
