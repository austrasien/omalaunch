const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const core = (name) => require(path.join(__dirname, "..", "plugin", "core", name + ".js"))
const Rank = core("Rank")
const State = core("State")
const Menu = core("Menu")
const Scripts = core("Scripts")
const Sections = core("Sections")

const titles = (ranked) => ranked.map((x) => x.row.title)

test("normalize strips accents and case", () => {
  assert.strictEqual(Rank.normalize("  Écran  Verrouillé "), "ecran verrouille")
})

test("words split camelCase and punctuation", () => {
  assert.deepStrictEqual(Rank.words("VisualStudio-Code v2"), ["visual", "studio", "code", "v", "2"])
})

test("exact beats prefix beats word start beats substring", () => {
  const rows = [
    { key: "a", title: "Firefox Nightly" },
    { key: "b", title: "Fire" },
    { key: "c", title: "Campfire" },
    { key: "d", title: "Open Fire Dialog" },
  ]
  assert.deepStrictEqual(titles(Rank.rank(rows, "fire")), ["Fire", "Firefox Nightly", "Open Fire Dialog", "Campfire"])
})

test("initials match", () => {
  const rows = [{ key: "a", title: "Visual Studio Code" }, { key: "b", title: "Vim" }]
  assert.strictEqual(Rank.rank(rows, "vsc")[0].row.title, "Visual Studio Code")
})

test("fuzzy keeps word-start subsequences and drops scattered ones", () => {
  assert.ok(Rank.fuzzy("scrrec", "screen recording") > 0)
  assert.strictEqual(Rank.fuzzy("xyz", "screen"), -1)
  assert.strictEqual(Rank.fuzzy("eeee", "reference tree"), -1)
})

test("alias wins outright", () => {
  const rows = [{ key: "a", title: "ff" }, { key: "b", title: "Firefox", alias: "ff" }]
  assert.strictEqual(Rank.rank(rows, "ff")[0].row.title, "Firefox")
})

test("learned term lifts a weaker match", () => {
  const rows = [{ key: "a", title: "Telegram" }, { key: "b", title: "Terminal", terms: ["te"] }]
  assert.strictEqual(Rank.rank(rows, "te")[0].row.title, "Terminal")
})

test("frecency breaks equal matches", () => {
  const rows = [{ key: "a", title: "Spotify" }, { key: "b", title: "Spotube", frecency: 5 }]
  assert.strictEqual(Rank.rank(rows, "spot")[0].row.title, "Spotube")
})

test("non-matching rows are dropped", () => {
  assert.strictEqual(Rank.rank([{ key: "a", title: "Calendar" }], "zzz").length, 0)
})

test("keywords match at reduced weight", () => {
  const rows = [{ key: "a", title: "Nautilus", keywords: ["files"] }, { key: "b", title: "Files" }]
  assert.deepStrictEqual(titles(Rank.rank(rows, "files")), ["Files", "Nautilus"])
})

test("frecency decays by half each week", () => {
  const s = State.empty()
  State.recordUse(s, "k", "", 0)
  State.recordUse(s, "k", "", 0)
  assert.strictEqual(State.frecency(s, "k", 0), 2)
  assert.ok(Math.abs(State.frecency(s, "k", State.HALF_LIFE_MS) - 1) < 1e-9)
})

test("terms are deduped and expire", () => {
  const s = State.empty()
  State.recordUse(s, "k", "Fi", 0)
  State.recordUse(s, "k", "fi", 10)
  assert.deepStrictEqual(State.terms(s, "k", 20), ["fi"])
  assert.deepStrictEqual(State.terms(s, "k", State.TERM_TTL_MS + 20), [])
})

test("picks count launches per query", () => {
  const s = State.empty()
  State.recordUse(s, "k", "ca", 0)
  State.recordUse(s, "k", "Ca", 10)
  State.recordUse(s, "k", "cal", 20)
  assert.deepStrictEqual(State.picks(s, "k", 30), { cal: 1, ca: 2 })
  assert.deepStrictEqual(State.picks(s, "k", State.TERM_TTL_MS + 25), {})
})

test("short queries put the most picked rows first", () => {
  const rows = [
    { key: "a", title: "Calculator", boost: 120 },
    { key: "b", title: "Google Calendar", picks: { ca: 1 } },
    { key: "c", title: "Capture", picks: { ca: 3 } },
    { key: "d", title: "Brave Origin", picks: { ca: 1 } }
  ]
  assert.deepStrictEqual(titles(Rank.rank(rows, "ca")), ["Capture", "Google Calendar", "Brave Origin", "Calculator"])
  // Longer queries keep the ordinary ranking.
  const long = [{ key: "a", title: "Calendar" }, { key: "b", title: "Calendar Sync Tool", picks: { calen: 5 } }]
  assert.strictEqual(Rank.rank(long, "calen")[0].row.title, "Calendar")
})

