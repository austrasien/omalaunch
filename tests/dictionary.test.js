const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const D = require(path.join(__dirname, "..", "plugins", "dictionary", "Dictionary.js"))

test("dictionary: prefixes", () => {
  assert.deepStrictEqual(D.parse("define maison"), { mode: "define", word: "maison" })
  assert.deepStrictEqual(D.parse("Def  ice cream "), { mode: "define", word: "ice cream" })
  assert.deepStrictEqual(D.parse("spell recieve"), { mode: "spell", word: "recieve" })
  assert.strictEqual(D.parse("defined"), null)
})

test("dictionary: html and definitions", () => {
  assert.strictEqual(D.stripHtml('<a href="/wiki/house">house</a> &amp; <b>home</b>&#39;s'), "house & home's")
  const json = { other: [{ partOfSpeech: "Noun", language: "Other", definitions: [{ definition: "x" }] }],
    fr: [{ partOfSpeech: "Noun", language: "French", definitions: [{ definition: "<i>house</i>" }, { definition: "" }] }] }
  assert.deepStrictEqual(D.definitions(json, ["fr", "en"], 5).map((d) => d.definition + "/" + d.language), ["house/French", "x/Other"])
})

test("dictionary: hunspell output", () => {
  assert.deepStrictEqual(D.spellResult("@(#) Hunspell\n*\n"), { correct: true, suggestions: [] })
  assert.deepStrictEqual(D.spellResult("@(#) Hunspell\n& recieve 2 0: receive, relieve\n"), { correct: false, suggestions: ["receive", "relieve"] })
  assert.deepStrictEqual(D.dictionaries("SEARCH PATH:\n.\nAVAILABLE DICTIONARIES (path is not mandatory for -d option):\n/usr/share/hunspell/fr_FR\n/usr/share/hunspell/en_US\n"), ["fr_FR", "en_US"])
})
