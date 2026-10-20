const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const K = require(path.join(__dirname, "..", "plugins", "web-keywords", "Keywords.js"))

test("web keywords: defaults and overrides", () => {
  const sites = K.merge({ gh: null, npm: "https://www.npmjs.com/search?q={query}", bad: { url: "https://x" }, _help: "text" })
  const kws = sites.map((s) => s.keyword)
  assert.ok(!kws.includes("gh") && kws.includes("npm") && kws.includes("yt"))
  assert.ok(!kws.includes("bad") && !kws.includes("_help"))
  assert.strictEqual(sites.find((s) => s.keyword === "npm").title, "npm")
})

test("web keywords: matching and urls", () => {
  const sites = K.merge(null)
  const m = K.match("YT  lofi beats", sites)
  assert.strictEqual(m.site.keyword, "yt")
  assert.strictEqual(K.urlFor(m.site, m.terms), "https://www.youtube.com/results?search_query=lofi%20beats")
  assert.strictEqual(K.match("yt", sites), null)
  assert.strictEqual(K.match("yt ", sites).terms, "")
  assert.strictEqual(K.match("ytx foo", sites), null)
  assert.strictEqual(K.urlFor(sites.find((s) => s.keyword === "pcloud"), "devis"), "https://my.pcloud.com/#/filemanager?q=name%3Adevis&folderid=0&filter=all")
})
