const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const O = require(path.join(__dirname, "..", "plugins", "obsidian", "Obsidian.js"))
const now = new Date(2026, 9, 20, 17, 5)

test("obsidian: queries", () => {
  assert.deepStrictEqual(O.parse("o stoïcisme"), { mode: "search", text: "stoïcisme" })
  assert.deepStrictEqual(O.parse("o"), { mode: "search", text: "" })
  assert.deepStrictEqual(O.parse("o+ appeler Luc"), { mode: "journal", text: "appeler Luc" })
  assert.deepStrictEqual(O.parse("on Idée produit"), { mode: "new", text: "Idée produit" })
  assert.strictEqual(O.parse("obsidian"), null)
  assert.strictEqual(O.parse("one"), null)
})

test("obsidian: vaults, dates, templates", () => {
  const v = O.vaults({ vaults: { a: { path: "/x/old" }, b: { path: "/x/main/", open: true } } })
  assert.deepStrictEqual(v.map((x) => x.name), ["main", "old"])
  assert.strictEqual(O.formatMoment(now, "YYYY-MM-DD"), "2026-10-20")
  assert.strictEqual(O.formatMoment(now, "dddd D MMMM [at] HH:mm"), "Tuesday 20 October at 17:05")
  assert.strictEqual(O.fillTemplate("# {{title}} {{date:DD/MM}} {{time}}", "T", now), "# T 20/10 17:05")
  assert.strictEqual(O.fileName('a/b: "c"?'), "a b c")
})

test("obsidian: insert in a section", () => {
  const doc = "## Notes\n- a\n\n## Links\nx\n"
  assert.strictEqual(O.insertLine(doc, "## Notes", "- b"), "## Notes\n- a\n- b\n\n## Links\nx\n")
  assert.strictEqual(O.insertLine("## Notes\n## Tasks\n", "## Notes", "- b"), "## Notes\n- b\n## Tasks\n")
  assert.strictEqual(O.insertLine("# T\ntext", "## Notes", "- b"), "# T\ntext\n- b\n")
  assert.strictEqual(O.insertLine("", "## Notes", "- b"), "- b\n")
  assert.strictEqual(O.insertLine("## Notes\n### sub\ny\n## Next", "## Notes", "- b"), "## Notes\n### sub\ny\n- b\n## Next")
})
