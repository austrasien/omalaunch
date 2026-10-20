import QtQuick

// The launcher's own commands.
Item {
  id: root

  property var host: null
  property string title: "omalaunch"
  required property var launcher         // Main.qml

  property var items: [
    { id: "omarchy-menu", title: "Omarchy Menu", subtitle: "Open the original Omarchy menu", icon: "\uf0c9", type: "Command", keywords: ["menu", "omarchy"] },
    { id: "reload-plugins", title: "Reload omalaunch Plugins", subtitle: "Rescan ~/.config/omalaunch/plugins", icon: "󰑓", type: "Command", keywords: ["plugins", "refresh"] },
    { id: "open-scripts", title: "Open Scripts Folder", subtitle: "~/.config/omalaunch/scripts", icon: "\uf120", type: "Command", keywords: ["script commands"] },
    { id: "open-plugins", title: "Open Plugins Folder", subtitle: "~/.config/omalaunch/plugins", icon: "\uf07b", type: "Command", keywords: ["extensions"] },
    { id: "disabled", title: "Show Disabled Items", subtitle: "Restore hidden rows", icon: "󰈉", type: "Command", keywords: ["hidden", "enable"] },
    { id: "plugin-errors", title: "Show Plugin Errors", subtitle: "Plugins that failed to load", icon: "\uf071", type: "Command", keywords: ["debug"] }
  ]

  function actions(row) {
    if (String(row.id).indexOf("restore:") === 0) return [{ id: "restore", title: "Enable Again" }]
    if (String(row.id).indexOf("error:") === 0) return [{ id: "copy", title: "Copy Error" }]
    return [{ id: "run", title: "Run" }]
  }

  function run(row, actionId) {
    if (String(row.id).indexOf("restore:") === 0) {
      root.launcher.enableKey(row.target)
      return { close: false, toast: "Enabled " + row.title }
    }
    if (String(row.id).indexOf("error:") === 0) {
      root.host.copy(row.copy)
      return { close: false, toast: "Copied" }
    }
    switch (row.id) {
    case "omarchy-menu":
      root.host.exec(["omarchy-menu"])
      return { close: true }
    case "reload-plugins":
      root.launcher.reloadPlugins()
      return { close: false, toast: "Plugins reloaded" }
    case "open-scripts":
      root.host.exec(["bash", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "bash", root.host.home + "/.config/omalaunch/scripts"])
      return { close: true }
    case "open-plugins":
      root.host.exec(["bash", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "bash", root.host.home + "/.config/omalaunch/plugins"])
      return { close: true }
    case "disabled":
      return { close: false, push: { id: "builtin:disabled", title: "Disabled Items", rows: root.launcher.disabledRows() } }
    case "plugin-errors":
      return { close: false, push: { id: "builtin:errors", title: "Plugin Errors", rows: root.launcher.errorRows() } }
    }
    return { close: false }
  }
}
