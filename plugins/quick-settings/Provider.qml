import QtQuick
import "Settings.js" as Settings

// Quick settings typed as commands (Settings.parse): volume, brightness,
// Wi-Fi, Bluetooth, audio output, do not disturb, battery. Rows show the
// current state; Enter applies and the launcher stays open to show the
// result.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Quick Settings"
  property string sectionTitle: "Quick Settings"
  property string placement: "inline"
  property int order: 4

  property var items: [
    { id: "go:vol", title: "Volume", subtitle: "vol 40 · vol +10 · vol mute", icon: "", type: "Setting", go: "vol ", keywords: ["sound", "son", "audio"] },
    { id: "go:lum", title: "Brightness", subtitle: "lum 70 · lum -10", icon: "", type: "Setting", go: "lum ", keywords: ["luminosité", "screen", "écran"] },
    { id: "go:wifi", title: "Wi-Fi", subtitle: "wifi · wifi on/off · wifi name", icon: "", type: "Setting", go: "wifi ", keywords: ["network", "réseau", "internet"] },
    { id: "go:bt", title: "Bluetooth", subtitle: "bt · bt on/off · bt device", icon: "", type: "Setting", go: "bt ", keywords: ["headphones", "casque", "écouteurs"] },
    { id: "go:out", title: "Audio Output", subtitle: "sortie · choose speakers or headphones", icon: "", type: "Setting", go: "sortie ", keywords: ["sortie audio", "speakers", "headphones", "hdmi"] },
    { id: "go:dnd", title: "Do Not Disturb", subtitle: "dnd · silence notifications", icon: "", type: "Setting", go: "dnd", keywords: ["ne pas déranger", "notifications", "focus"] },
    { id: "go:bat", title: "Battery", subtitle: "batterie · level, time left, power draw", icon: "", type: "Setting", go: "batterie", keywords: ["batterie", "power", "charge"] }
  ]

  function sh(script, args, callback) {
    root.host.capture(["bash", "-c", script, "bash"].concat(args || []), function(code, out, err) { callback(code, String(out || ""), String(err || "")) }, 8000)
  }

  function pct(x) { return Math.round(x) + " %" }

  function query(text, reply) {
    var q = Settings.parse(text)
    if (!q) return []
    var f = { volume: volume, brightness: brightness, wifi: wifi, bluetooth: bluetooth, output: output, dnd: dnd, battery: battery }[q.cmd]
    root.sectionTitle = "Quick Settings"
    f(q.arg, function(rows) { reply(rows, "inline") })
    return null
  }

  // ------------------------------------------------------------- volume
  function volume(arg, done) {
    sh("wpctl get-volume @DEFAULT_AUDIO_SINK@", [], function(code, out) {
      var m = /Volume:\s*([\d.]+)/.exec(out)
      var now = m ? parseFloat(m[1]) * 100 : 0
      var muted = /MUTED/.test(out)
      var rows = []
      var lv = Settings.level(arg, 150)
      if (lv) {
        var target = Math.max(0, Math.min(150, lv.set !== undefined ? lv.set : now + lv.by))
        rows.push({ id: "vol:set", title: "Set volume to " + pct(target), subtitle: "now " + pct(now) + (muted ? " (muted)" : ""), icon: "", type: "Volume", op: "vol", value: target })
      }
      if (arg === "mute" || arg === "unmute" || arg === "muet" || !lv) {
        rows.push({ id: "vol:mute", title: muted ? "Unmute" : "Mute", subtitle: "Volume " + pct(now) + (muted ? ", muted" : ""), icon: muted ? "" : "", type: "Volume", op: "mute" })
      }
      done(rows)
    })
  }

  // --------------------------------------------------------- brightness
  function brightness(arg, done) {
    sh("brightnessctl -m", [], function(code, out) {
      var f = out.trim().split(",")
      var now = f.length > 3 ? parseInt(f[3], 10) : 0
      var lv = Settings.level(arg, 100)
      if (code !== 0) { done([{ id: "bri:none", title: "No backlight found", icon: "", type: "Brightness", disabled: true }]); return }
      if (!lv) { done([{ id: "bri:now", title: "Brightness " + pct(now), subtitle: "Type a level: lum 70, lum +10", icon: "", type: "Brightness", disabled: true }]); return }
      var target = Math.max(1, Math.min(100, lv.set !== undefined ? lv.set : now + lv.by))
      done([{ id: "bri:set", title: "Set brightness to " + pct(target), subtitle: "now " + pct(now), icon: "", type: "Brightness", op: "bri", value: target }])
    })
  }

  // --------------------------------------------------------------- wifi
  function wifi(arg, done) {
    sh('nmcli -t radio wifi; printf "\\x1e"; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null; printf "\\x1e"; nmcli -t -f NAME con show 2>/dev/null', [], function(code, out) {
      var p = out.split("\x1e")
      var on = /enabled/.test(p[0] || "")
      var known = (p[2] || "").split("\n").map(function(s) { return s.replace(/\\:/g, ":") })
      var rows = []
      if (arg === "on" || arg === "off" || !arg) {
        rows.push({ id: "wifi:radio", title: on ? "Turn Wi-Fi Off" : "Turn Wi-Fi On", subtitle: on ? "Wi-Fi is on" : "Wi-Fi is off", icon: "", type: "Wi-Fi", op: "wifi-radio", value: on ? "off" : "on", disabled: (arg === "on" && on) || (arg === "off" && !on) })
      }
      if (on && arg !== "on" && arg !== "off") {
        Settings.networks(p[1]).filter(function(n) { return !arg || n.ssid.toLowerCase().indexOf(arg) >= 0 }).slice(0, 12).forEach(function(n) {
          rows.push({ id: "wifi:" + n.ssid, title: n.ssid, subtitle: (n.active ? "Connected  ·  " : (known.indexOf(n.ssid) >= 0 ? "Known  ·  " : "")) + n.signal + " %" + (n.secure ? "  ·  secured" : "  ·  open"),
            icon: n.secure ? "" : "", type: "Wi-Fi", op: n.active ? "wifi-off-net" : "wifi-join", value: n.ssid, known: known.indexOf(n.ssid) >= 0 })
        })
      }
      done(rows)
    })
  }

  // ---------------------------------------------------------- bluetooth
  function bluetooth(arg, done) {
    var script = 'bluetoothctl show | grep -q "Powered: yes" && echo on || echo off; printf "\\x1e"; '
      + 'bluetoothctl devices Paired | while read -r _ mac name; do c=$(bluetoothctl info "$mac" | grep -q "Connected: yes" && echo yes || echo no); printf "Device %s %s\\t%s\\n" "$mac" "$name" "$c"; done'
    sh(script, [], function(code, out) {
      var p = out.split("\x1e")
      var on = (p[0] || "").trim() === "on"
      var rows = []
      if (arg === "on" || arg === "off" || !arg) rows.push({ id: "bt:power", title: on ? "Turn Bluetooth Off" : "Turn Bluetooth On", subtitle: on ? "Bluetooth is on" : "Bluetooth is off", icon: "", type: "Bluetooth", op: "bt-power", value: on ? "off" : "on", disabled: (arg === "on" && on) || (arg === "off" && !on) })
      if (arg !== "on" && arg !== "off") {
        Settings.devices(p[1]).filter(function(d) { return !arg || d.name.toLowerCase().indexOf(arg) >= 0 }).forEach(function(d) {
          rows.push({ id: "bt:" + d.mac, title: d.name, subtitle: d.connected ? "Connected  ·  Enter disconnects" : (on ? "Paired  ·  Enter connects" : "Paired  ·  Bluetooth is off"), icon: "", type: "Bluetooth", op: d.connected ? "bt-disconnect" : "bt-connect", value: d.mac, disabled: !on && !d.connected })
        })
      }
      done(rows)
    })
  }

  // ------------------------------------------------------------- output
  function output(arg, done) {
    sh("wpctl status", [], function(code, out) {
      var rows = Settings.sinks(out).filter(function(s) { return !arg || s.name.toLowerCase().indexOf(arg) >= 0 }).map(function(s) {
        return { id: "out:" + s.id, title: s.name, subtitle: s.default ? "Current output" : "Enter makes it the output", icon: /hdmi|displayport/i.test(s.name) ? "" : (/head|casque|bluez|buds|q45|shokz/i.test(s.name) ? "" : ""), type: "Output", op: "sink", value: s.id, disabled: s.default }
      })
      done(rows.length ? rows : [{ id: "out:none", title: "No audio output found", icon: "", type: "Output", disabled: true }])
    })
  }

  // ---------------------------------------------------------------- dnd
  function dnd(arg, done) {
    sh("omarchy-shell notifications isDnd 2>/dev/null", [], function(code, out) {
      var on = /^(on|true|1)$/i.test(out.trim())
      var want = arg === "on" ? true : (arg === "off" ? false : !on)
      done([{ id: "dnd", title: want ? "Turn On Do Not Disturb" : "Turn Off Do Not Disturb", subtitle: "Do not disturb is " + (on ? "on" : "off"), icon: want ? "" : "", type: "Notifications", op: "dnd", disabled: want === on }])
    })
  }

  // ------------------------------------------------------------ battery
  function battery(arg, done) {
    sh('b=$(upower -e | grep -m1 BAT) || exit 1; upower -i "$b"', [], function(code, out) {
      if (code !== 0) { done([{ id: "bat:none", title: "No battery", icon: "", type: "Battery", disabled: true }]); return }
      var get = function(k) { var m = new RegExp(k + ":\\s*(.*)").exec(out); return m ? m[1].trim() : "" }
      var level = parseFloat(get("percentage")) || 0
      var state = get("state")
      var left = get("time to empty") || get("time to full")
      var rate = parseFloat(get("energy-rate")) || 0
      var health = get("capacity")
      var icon = level > 87 ? "" : level > 62 ? "" : level > 37 ? "" : level > 12 ? "" : ""
      var fr = { discharging: "on battery", charging: "charging", "fully-charged": "full", "pending-charge": "plugged in" }[state] || state
      done([{ id: "bat", title: "Battery " + Math.round(level) + " %" + (left ? "  ·  " + left + (state === "charging" ? " to full" : " left") : ""), subtitle: fr + (rate ? "  ·  " + rate.toFixed(1) + " W" : "") + (health ? "  ·  health " + Math.round(parseFloat(health)) + " %" : ""), icon: icon, type: "Battery", op: "power", disabled: false, copy: Math.round(level) + " %" }])
    })
  }

  // ------------------------------------------------------------ actions
  function actions(row) {
    if (row.go !== undefined) return [{ id: "go", title: "Open " + row.title }]
    if (row.op === "power") return [{ id: "apply", title: "Power Profiles" }]
    if (row.op === "wifi-join" && !row.known) return [{ id: "apply", title: "Connect (asks for the password)" }]
    return [{ id: "apply", title: row.title }]
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function run(row, actionId) {
    if (row.go !== undefined) {
      root.host.setQuery(row.go)
      return { close: false }
    }
    var cmd = null
    switch (row.op) {
    case "vol": cmd = "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " + (row.value / 100).toFixed(2); break
    case "mute": cmd = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; break
    case "bri": cmd = "brightnessctl -q set " + row.value + "%"; break
    case "wifi-radio": cmd = "nmcli radio wifi " + row.value; break
    case "wifi-off-net": cmd = "nmcli con down id " + quote(row.value); break
    case "wifi-join":
      if (!row.known) {
        root.host.terminal("nmcli --ask dev wifi connect " + quote(row.value), true)
        return { close: true }
      }
      cmd = "nmcli con up id " + quote(row.value); break
    case "bt-power": cmd = "bluetoothctl power " + row.value; break
    case "bt-connect": cmd = "bluetoothctl connect " + row.value; break
    case "bt-disconnect": cmd = "bluetoothctl disconnect " + row.value; break
    case "sink": cmd = "wpctl set-default " + row.value; break
    case "dnd": cmd = "omarchy toggle notification silencing"; break
    case "power":
      root.host.setQuery("power profile")
      return { close: false }
    }
    if (!cmd) return { close: false }
    root.host.toast("…")
    sh(cmd + " 2>&1", [], function(code, out) {
      var last = out.trim().split("\n").pop()
      root.host.toast(code === 0 ? "Done" : "Failed: " + last)
      root.host.refresh()
    })
    return { close: false }
  }
}
