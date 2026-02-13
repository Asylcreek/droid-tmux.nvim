# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project uses Semantic Versioning.

## [0.2.1] - 2026-02-13

### Fixed
- Applied formatting fixes required by `stylua --check` in CI.

## [0.2.0] - 2026-02-13

### Added
- `:DroidStatus` command with live pane resolution details and last-send status.
- Integration tests for send entrypoints and status behavior.
- Bracketed paste send path tests for multiline fidelity and submit timing.

### Changed
- Droid pane auto-resolution now uses live detection only in the current tmux window.
- Detection now matches Droid by process command first, with pane title fallback for shell-wrapped Droid sessions.
- Prompt submission defaults to `submit_key = "Enter"` with `submit_delay_ms = 120` to improve reliability after paste.

### Removed
- Removed `:DroidPickPane` command and related keymap/implementation paths.
- Removed persisted pane selection (`@droid_pane`) behavior.

### Fixed
- Commands now consistently notify users when no Droid pane is available.
- Stale pane failures (pane closed after resolution) now return explicit user-visible errors.
- Focus and send flows now share consistent error handling and no longer fail silently.

## [0.1.2] - 2026-02-13

### Fixed
- Replaced Lua `goto` usage in diagnostics collection to keep CI linting/parsing compatible with Lua 5.1 tooling.

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
