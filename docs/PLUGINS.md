# Writing omalaunch plugins

A plugin is a folder in `~/.config/omalaunch/plugins/<folder>/` with a
`manifest.json` and one QML file. The built-in sources (applications, the
Omarchy menu, scripts, web fallbacks) use the same interface.

```json
{
  "id": "weather",
  "name": "Weather",
  "version": "1.0.0",
  "author": "you",
  "license": "MIT",
  "description": "Shows the weather inline.",
  "entry": "Provider.qml"
}
```

`id` is lower-case letters, digits, `.`, `_` or `-`, and must be unique.
Rows from the plugin get keys `<id>:<row id>`, which is what favourites,
aliases and rankings remember, so keep row ids stable.

## The provider object

The entry file's root object is any QML item. omalaunch sets `host` and
`pluginDir`, then calls `start()`. Every member below is optional except
`host`.

```qml
import QtQuick

Item {
  property var host: null           // required: the host API, set before start()
  property string pluginDir: ""     // absolute path of the plugin folder

  property string title: "Weather"  // fallback section title
  property string sectionTitle: ""  // section title for query rows (overrides title)
  property string placement: "inline" // where query rows go: "inline" (top) or "bottom"
  property int order: 50            // order among sections with the same placement

  // Catalog rows: ranked by omalaunch together with apps and commands.
  // Call host.changed() after replacing the array.
  property var items: []

  function start() {}               // once, after host is set
  function opened() {}              // each time the launcher opens

  // Query rows: called (debounced) for every non-empty search. Return rows,
  // or call reply(rows[, placement]) later; late replies for an old query
  // are dropped. Return [] for nothing.
  function query(text, reply) { return [] }

  // Actions for a row; the first is the primary (Enter), the next two get
  // Ctrl+Enter and Ctrl+Shift+Enter. Default: [{ id: "run", title: "Open" }].
  function actions(row) { return [{ id: "run", title: "Open" }] }

  // Do it. Return { close?: bool, toast?: string, push?: { id, title, rows } }.
  // `push` opens a sub-list (Esc goes back). ctx = { query, alias }.
  function run(row, actionId, ctx) { return { close: true } }
}
```

### Rows

| Field | Meaning |
|---|---|
| `id` | Stable id within the plugin (required). |
| `title` | Main text (required). |
| `subtitle` | Secondary text, also searched (at reduced weight). |
| `keywords` | Extra search terms (array of strings). |
| `icon` | A Nerd Font glyph. Write private-use glyphs as `""` escapes. |
| `iconFont` | Font family for the glyph, if not the shell font. |
| `iconSource` | An image URL instead of a glyph. |
| `type` | Label on the right (e.g. "Command"). |
| `group` | `"commands"` (default) or `"apps"`, for the empty-query sections. |
| `when` | Catalog rows only: `"always"` (default), `"searching"` (hidden until the user types) or `"empty"`. |
| `boost` | Number added to the rank score; use sparingly. |
| `copy` | Text for Ctrl+Shift+C (defaults to the title). |
| `disabled` | Shown greyed out; Enter does nothing. |

Any other fields are kept and handed back to `actions()` and `run()`.

### The host API

| Member | Does |
|---|---|
| `host.exec(argv)` | Run a program detached (no shell). |
| `host.shell(cmd)` | Run a bash command detached (login shell). |
| `host.capture(argv, cb(code, stdout, stderr), timeoutMs)` | Run and collect output. |
| `host.copy(text)` | Put text on the clipboard. |
| `host.browse(url)` | Open a URL in the default browser. |
| `host.notify(title, body)` | Desktop notification. |
| `host.terminal(cmd, hold)` | Run `cmd` in a floating terminal; `hold` waits for a key at the end. |
| `host.toast(text)` | Message in the launcher footer. |
| `host.close()` | Hide the launcher. |
| `host.setQuery(text)` | Replace the search text. |
| `host.changed()` | Tell omalaunch that `items` changed. |
| `host.refresh()` | Re-run the current query. |
| `host.reply(rows, placement)` | Push query rows at any time. |
| `host.dataDir` | `~/.local/share/omalaunch/plugins/<id>` (create it yourself). |
| `host.home`, `host.omarchyPath` | Paths. |
| `host.appLibrary` | The shell's app library when available (may be null). |

## Developing

`omalaunch reload` (or the "Reload omalaunch Plugins" command) reloads
plugin QML. Quickshell caches imported `.js` files for the life of the
shell, so after editing a plugin's JavaScript run `omarchy-restart-shell`.
Load errors appear under "Show Plugin Errors" and in `omalaunch plugins`.

## Script commands

For a quick command, drop an executable into `~/.config/omalaunch/scripts/`:

```bash
#!/bin/bash
# @omalaunch.title Restart Waybar
# @omalaunch.mode toast
# @omalaunch.icon 󰑓
# @omalaunch.description Kill and relaunch the bar
# @omalaunch.argument optional message
omarchy-restart-waybar && echo "Bar restarted ${1:-}"
```

Modes: `silent` (default), `toast` (notification with the last line of
output), `terminal` (floating terminal). With `argument`, type the title, a
space, then the argument; it arrives as `$1`.
