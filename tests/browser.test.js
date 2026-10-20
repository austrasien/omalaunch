const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const B = require(path.join(__dirname, "..", "plugins", "browser", "Browser.js"))

test("browser: bookmarks tree", () => {
  const json = { roots: { bookmark_bar: { type: "folder", name: "Bar", children: [
    { type: "url", name: "Plane", url: "https://app.plane.so" },
    { type: "folder", name: "Askalon", children: [{ type: "url", name: "Drive", url: "https://drive.google.com" }, { type: "url", name: "x", url: "javascript:void(0)" }] }
  ] }, other: { type: "folder", name: "Other", children: [] }, sync_transaction_version: "1" } }
  assert.deepStrictEqual(B.bookmarks(json).map((b) => b.title + "|" + b.folder), ["Plane|Bar", "Drive|Bar › Askalon"])
})

test("browser: prefix, sql, dates", () => {
  assert.deepStrictEqual(B.termsFrom("b Plane tickets"), ["plane", "tickets"])
  assert.strictEqual(B.termsFrom("brave"), null)
  const sql = B.historySql(["l'été", "50%"], 5)
  assert.ok(sql.includes("'%l''été%'") && sql.includes("50\\%") && sql.endsWith("LIMIT 5"))
  assert.strictEqual(B.chromeDate("13436986542515000").getUTCFullYear(), 2026)
  assert.strictEqual(B.host("https://www.reddit.com/r/x"), "reddit.com")
})
