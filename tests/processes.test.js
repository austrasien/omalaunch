const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const P = require(path.join(__dirname, "..", "plugins", "processes", "Processes.js"))

test("processes: prefix", () => {
  assert.deepStrictEqual(P.termsFrom("kill Brave"), ["brave"])
  assert.deepStrictEqual(P.termsFrom("tuer"), [])
  assert.strictEqual(P.termsFrom("killer"), null)
})

test("processes: grouping", () => {
  const ps = "  10 brave 2.0 500000 /opt/brave --type=renderer\n  11 brave 1.0 300000 /opt/brave\n  12 quickshell 3.0 800000 /usr/bin/quickshell\n  13 zoom 9.5 100 /opt/zoom\n  99 ps 0 1 ps"
  const g = P.groups(P.parsePs(ps, 99), [])
  assert.deepStrictEqual(g.map((x) => [x.comm, x.pids.length, x.protected]), [["brave", 2, false], ["quickshell", 1, true], ["zoom", 1, false]])
  assert.strictEqual(g[0].rss, 800000)
  assert.deepStrictEqual(P.groups(P.parsePs(ps, 99), ["renderer"]).map((x) => x.comm), ["brave"])
  assert.strictEqual(P.memory(800000), "781 MB")
  assert.strictEqual(P.memory(3 * 1048576), "3.0 GB")
})
