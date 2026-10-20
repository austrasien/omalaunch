const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const S = require(path.join(__dirname, "..", "plugins", "quick-settings", "Settings.js"))

test("quick settings: commands and levels", () => {
  assert.deepStrictEqual(S.parse("vol 40"), { cmd: "volume", arg: "40" })
  assert.deepStrictEqual(S.parse("Luminosité +10"), { cmd: "brightness", arg: "+10" })
  assert.deepStrictEqual(S.parse("ne pas déranger"), { cmd: "dnd", arg: "" })
  assert.deepStrictEqual(S.parse("bt q45"), { cmd: "bluetooth", arg: "q45" })
  assert.strictEqual(S.parse("volcano"), null)
  assert.deepStrictEqual(S.level("40%"), { set: 40 })
  assert.deepStrictEqual(S.level("-5"), { by: -5 })
  assert.strictEqual(S.level("120"), null)
  assert.deepStrictEqual(S.level("120", 150), { set: 120 })
})

test("quick settings: parsers", () => {
  const status = "PipeWire\nAudio\n ├─ Devices:\n │      48. Ryzen HD Audio Controller [alsa]\n ├─ Sinks:\n │  *   59. Ryzen HD Audio Controller Analog Stereo [vol: 0.45]\n │      77. soundcore Space Q45 [vol: 0.80]\n │\n ├─ Sources:\n │  *   60. Mic [vol: 0.93]\nVideo\n"
  assert.deepStrictEqual(S.sinks(status), [{ id: 59, name: "Ryzen HD Audio Controller Analog Stereo", default: true }, { id: 77, name: "soundcore Space Q45", default: false }])
  const nets = S.networks(" :Home:60:WPA2\n*:Home:80:WPA2\n :Cafe\\:Wifi:90:\n :Guest:40:--\n")
  assert.deepStrictEqual(nets.map((n) => [n.ssid, n.active, n.secure]), [["Home", true, true], ["Cafe:Wifi", false, false], ["Guest", false, false]])
  assert.deepStrictEqual(S.devices("Device F4:9D:8A:75:8E:03 soundcore Space Q45\tyes\n"), [{ mac: "F4:9D:8A:75:8E:03", name: "soundcore Space Q45", connected: true }])
})
