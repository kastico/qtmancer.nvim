# qtmancer.nvim

*Conjure Qt from inside Neovim.*

A Neovim plugin for Qt C++ and QML development: project tooling, Qt Designer integration, build/debug helpers and offline Qt documentation, without leaving the editor.

> **Fork notice.** qtmancer.nvim is a fork of [2774326573/qt-assistant.nvim](https://github.com/2774326573/qt-assistant.nvim). The project management, UI Designer, class generation, build and debug tooling comes from the original project, and credit for that work goes to its author. This fork restructures the code base and adds a Qt documentation viewer with QML-aware lookup.

## Features

Inherited from upstream (see the [upstream README](https://github.com/2774326573/qt-assistant.nvim#readme) for details):

- Create and open Qt projects (CMake and qmake), including multi-module workspaces
- Create and edit `.ui` files and launch Qt Designer
- Generate C++ classes, including from `.ui` files via `uic`
- Build and run, CMake presets, automatic `CMakeLists.txt` updates
- Debugging through `nvim-dap`
- Linux, macOS and Windows

New in this fork:

- Restructured code base (`lua/qt/core`, `build`, `create`, `designer`, `docs`)
- Keymaps in one place with a configurable prefix
- Dead code removed, missing `qt.debug` module guarded
- Offline Qt documentation lookup for the symbol under the cursor, the visual selection or a typed query
- QML type and member lookup (`TextArea`, `ApplicationWindow`, ...), lightly tested
- Docs in a reusable right-hand `w3m` split, updated in place, lightly tested

## Qt documentation lookup

The plugin finds the Qt documentation installed on your system, builds a symbol index from the qdoc `.index` files (cached after the first run) and opens the page for a symbol at the right anchor.

| Command | Description |
| --- | --- |
| `:QtDocs [query]` | Docs for `query`; without arguments, the symbol under the cursor or the visual selection |
| `:QtDocsVersions` | List the installed Qt documentation sets |
| `:QtDocsReindex` | Rebuild the symbol index (run it after installing new docs) |
| `:QtDocsBrowser` | Choose which terminal browser to use |

| Keymap | Action |
| --- | --- |
| `<leader>Qk` | Docs for the symbol under the cursor (normal) or the selection (visual) |
| `<leader>QK` | Prompt for a term |

A name is resolved by full name, then last segment, then shorter prefixes (`Qt::AlignLeft` -> `AlignLeft` -> `Qt`), then a substring search. In `qml` buffers, QML types are tried first (`TextArea` -> `QtQuick.Controls.TextArea`). When several pages match, you pick one from a list.

Options:

```lua
vim.g.qt_docs_viewer = "terminal" -- "terminal" (split on the right) or "browser" (system browser)
vim.g.qt_docs_browser = "w3m"     -- w3m, links, elinks or lynx; default: first one installed
```

Inside the `w3m` split: `j`/`k`/`h`/`l` to move, `Tab` for the next link, `Enter` to follow it, `B` to go back, `q` to quit, `Alt+h` to return to the code window without closing the docs.

## Requirements

- Neovim 0.10+
- Qt 5.15+ or 6.x
- CMake (recommended) or qmake
- Qt documentation (HTML and `.index` files) installed, from your distribution's Qt doc packages or the Qt installer's *Documentation* component
- Optional: `w3m` (or `links`, `elinks`, `lynx`) for the docs split, `clangd`, `qmlls`, `nvim-dap`

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "kastico/qtmancer.nvim",
  config = function()
    require("qt").setup()
  end,
}
```

## License

The upstream README states MIT, but the upstream repository does not include a `LICENSE` file yet. This fork will follow the upstream license once it is added.
