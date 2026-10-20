import QtQuick
import Quickshell.Services.Mpris

// Controls the active media player over MPRIS. The rows are refreshed each
// time the launcher opens and after every action.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Music"
  property var items: []

  // The playing player if any, else the first one that can play.
  function player() {
    var list = Mpris.players.values
    for (var i = 0; i < list.length; i++) if (list[i].playbackState === MprisPlaybackState.Playing) return list[i]
    for (var j = 0; j < list.length; j++) if (list[j].canPlay) return list[j]
    return list.length ? list[0] : null
  }

  function nowPlaying(p) {
    if (!p) return ""
    var t = p.trackTitle || ""
    var a = p.trackArtist || ""
    return t && a ? t + " — " + a : t
  }

  function refresh() {
    var p = player()
    var playing = p && p.playbackState === MprisPlaybackState.Playing
    var none = !p
    var info = none ? "No media player running" : [nowPlaying(p), p.identity || ""].filter(function(x) { return x }).join("  ·  ")
    var rows = [
      { id: "toggle", title: playing ? "Pause Music" : "Play Music", subtitle: info, icon: playing ? "" : "", type: "Music", keywords: ["play", "pause", "music", "media", "song"], disabled: none, copy: nowPlaying(p) },
      { id: "next", title: "Next Track", subtitle: info, icon: "", type: "Music", keywords: ["skip", "music", "song"], disabled: none || !p.canGoNext },
      { id: "previous", title: "Previous Track", subtitle: info, icon: "", type: "Music", keywords: ["back", "music", "song"], disabled: none || !p.canGoPrevious }
    ]
    if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
      root.items = rows
      if (root.host) root.host.changed()
    }
  }

  function start() { refresh() }
  function opened() { refresh() }

  Connections {
    target: Mpris.players
    function onValuesChanged() { root.refresh() }
  }

  function actions(row) {
    if (row.id === "toggle") return [{ id: "run", title: row.title }, { id: "copy-track", title: "Copy Track Name" }]
    return [{ id: "run", title: row.title }]
  }

  function run(row, actionId) {
    var p = player()
    if (!p) return { close: false, toast: "No media player running" }
    if (actionId === "copy-track") {
      root.host.copy(nowPlaying(p))
      return { close: false, toast: "Copied" }
    }
    if (row.id === "toggle") p.togglePlaying()
    else if (row.id === "next") p.next()
    else if (row.id === "previous") p.previous()
    refreshTimer.restart()
    return { close: true }
  }

  // Track metadata changes a moment after the command.
  Timer { id: refreshTimer; interval: 600; onTriggered: root.refresh() }
}