test("favorites toggle and reorder", () => {
  const s = State.empty()
  State.toggleFavorite(s, "a"); State.toggleFavorite(s, "b"); State.toggleFavorite(s, "c")
  assert.ok(State.moveFavorite(s, "c", -1))
  assert.deepStrictEqual(s.favorites, ["a", "c", "b"])
  assert.ok(!State.moveFavorite(s, "a", -1))
  State.toggleFavorite(s, "c")
  assert.deepStrictEqual(s.favorites, ["a", "b"])
})

test("disabling removes a favorite", () => {
  const s = State.empty()
  State.toggleFavorite(s, "a")
  State.setDisabled(s, "a", true)
  assert.deepStrictEqual(s.favorites, [])
  assert.ok(s.disabled.a)
})

test("upgrade keeps valid fields and fills the rest", () => {
  const s = State.upgrade({ favorites: ["x"], zoom: "big", history: "nope" })
  assert.deepStrictEqual(s.favorites, ["x"])
  assert.strictEqual(s.zoom, 1)
  assert.deepStrictEqual(s.history, [])
})

test("history is newest first and unique", () => {
  const s = State.empty()
  State.pushHistory(s, "a"); State.pushHistory(s, "b"); State.pushHistory(s, "a")
  assert.deepStrictEqual(s.history, ["a", "b"])
})

test("jsonc stripping keeps // inside strings", () => {
  const raw = '{\n // c\n "a": {"label":"A","action":"xdg-open https://x.y/z", /* b */ },\n}'
  const parsed = Menu.parseFile(raw)
  assert.strictEqual(parsed.error, "")
  assert.strictEqual(parsed.entries.a.action, "xdg-open https://x.y/z")
})

test("menu merge overrides by field and infers kind and parent", () => {
  const base = Menu.parseFile('{"s":{"label":"Setup"},"s.x":{"label":"X","action":"a"},"s.l":{"label":"L","target":"s"}}').entries
  const user = Menu.parseFile('{"s.x":{"label":"Ex"}}').entries
  const m = Menu.merge([base, user])
  assert.strictEqual(m["s.x"].label, "Ex")
  assert.strictEqual(m["s.x"].action, "a")
  assert.strictEqual(m["s.x"].kind, "action")
  assert.strictEqual(m["s.l"].kind, "link")
  assert.strictEqual(m.s.kind, "menu")
  assert.strictEqual(m["s.x"].parent, "s")
  assert.deepStrictEqual(Menu.trail(m, "s.x"), ["Setup"])
  assert.deepStrictEqual(Menu.children(m, "s").map((e) => e.id), ["s.x", "s.l"])
})

test("failed when hides the subtree", () => {
  const m = Menu.merge([Menu.parseFile('{"a":{"label":"A","when":"false"},"a.b":{"label":"B","action":"x"},"c":{"label":"C"}}').entries])
  assert.deepStrictEqual(Menu.hiddenIds(m, { a: false }), { a: true, "a.b": true })
})

test("guard output parsing", () => {
  assert.deepStrictEqual(Menu.parseGuardOutput("1\t0\n0\t1\n", 2), [true, false])
})

test("script header", () => {
  const h = Scripts.parseHeader("#!/bin/bash\n# @omalaunch.title Hello World\n# @omalaunch.mode toast\n// @omalaunch.argument name\necho hi")
  assert.deepStrictEqual(h, { title: "Hello World", mode: "toast", icon: "", description: "", argument: "name", keyword: "" })
  assert.strictEqual(Scripts.parseHeader("echo nothing"), null)
  assert.strictEqual(Scripts.parseHeader("# @omalaunch.title T\n# @omalaunch.mode weird").mode, "silent")
})

test("script argument from query", () => {
  assert.strictEqual(Scripts.argumentFrom("hello world  bob ", "Hello World", ""), "bob")
  assert.strictEqual(Scripts.argumentFrom("hw bob", "Hello World", "hw"), "bob")
  assert.strictEqual(Scripts.argumentFrom("hello", "Hello World", ""), "")
})

test("script filters: keyword and header", () => {
  const h = Scripts.parseHeader("# @omalaunch.title Keys\n# @omalaunch.mode filter\n# @omalaunch.keyword keys extra")
  assert.strictEqual(h.mode, "filter")
  assert.strictEqual(h.keyword, "keys")
  assert.strictEqual(Scripts.filterText("keys term", "keys"), "term")
  assert.strictEqual(Scripts.filterText("Keys", "keys"), "")
  assert.strictEqual(Scripts.filterText("keyswitch", "keys"), null)
  assert.strictEqual(Scripts.filterText("keys", ""), null)
})

