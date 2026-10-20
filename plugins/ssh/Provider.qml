import QtQuick
import "Ssh.js" as Ssh

// SSH hosts from ~/.ssh/config, including files it Includes: searchable
// rows, and "ssh [name]" lists them. Enter connects in a terminal window.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "SSH"
  property string placement: "inline"
  property int order: 24
  property var hosts: []
  property var items: []

  function start() { load() }
  function opened() { load() }

  function load() {
    // The config plus its Include files (relative ones resolve in ~/.ssh).
    var script = 'cfg=$HOME/.ssh/config; [[ -f $cfg ]] || exit 0; cat "$cfg"; '
      + 'grep -iE "^\\s*Include\\s" "$cfg" | sed -E "s/^\\s*[Ii]nclude\\s+//" | tr " " "\\n" | while read -r p; do '
      + '[[ $p == /* || $p == ~* ]] || p=$HOME/.ssh/$p; p=${p/#\\~/$HOME}; for f in $p; do [[ -f $f ]] && { echo; cat "$f"; }; done; done'
    root.host.capture(["bash", "-c", script], function(code, out) {
      var list = Ssh.hosts(out)
      if (JSON.stringify(list) === JSON.stringify(root.hosts)) return
      root.hosts = list
      root.items = list.map(rowFor).map(function(r) { r.visibility = "search-only"; return r })
      root.host.changed()
    })
  }

  function rowFor(h) {
    var where = (h.user ? h.user + "@" : "") + (h.hostname || h.name) + (h.port ? ":" + h.port : "")
    return { id: "h:" + h.name, title: h.name, subtitle: "ssh  ·  " + where, icon: "", type: "SSH", hostAlias: h.name, keywords: ["ssh", h.hostname], copy: "ssh " + h.name }
  }

  function query(text) {
    var words = Ssh.termsFrom(text)
    if (words === null) return []
    var rows = root.hosts.filter(function(h) {
      var hay = (h.name + " " + h.hostname + " " + h.user).toLowerCase()
      return words.every(function(w) { return hay.indexOf(w) >= 0 })
    }).map(rowFor)
    if (!rows.length && words.length === 1) rows = [{ id: "adhoc", title: "ssh " + words[0], subtitle: "Not in ~/.ssh/config", icon: "", type: "SSH", hostAlias: words[0], copy: "ssh " + words[0] }]
    return rows
  }

  function actions(row) {
    return [{ id: "connect", title: "Connect" }, { id: "copy", title: "Copy ssh Command" }, { id: "files", title: "Browse Files (sftp)" }]
  }

  function run(row, actionId) {
    if (actionId === "copy") {
      root.host.copy(row.copy)
      return { close: false, toast: "Copied" }
    }
    if (actionId === "files") {
      root.host.exec(["xdg-open", "sftp://" + row.hostAlias + "/"])
      return { close: true }
    }
    root.host.exec(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--title=ssh " + row.hostAlias, "-e", "ssh", row.hostAlias])
    return { close: true }
  }
}
