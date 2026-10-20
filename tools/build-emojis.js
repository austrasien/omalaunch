#!/usr/bin/env node
// Builds plugins/emojis/emojis.json from Unicode data:
//   node tools/build-emojis.js DIR
// DIR holds emoji-test.txt (https://unicode.org/Public/emoji/latest/) and the
// CLDR annotations, ann-<lang>.json and der-<lang>.json for en and fr, from
// cldr-json (cldr-annotations-full, cldr-annotations-derived-full).
// Output: [{ e, en, fr, k, g }] — emoji, English and French names, extra
// keywords in both languages, group. Skin-tone variants are left out.

const fs = require("fs")
const path = require("path")

const dir = process.argv[2]
if (!dir) { console.error("usage: build-emojis.js DIR"); process.exit(1) }
const read = (f) => fs.readFileSync(path.join(dir, f), "utf8")

const names = {}
for (const lang of ["en", "fr"]) {
  const merged = {}
  for (const f of [`ann-${lang}.json`, `der-${lang}.json`]) {
    const data = JSON.parse(read(f))
    const a = (data.annotations || data.annotationsDerived).annotations
    for (const ch in a) merged[ch] = a[ch]
  }
  names[lang] = merged
}

const strip = (s) => s.replace(/️/g, "")
const lookup = (lang, e) => names[lang][e] || names[lang][strip(e)] || null

const out = []
let group = ""
for (const line of read("emoji-test.txt").split("\n")) {
  const g = /^# group: (.*)$/.exec(line)
  if (g) { group = g[1]; continue }
  const m = /^([0-9A-F ]+?)\s*; fully-qualified\s*# (\S+) E[\d.]+ (.*)$/.exec(line)
  if (!m || group === "Component") continue
  const codes = m[1].split(" ")
  if (codes.some((c) => /^1F3F[B-F]$/.test(c))) continue
  const e = m[2]
  const en = lookup("en", e)
  const fr = lookup("fr", e)
  const enName = en && en.tts ? en.tts[0] : m[3]
  const frName = fr && fr.tts ? fr.tts[0] : ""
  const words = new Set()
  for (const a of [en, fr]) if (a && a.default) a.default.forEach((w) => words.add(w))
  words.delete(enName); words.delete(frName)
  out.push({ e, en: enName, fr: frName, k: [...words].join(" | "), g: group })
}

const target = path.join(__dirname, "..", "plugins", "emojis", "emojis.json")
fs.writeFileSync(target, JSON.stringify(out) + "\n")
console.log(`${out.length} emojis → ${target}`)