test("script filters: output parsing", () => {
  assert.strictEqual(Scripts.parseFilterOutput("not json"), null)
  assert.strictEqual(Scripts.parseFilterOutput('{"other": 1}'), null)
  const rows = Scripts.parseFilterOutput('{"items":[{"title":"A","arg":"a","open":"https://x"},"B",{"subtitle":"no title"}]}')
  assert.deepStrictEqual(rows.map((r) => [r.title, r.arg, r.open, r.copy]), [["A", "a", "https://x", "a"], ["B", "B", "", "B"]])
  assert.strictEqual(Scripts.parseFilterOutput(JSON.stringify(Array.from({ length: 80 }, (_, i) => "x" + i))).length, 50)
})

const deps = { Rank, State }

test("root sections, empty query", () => {
  const s = State.empty()
  State.toggleFavorite(s, "app:b")
  State.recordUse(s, "cmd:x", "", 0)
  s.disabled["cmd:hidden"] = true
  const catalog = [
    { key: "app:a", title: "Alpha", group: "apps" },
    { key: "app:b", title: "Beta", group: "apps" },
    { key: "cmd:x", title: "X", group: "commands" },
    { key: "cmd:y", title: "Y", group: "commands" },
    { key: "cmd:deep", title: "Deep", group: "commands", visibility: "search-only" },
    { key: "cmd:hidden", title: "Hidden", group: "commands" },
  ]
  const out = Sections.rootSections(catalog, [], "", s, 0, deps)
  assert.deepStrictEqual(out.map((x) => [x.id, x.rows.map((r) => r.key)]), [
    ["favorites", ["app:b"]],
    ["suggestions", ["cmd:x"]],
    ["commands", ["cmd:y"]],
    ["apps", ["app:a"]],
  ])
})

test("root sections, query with inline and bottom", () => {
  const s = State.empty()
  const catalog = [{ key: "cmd:deep", title: "Deep", group: "commands", visibility: "search-only" }, { key: "e", title: "Empty only", visibility: "idle-only" }]
  const dynamic = [
    { id: "web", title: "Web", placement: "bottom", order: 9, rows: [{ key: "web:g", title: "Google" }] },
    { id: "calc", title: "Calculator", placement: "inline", order: 0, rows: [{ key: "calc:r", title: "4" }] },
    { id: "none", title: "None", placement: "bottom", order: 1, rows: [] },
  ]
  const out = Sections.rootSections(catalog, dynamic, "de", s, 0, deps)
  assert.deepStrictEqual(out.map((x) => x.id), ["calc", "results", "web"])
  assert.deepStrictEqual(Sections.rootSections(catalog, dynamic, "empty", s, 0, deps).map((x) => x.id), ["calc", "web"])
})

test("flatten numbers items across sections", () => {
  const flat = Sections.flatten([{ id: "a", title: "A", rows: [{ key: 1 }] }, { id: "b", title: "", rows: [{ key: 2 }, { key: 3 }] }])
  assert.deepStrictEqual(flat.map((f) => f.header ? "H" : f.ordinal), ["H", 0, 1, 2])
})

test("boost lifts apps over deep menu entries", () => {
  const rows = [{ key: "a", title: "Brave", boost: -50 }, { key: "b", title: "Brave Origin", boost: 120 }]
  assert.strictEqual(Rank.rank(rows, "brave")[0].row.title, "Brave Origin")
})

test("keywords are not fuzzy-matched", () => {
  assert.strictEqual(Rank.rank([{ key: "a", title: "Pinta", keywords: ["edit images and screenshots"] }], "ecran").length, 0)
})

test("sections: neighbours with the same title merge", () => {
  const dynamic = [
    { id: "dyn:claude", title: "Search the web", placement: "bottom", order: 1001, rows: [{ key: "claude:ask", title: "Ask Claude" }] },
    { id: "dyn:web", title: "Search the web", placement: "bottom", order: 1000, rows: [{ key: "web:google", title: "Search Google" }, { key: "web:ddg", title: "Search DuckDuckGo" }] }
  ]
  const secs = Sections.rootSections([], dynamic, "drone", State.empty(), Date.now(), { Rank, State })
  assert.deepStrictEqual(secs.map((s) => [s.title, s.rows.map((r) => r.key)]), [["Search the web", ["web:google", "web:ddg", "claude:ask"]]])
})

test("rank handles titles that name Object.prototype members", () => {
  const rows = [{ key: "a", title: "constructor" }, { key: "b", title: "toString" }]
  assert.deepStrictEqual(titles(Rank.rank(rows, "con")), ["constructor"])
  assert.deepStrictEqual(titles(Rank.rank(rows, "tostring")), ["toString"])
})
