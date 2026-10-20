const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const Files = require(path.join(__dirname, "..", "plugins", "files", "Files.js"))

test("files: prefix", () => {
  assert.deepStrictEqual(Files.termsFrom("'Foo bar"), ["foo", "bar"])
  assert.deepStrictEqual(Files.termsFrom("find  notes "), ["notes"])
  assert.strictEqual(Files.termsFrom("finder"), null)
  assert.strictEqual(Files.termsFrom("'"), null)
})

test("files: ranking", () => {
  const paths = [
    "/h/a/deep/x/notes-old.md",
    "/h/notes/",
    "/h/b/mynotes.txt",
    "/h/notes.md",
    "/h/c/other.txt"
  ]
  assert.deepStrictEqual(Files.rank(paths, ["notes"]), ["/h/notes/", "/h/notes.md", "/h/a/deep/x/notes-old.md", "/h/b/mynotes.txt"])
  assert.deepStrictEqual(Files.rank(paths, ["notes", "deep"]), ["/h/a/deep/x/notes-old.md"])
})

test("files: recently-used.xbel", () => {
  const xml = `<xbel>
  <bookmark href="file:///h/a%20b.pdf" added="2026-01-01T00:00:00Z" modified="2026-02-01T00:00:00Z" visited="x"></bookmark>
  <bookmark href="https://example.com" modified="2026-03-01T00:00:00Z"></bookmark>
  <bookmark href="file:///h/c&amp;d.txt" modified="2026-03-01T00:00:00Z"></bookmark>
</xbel>`
  assert.deepStrictEqual(Files.parseRecent(xml).map((r) => r.path), ["/h/c&d.txt", "/h/a b.pdf"])
  assert.strictEqual(Files.tilde("/home/u/x", "/home/u"), "~/x")
})

test("files: search filters", () => {
  const filters = Files.normalizeFilters([
    { keyword: "PDF", title: "PDFs", extensions: [".pdf"] },
    { keyword: "pdf", title: "duplicate" },
    { keyword: "two words" },
    { keyword: "proj", title: "Projects", type: "folder", folders: ["~/src"], hidden: true }
  ])
  assert.deepStrictEqual(filters.map((f) => [f.keyword, f.type, f.extensions.join(",")]), [["pdf", "file", "pdf"], ["proj", "folder", ""]])
  assert.strictEqual(Files.filterFor("pdf", filters), null)
  assert.deepStrictEqual(Files.filterFor("pdf ", filters).words, [])
  assert.deepStrictEqual(Files.filterFor("Pdf facture 2026", filters).words, ["facture", "2026"])
  assert.strictEqual(Files.filterFor("pdfs x", filters), null)
  assert.deepStrictEqual(Files.fdArgs(filters[1], ["omal"], "/home/u"), ["-i", "-F", "--absolute-path", "-H", "-t", "d", "--", "omal", "/home/u/src"])
})
