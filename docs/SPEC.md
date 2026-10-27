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

- A card centred on the focused screen (vertically at its tallest, so the
  search field does not move as results change), over a transparent
  full-screen surface. Clicking outside closes it.
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
| `scripts` | Executables in `~/.config/omalaunch/scripts/` with a header (§7); filter scripts also answer `<keyword> text`. |
| `shell` | `> command` runs the command in a floating terminal (Ctrl+Enter: in the background). |
| `web` | Fallback rows "Search Google / DuckDuckGo for …" at the bottom while searching. |
| `builtin` | Launcher commands: open the original Omarchy menu, reload plugins, open the scripts folder. |

User plugins live in `~/.config/omalaunch/plugins/<id>/`. Bundled plugins in
the repo's `plugins/` are installed there by `omalaunch install`:

| Plugin | Rows |
|---|---|
| `calculator` | Arithmetic, currencies (ECB daily rates), units with `qalc`. |
| `claude` | Offered with Google and DuckDuckGo under "Search the web" for any search; `? question` puts it on top. Enter streams the answer under the search field (Markdown, in place of the list); a question within 15 minutes continues the same conversation (Sonnet, for speed); on the answer, Enter continues it in Claude Code, Ctrl+Enter copies it, Esc goes back. Ctrl+Enter on the question asks in Claude Code directly. `cc` / `resume` [words]: recent Claude Code sessions by title; Enter resumes in a terminal in the session's folder, Quick Look shows its last exchanges. |
| `files` | `'term` or `find term`: files and folders under `~` (fd, hidden and ignored files skipped). Search filters: `<keyword> term` limited to extensions and folders (`~/.config/omalaunch/file-filters.json`; defaults `pdf`, `img`, `doc`, `vid`); a keyword with no term lists the newest matches of the past year. Recently used documents (`recently-used.xbel`) are searchable rows and a "Recent Documents" list. |
| `clipboard` | `clip text` searches Omarchy's clipboard history; "Clipboard History" lists it. Enter pastes into the focused window, Ctrl+Enter copies. |
| `music` | Play/Pause, Next, Previous for the active MPRIS player, with the current track. |
| `dictionary` | `define word` (Wiktionary, English glosses for any language), `spell word` (hunspell). |
| `emojis` | `:name` in French or English (Unicode CLDR names); Enter pastes, a bare `:` lists the last used. |
| `snippets` | `;name` pastes `~/.config/omalaunch/snippets/name.*` with variables filled in (README); `{input:…}` asks in the launcher; `{shell:…}` runs only in executable snippet files; the text clipboard is restored after pasting. |
| `web-keywords` | `<keyword> terms` opens a site search; defaults in `Keywords.js`, overrides in `~/.config/omalaunch/web.json` (`null` removes a default). |
| `clock` | `heure tokyo`, `15h paris en tokyo`, `1000 UTC+2 to BST` (cities, `UTC±h[:mm]`, `+hhmm` and abbreviations such as BST, CET, EST, PST, JST), `maintenant en pst`, `dans 3 jours`, `jusqu'au 25/12`, `timer 25 café` (an Omarchy reminder). |
| `browser` | Bookmarks of the most recently used Chromium-family profile as searchable rows; `b term` over bookmarks and history (read in place, sqlite immutable). |
| `quick-settings` | `vol 40` / `vol +10` / `vol mute`, `lum 70`, `wifi [on/off/name]`, `bt [on/off/device]`, `sortie` (audio output), `dnd`, `batterie`. |
| `processes` | `kill [name]`: your processes grouped by program, by memory; Enter SIGTERM, Ctrl+Enter SIGKILL; session plumbing protected. |
| `ssh` | Hosts from `~/.ssh/config` and its Includes as rows; `ssh [name]`; Enter connects in a terminal. |
| `agenda` | `agenda [demain / words]`: the next 14 days from `~/.config/omalaunch/calendars.json` (iCalendar URLs, e.g. Google Calendar's secret iCal address; RRULE, EXDATE and moved instances expanded by `agenda.py`); a "Next:" row; Enter joins the call link. |
| `obsidian` | `o term` (titles, then content via ripgrep), `o` (newest notes), `o+ text` (a `- HH:mm text` line under `## Notes` in today's daily note, created from the daily template), `on Title` (new note in the new-note folder or `Inbox/`). |

## 4. Lists and sections

When at least 60 % of the rows (and 4 or more) are images, PDFs, videos,
slides or emojis, the list becomes a 5-column grid of thumbnails (rendered
by `preview.sh` at 320 px and cached). Arrows move in two dimensions;
`Ctrl+G` switches between grid and list until the launcher resets.

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
| `Ctrl+Shift+H` | give the row its own Hyprland key (typed as `SUPER + SHIFT + B`; empty removes it) |
| `Ctrl+L` | show the row's copy text (else its title) in Large Type; any key closes it |
| `Shift` (tap) / `Ctrl+Y` | Quick Look: a pane beside the list previews the selected row's file (`previewPath` or `path`, rendered by `plugin/services/preview.sh`): images; PDF pages (up to 8, scrolling) with the page count; videos as a 3 × 2 contact sheet with duration, size and codec; audio with cover or waveform and tags; office documents and slides via LibreOffice; spreadsheets (CSV, TSV, xlsx, ods) as tables; archives as file listings; code and JSON with syntax colours (Pygments); 3D models (STL, OBJ, 3MF, STEP…) rendered with f3d when installed, with their dimensions; fonts as a sample; EPUB covers with title and author; git repositories with branch, changes and README; Obsidian notes with links and embedded images resolved; Markdown, text and folder listings; else file info. Or the row's `previewText`, or the provider's `preview()`. The pane takes the content's proportions within the free screen area (portrait pages fill the height, slides the width), text and folders fill the height, and the card moves left so both stay centred; it follows the selection, `Shift+↑/↓` scrolls it, `Esc` closes it |
| `Esc` | close the action panel, else leave the submenu, else close (the query is kept for the next opening, fully selected) |
| `Shift+Esc` | back to root |
| `Ctrl+A/E/B/F/W/U` | emacs-style editing in the field |

Generic actions available on every catalog row: favourite, alias, hotkey,
copy title, Large Type, disable, reset ranking. Query rows get copy and Large Type. Disabled rows can be restored from the builtin
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

`mode filter` with `keyword <word>` makes a script filter: while the query is
`<word> text`, the script runs with `text` as `$1` and prints JSON items
(`PLUGINS.md`), shown inline. Enter opens an item's `open` target or runs the
script again as `<script> --run <arg>`.

## 8. State

`~/.local/share/omalaunch/state.json`: frecency, learned terms, aliases,
favourites, disabled ids, query history, zoom. Written debounced; a corrupt
file is moved aside and replaced. `omalaunch sync DIR` moves the whole
directory into DIR and leaves a symlink (the directory, not the file, because
writes are atomic renames). Per-row hotkeys: `~/.local/state/omalaunch/hotkeys.tsv`.

## 9. CLI (`omalaunch`)

`install` (link the plugin and bundled plugins, enable), `uninstall`,
`reload` (force Quickshell to reload the QML), `dev` (reload on save),
`doctor`, `bind` (write `~/.config/hypr/omalaunch.lua` with a key),
`hotkey set|unset|list` (per-row keys in `~/.config/hypr/omalaunch-hotkeys.lua`,
checked against existing Hyprland binds), `scratchpad [KEYS…]|off` (keys in
`~/.config/hypr/omalaunch-scratchpad.lua` that toggle the scratchpad, open the
launcher over it when it is empty, and close it again when the launcher is
dismissed with Esc), `sync DIR|off`,
`toggle|show|hide`, `run <id>`, `query <text>` (open with text),
`search <text>` (print the rows a query returns, without opening).
