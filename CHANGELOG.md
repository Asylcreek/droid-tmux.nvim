# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project uses Semantic Versioning.

## [0.1.1] - 2026-02-13

### Changed
- `:DroidSendDiagnosticsAll` now skips gitignored files and reports diagnostics from loaded non-gitignored buffers only.

## [0.1.0] - 2026-02-12

### Added
- Initial release of `droid-tmux.nvim`.
- Tmux-based Droid pane detection scoped to current tmux window.
- Commands:
  - `:DroidAsk`
  - `:DroidPrompt`
  - `:DroidFocus`
  - `:DroidPickPane`
  - `:DroidSendBuffer`
  - `:DroidSendLine`
  - `:DroidSendLines`
  - `:DroidSendDiff`
  - `:DroidSendDiagnostics`
  - `:DroidSendDiagnosticsAll`
  - `:DroidSendQuickfix`
- Prompt templates and variable expansion for file/diff/diagnostics/quickfix.
- Configurable keymaps via `setup({ keymaps = { ... } })`.
- Neovim help docs in `doc/droid-tmux.txt`.
