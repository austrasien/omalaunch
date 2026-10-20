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
  images, PDFs, videos, text and Markdown, folders, clipboard entries.
- **Search filters.** `pdf facture`, `img`, `doc`, `vid`: file searches tied
  to extensions and folders, editable in `~/.config/omalaunch/file-filters.json`.
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
