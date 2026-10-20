// Processes for "kill" (tests/processes.test.js).

// Session plumbing that must not be killed from the launcher.
var PROTECTED = ["Hyprland", "hyprland", "quickshell", "qs", "systemd", "dbus-daemon", "dbus-broker", "pipewire", "wireplumber", "pipewire-pulse", "uwsm", "Xwayland", "xdg-desktop-portal", "xdg-desktop-portal-hyprland", "gnome-keyring-daemon", "ssh-agent", "gpg-agent", "login", "sshd", "bash", "zsh", "fish", "ps"]

// "kill brave" / "tuer brave" / "kill" → words (possibly []), else null.
function termsFrom(query) {
  var m = /^(?:kill|tuer|stop)(?:\s+(.*?))?\s*$/i.exec(String(query || ""))
  return m ? (m[1] || "").toLowerCase().split(/\s+/).filter(function(w) { return w }) : null
}

// `ps -o pid=,comm=,%cpu=,rss=,args=` lines → [{ pid, comm, cpu, rss (KiB), args }].
function parsePs(text, selfPid) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    var m = /^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+(\d+)\s+(.*)$/.exec(line)
    if (!m || +m[1] === selfPid) return
    out.push({ pid: +m[1], comm: m[2], cpu: +m[3], rss: +m[4], args: m[5] })
  })
  return out
}

// Programs (by comm) with their processes, biggest memory first, keeping
// those whose name or command line holds every word.
function groups(procs, words) {
  var by = {}
  procs.forEach(function(p) {
    var hay = (p.comm + " " + p.args).toLowerCase()
    if (!words.every(function(w) { return hay.indexOf(w) >= 0 })) return
    var g = by[p.comm] || (by[p.comm] = { comm: p.comm, pids: [], cpu: 0, rss: 0, args: p.args })
    g.pids.push(p.pid)
    g.cpu += p.cpu
    g.rss += p.rss
  })
  var list = []
  for (var k in by) {
    by[k].protected = PROTECTED.indexOf(k) >= 0
    list.push(by[k])
  }
  list.sort(function(a, b) { return b.rss - a.rss })
  return list
}

function memory(kib) {
  if (kib >= 1048576) return (kib / 1048576).toFixed(1) + " GB"
  if (kib >= 1024) return Math.round(kib / 1024) + " MB"
  return kib + " KB"
}

if (typeof module !== "undefined") module.exports = { PROTECTED: PROTECTED, termsFrom: termsFrom, parsePs: parsePs, groups: groups, memory: memory }
