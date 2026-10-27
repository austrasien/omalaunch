# omalaunch

A keyboard-first launcher for [Omarchy](https://omarchy.org), running inside
`omarchy-shell`. One search for your applications, every Omarchy menu action,
your scripts and plugins, ranked by what you actually use.

- **Learns.** Results are ranked by match quality, how often and how recently
  you used them, and the queries you typed before picking them: if you type
  `te` and pick Terminal, `te` keeps meaning Terminal.
- **Everything Omarchy.** All Omarchy menu entries with their breadcrumbs,
  live ✓ state and hidden/greyed conditions, plus your own menu extensions.
- **Yours.** Aliases, favourites (reorderable), and hiding what you never use.
- **Extensible.** Plugins are a manifest and a QML file
  ([docs/PLUGINS.md](docs/PLUGINS.md)); script commands are any executable
  with a header.
- **Bundled plugins.** Calculator with currency conversion (ECB daily rates,
  units via `qalc` when installed), Claude (`? your question`), files
  (`'name` or `find name`, plus recent documents), clipboard history
  (`clip text`), music controls, and a dictionary (`define word`,
  `spell word`).
- **Quick Look.** Tap `Shift` (or `Ctrl+Y`) to preview the selected file:
  images, PDF pages, videos (contact sheet), audio, office documents and
  slides, spreadsheets, archives, code with syntax colours, 3D models (with
  `f3d`), fonts, EPUBs, git repositories, Obsidian notes, clipboard entries.
- **Search filters.** `pdf facture`, `img`, `doc`, `vid`: file searches tied
  to extensions and folders, editable in `~/.config/omalaunch/file-filters.json`.
- **More plugins.** Emojis in French or English (`:feu`, `:fire`), snippets
  (`;sig`, with `{date}`, `{clipboard}`, `{input:…}` and more), site searches
  (`gh`, `yt`, `maps`, `wiki`, `deepl`, `amz`…), a world clock and timers
  (`heure tokyo`, `dans 3 jours`, `timer 25 café`), Obsidian notes (`o`,
  `o+`, `on`), Claude answering right under the search field (`? question`,
  follow-ups keep the conversation) and Claude Code sessions (`cc`).
- **Laptop daily.** Browser bookmarks and history (`b …`), quick settings
  (`vol 40`, `lum 70`, `wifi`, `bt`, `sortie`, `dnd`, `batterie`), `kill …`,
  SSH hosts (`ssh …`), your agenda (`agenda`, Enter joins the call) and time
  conversions (`1000 UTC+2 to BST`).
- **Grid view.** Images, PDFs and emojis show as thumbnails (`Ctrl+G` toggles).
- **Shell and keys.** `> command` runs a command; any row can get its own
  Hyprland key (`Ctrl+Shift+H`); `Ctrl+L` shows a result in Large Type.
- **Sync.** `omalaunch sync ~/Dropbox/omalaunch` keeps rankings and settings
  in a synced folder.
- **Native.** No daemon, no Electron. Colours follow `omarchy theme set` live.

Behaviour is specified in [docs/SPEC.md](docs/SPEC.md).

## Install

Requires Omarchy 4 (`omarchy-shell`) and `fd` for file search. Optional:
`libqalculate` for units in the calculator, the `claude` CLI for the Claude
plugin, `hunspell-fr` / `hunspell-en_us` for `spell`.

```sh
git clone https://github.com/austrasien/omalaunch.git ~/src/omalaunch
~/src/omalaunch/bin/omalaunch install   # link the plugin, bundled plugins and the CLI
omalaunch bind                          # Alt+Space (or: omalaunch bind "SUPER + SPACE")
omalaunch doctor
```

`omalaunch uninstall` and `omalaunch unbind` undo it. Your rankings stay in
`~/.local/share/omalaunch/`.

## Keys

| Key | Does |
|---|---|
| `Enter` / `Ctrl+Enter` / `Ctrl+Shift+Enter` | First / second / third action |
| `Ctrl+K` | All actions for the row |
| `Ctrl+1`…`9` | Run the n-th row |
| `↑` / `↓`, `Ctrl+P` / `Ctrl+N` | Move |
| `Ctrl+↑` / `Ctrl+↓` | Previous / next section |
| `↑` on an empty search | Previous queries |
| `Ctrl+Shift+F` | Favourite (`Ctrl+Alt+↑/↓` reorders) |
| `Ctrl+Shift+A` | Set an alias |
| `Ctrl+Shift+H` | Give the row its own key |
| `Ctrl+L` | Large Type |
| `Shift` (tap) / `Ctrl+Y` | Quick Look (`Shift+↑/↓` scrolls it) |
| `Ctrl+G` | Grid / list |
| `Ctrl+Shift+C` | Copy |
| `Alt+Shift+D` | Hide the row ("Show Disabled Items" restores it) |
| `Esc` / `Shift+Esc` | Back / back to root |
| `Ctrl +` / `Ctrl −` / `Ctrl 0` | Zoom |

## CLI

```sh
omalaunch toggle | show | hide
omalaunch query "2+2"           # open with text
omalaunch run apps:firefox      # run a row by key
omalaunch search lock           # print what a search returns
omalaunch plugins               # loaded providers and plugin errors
omalaunch reload | dev          # reload QML once / on every save
omalaunch hotkey set "SUPER + B" apps:firefox   # a key for one row; hotkey list | unset
omalaunch scratchpad "SUPER + grave"            # toggle the scratchpad, launcher over it when empty; Esc closes both; scratchpad off
omalaunch sync ~/Dropbox/omalaunch              # keep settings in a synced folder; sync off
```

## Development

```sh
node --test tests/*.test.js     # ranking, state, menu parsing, calculator
omalaunch dev                   # reload on save
```

## License

MIT. omalaunch is an independent project, written from its own spec. It is
not affiliated with Raycast or Omarchy.

## Snippets

Each file in `~/.config/omalaunch/snippets/` is a snippet named after the
file: `sig.txt` is pasted with `;sig`. Variables:

| Variable | Gives |
|---|---|
| `{date}`, `{date:DD/MM/YYYY}` | today (tokens: `YYYY YY MMMM MMM MM M DD D dddd ddd HH H mm ss WW`, `[text]` literal; French month and day names) |
| `{date+3d}`, `{date-1w:dddd}` | a shifted date: `d` days, `w` weeks, `m` months, `y` years |
| `{time}`, `{datetime}`, `{weekday}`, `{week}` | 17:42, 2026-10-20 17:42, mardi, 43 |
| `{clipboard}`, `{selection}` | the clipboard text, the selected text |
| `{cursor}` | where the cursor ends up after pasting |
| `{input:Label}` | asks for a value in the launcher first |
| `{hostname}`, `{user}`, `{fullname}`, `{email}` | machine, user, git name and email |
| `{ip}`, `{publicip}` | local and public IPv4 |
| `{uuid}`, `{random:8}` | a UUID, 8 random characters |
| `{snippet:name}` | another snippet |
| `{shell:command}` | the command's output; only in snippet files marked executable (`chmod +x`) |

Unknown variables are left as they are.

