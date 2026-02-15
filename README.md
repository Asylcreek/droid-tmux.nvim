# droid-tmux.nvim

Neovim bridge for sending context to a `droid` CLI running in a tmux pane.

## Why this exists

I needed a way to send context to my [Factory Droid](https://docs.factory.ai)
CLI without having to open a terminal in Neovim. [sidekick.nvim](https://github.com/folke/sidekick.nvim)
was the closest to my goal, but I disable mouse actions with
[hardtime.nvim](https://github.com/m4xshen/hardtime.nvim) and I love scrolling
to read agent output.

## Features

- Uses an external tmux pane (no Neovim terminal required)
- Per-window pane pinning for deterministic sends/focus
- Prompted sends for visual selections and current line
- Context commands for diff, diagnostics, workspace diagnostics, and quickfix
- Prompt templates with context variables

## Requirements

- Neovim 0.10+
- tmux
- `droid` running in a tmux pane

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

At minimum, pass `opts = {}` so lazy.nvim calls `setup()`:

```lua
{
  "asylcreek/droid-tmux.nvim",
  opts = {},
}
```

With custom options:

```lua
{
  "asylcreek/droid-tmux.nvim",
  opts = {
    submit_key = "Enter",
    submit_delay_ms = 120,
    keymaps = {
      ask = "<leader>aa",
      focus = "<leader>af",
      pick_pane = "<leader>as",
      visual = "<leader>av",
      line = "<leader>al",
      prompt = "<leader>ap",
      diff = "<leader>ad",
      diagnostics = "<leader>ax",
      diagnostics_all = "<leader>aX",
      quickfix = "<leader>aq",
    },
  },
}
```

### Without lazy.nvim

Make sure you call `setup()` yourself:

```lua
require("droid_tmux").setup({})
```

To pin a version in lazy.nvim:

```lua
{
  "asylcreek/droid-tmux.nvim",
  version = ">=0.1.0",
}
```

Or pin an exact release:

```lua
{
  "asylcreek/droid-tmux.nvim",
  version = "0.1.3",
}
```

## Keymaps

Keymaps are configured under `keymaps = { ... }`.

- Set a key to `false` to disable that mapping.
- Omit a key to keep its default mapping.

Example:

```lua
require("droid_tmux").setup({
  keymaps = {
    ask = "<leader>aa",
    pick_pane = "<leader>as",
    visual = "<leader>av",
    line = "<leader>al",
    prompt = "<leader>ap",
    diff = "<leader>ad",
    diagnostics = "<leader>ax",
    diagnostics_all = "<leader>aX",
    quickfix = "<leader>aq",
    focus = "<leader>af",
  },
})
```

## Commands

- `:DroidAsk [message]`
- `:DroidPrompt [template]`
- `:DroidFocus`
- `:DroidPickPane [pane_id]`
- `:DroidStatus`
- `:DroidSendBuffer [message]`
- `:DroidSendLine [message]`
- `:[range]DroidSendLines [message]`
- `:DroidSendDiff [message]`
- `:DroidSendDiagnostics [message]`
- `:DroidSendDiagnosticsAll [message]` (loaded non-gitignored buffers only)
- `:DroidSendQuickfix [message]`

## Prompt variables

- `{file}`
- `{diagnostics}`
- `{diagnostics_all}`
- `{quickfix}`
- `{diff}`

## Notes

- Pane selection is persisted per tmux window via `:DroidPickPane`.
- `:DroidSend*` and `:DroidFocus` automatically open the pane picker when no pane is pinned.

## Development

Run local CI checks:

```bash
just check
```

Format Lua files:

```bash
just fix
```

## References

- Factory Droid: [docs.factory.ai](https://docs.factory.ai)
- Inspired by:
  - [greggh/claude-code.nvim](https://github.com/greggh/claude-code.nvim)
  - [NickvanDyke/opencode.nvim](https://github.com/NickvanDyke/opencode.nvim)
  - [sourcegraph/amp.nvim](https://github.com/sourcegraph/amp.nvim)
  - [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim)
