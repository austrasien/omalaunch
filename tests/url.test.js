const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const U = require(path.join(__dirname, "..", "plugins", "url", "Url.js"))

test("url: recognised", () => {
  assert.strictEqual(U.parse("  https://github.com/austrasien/omalaunch  "), "https://github.com/austrasien/omalaunch")
  assert.strictEqual(U.parse("github.com"), "https://github.com")
  assert.strictEqual(U.parse("www.example.zz"), "https://www.example.zz")
  assert.strictEqual(U.parse("news.ycombinator.com/item?id=1"), "https://news.ycombinator.com/item?id=1")
  assert.strictEqual(U.parse("example.zz/path"), "https://example.zz/path")
  assert.strictEqual(U.parse("localhost:3000"), "http://localhost:3000")
  assert.strictEqual(U.parse("192.168.1.1"), "http://192.168.1.1")
  assert.strictEqual(U.parse("file:///tmp/a.html"), "file:///tmp/a.html")
})

test("url: left as searches", () => {
  for (const q of ["firefox", "notes.md", "Main.qml", "2+2", "3.14", "1.5", "o 2026", "a.b c", "tleoutre@gmail.com", "ssh://host", "", "v0.1.7"])
    assert.strictEqual(U.parse(q), null, q)
})
