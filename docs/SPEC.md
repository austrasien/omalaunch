# omalaunch — behavioural spec

omalaunch is a keyboard-first launcher that runs inside `omarchy-shell` as a
plugin. This document says what it does. It is written from scratch for this
project; it is not derived from any other launcher's source or internals.

## 1. Runtime

- One Omarchy shell plugin, id `austraz.omalaunch`, kind `menu`, kept loaded.
- The shell calls `open(payloadJson)` and `close()`. The plugin also answers
  `qs ipc` on target `omalaunch` (`toggle`, `show`, `hide`, `isOpen`, `ping`,
  `run <id>`, `query <text>`), and registers the Hyprland global shortcut
  `omalaunch:toggle`.
- No daemon, no network access of its own. Plugins may run commands.
- Targets Omarchy 4.0.x: `Quickshell.Io.IpcHandler` and a Quickshell
  `PanelWindow` on the overlay layer with exclusive keyboard focus.

## 2. Window

- A card centred horizontally, placed about a quarter down the focused
  screen, over a transparent full-screen surface. Clicking outside closes it.
- Search field on top, result list below, a footer showing the launcher name,
  the primary action and the action-panel hint.
- Colours and fonts come from `qs.Commons` (`Color.menu.*`, `Style`), so the
  card follows `omarchy theme set` live. No theme config of its own.
- Zoom: `Ctrl +`, `Ctrl −`, `Ctrl 0`; persisted.

## 3. Sources (providers)

Everything in the list comes from a provider (see `PLUGINS.md`). Built in:

| Provider | Rows |
|---|---|
| `apps` | Desktop applications from the shell's app library (respects Omarchy's hidden entries). |
| `omarchy` | Every Omarchy menu entry from `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`, overlaid by `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Breadcrumb as subtitle. `when` hides a row, `checked` adds ✓, `disabled` greys it. Submenus open in place (Esc goes back). Runtime providers `fonts` and `power-profiles` fill their submenus. |
| `scripts` | Executables in `~/.config/omalaunch/scripts/` with a header (§7). |
| `web` | Fallback rows "Search Google / DuckDuckGo for …" at the bottom while searching. |
| `builtin` | Launcher commands: open the original Omarchy menu, reload plugins, open the scripts folder. |

User plugins live in `~/.config/omalaunch/plugins/<id>/`. Bundled plugins in
the repo's `plugins/` are installed there by `omalaunch install`.

## 4. Lists and sections

- **Empty query:** Favorites (user order) → Suggestions (top 6 by frecency) →
  Commands → Applications.
- **Query:** inline sections from plugins (e.g. the calculator) → Results
  (one ranked list across catalog providers) → plugin sections placed
  `bottom` → web fallbacks.
- Disabled (hidden) items never show. A command's subtitle is its breadcrumb
  or description; the right side shows its type.

## 5. Ranking (independent design)

Each catalog row has a title, optional subtitle, keywords and the user's
alias. For a query `q` (lower-cased, accents stripped):

1. Field match, best of:
   - alias equal to `q`: 1000; alias starting with `q`: 900
   - title equal: 800; title starting with `q`: 700
   - a word of the title starting with `q`: 600
   - `q` equal to the initials of the title words: 550
   - title containing `q`: 450
   - keyword or subtitle: same ladder at 60 %
   - fuzzy (all of `q` in order): 100–300 by how many matched letters start
     words or follow the previous match; dropped when the gaps make it look
     accidental (fewer than half the letters contiguous or on word starts, for
     queries longer than 3).
2. Learned terms: when the user launched the row after typing a query, that
   query is remembered for the row (last 50 per row, 30-day expiry). If `q`
   equals a remembered query: +350; if a remembered query starts with `q`:
   +200.
3. Frecency: each launch adds 1 to a score that halves every 7 days.
   Final score adds `40 · log2(1 + frecency)`.
4. Kind boost: a provider may add a fixed `boost` to its rows. Applications
   get +120; Omarchy entries lose 25 per menu level, so "brave" finds the
   Brave app before "Install › Browser › Brave". Fuzzy matching applies to
   titles only.
5. Ties: favourites first, then shorter title, then alphabetical.

## 6. Interaction

| Key | Does |
|---|---|
| `Enter` / `Ctrl+Enter` / `Ctrl+Shift+Enter` | first / second / third action of the selected row |
| `Ctrl+K` | action panel for the row (filterable) |
| `Ctrl+1…9` | run the n-th visible row |
| `↑` / `↓`, `Ctrl+P` / `Ctrl+N` | move |
| `Ctrl+↑` / `Ctrl+↓` | previous / next section |
| `↑` in an empty field | walk back through query history (last 50) |
| `Ctrl+Shift+F` | toggle favourite; `Ctrl+Alt+↑/↓` reorders favourites |
| `Ctrl+Shift+C` | copy (the row's copy text, else its title) |
| `Alt+Shift+D` | disable (hide) the row |
| `Ctrl+Shift+A` | set an alias for the row |
| `Esc` | close the action panel, else leave the submenu, else clear the query, else close |
| `Shift+Esc` | back to root |
| `Ctrl+A/E/B/F/W/U` | emacs-style editing in the field |

Generic actions available on every catalog row: favourite, alias, copy title,
disable, reset ranking. Disabled rows can be restored from the builtin
command "Show disabled items".

When closed, the launcher keeps its state for 90 s (reopen where you were),
then resets to root.

## 7. Script commands

An executable file in `~/.config/omalaunch/scripts/` whose first 30 lines
contain `@omalaunch.<key> <value>` comments (`#`, `//` or `--` prefixes).
Keys: `title` (required), `mode` (`silent` default, `toast`, `terminal`),
`icon` (a glyph), `description`, `argument` (placeholder: the query after the
title is passed as `$1`). `silent` runs detached; `toast` shows the last line
of stdout; `terminal` runs in a floating terminal and waits for a key.

## 8. State

`~/.local/share/omalaunch/state.json`: frecency, learned terms, aliases,
favourites, disabled ids, query history, zoom. Written debounced; a corrupt
file is moved aside and replaced.

## 9. CLI (`omalaunch`)

`install` (link the plugin and bundled plugins, enable), `uninstall`,
`reload` (force Quickshell to reload the QML), `dev` (reload on save),
`doctor`, `bind` (write `~/.config/hypr/omalaunch.lua` with a key),
`toggle|show|hide`, `run <id>`, `query <text>` (open with text).
