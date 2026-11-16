# CLAUDE.md — herdr-ytm-plugin (JLoPlaya)

herdr plugin (id `jloplaya`) that remote-controls ytm-player, a YouTube Music
TUI: play/pause, next/prev, like, now-playing toasts, and a floating player.
Public repo — never commit personal paths, account names or machine config.

## Where things live
- `herdr-plugin.toml` — manifest (actions + popup pane).
- `ytm.sh` — the single entry point for every action and the pane.
- `lib/format.sh` — pure JSON → toast formatting (no side effects).
- `tmux.conf` — private tmux server config for the floating player.
- `tests/run.sh` — test runner with mock `ytm`/`herdr` and JSON fixtures.
- `docs/` — [index](docs/README.md), [architecture](docs/ARCHITECTURE.md),
  [decisions](docs/adr/README.md). User-facing docs: [README.md](README.md).
- Work tracking: a local kanban board (not committed).

## Commands
- Test: `bash tests/run.sh` (must stay green; also run it with `/bin/bash` on macOS).
- Syntax: `bash -n ytm.sh lib/format.sh tests/run.sh`.
- Try locally: `herdr plugin link .`, then
  `herdr plugin action invoke <toggle|next|prev|now|like|open> --plugin jloplaya`
  and read results with `herdr plugin log list --plugin jloplaya`.

## Rules
- Talk to ytm **only through the `ytm` CLI**; never read or write ytm-player's
  config directory; no network calls, no telemetry (ADR 0002).
- Control actions **never start ytm**. Only `open` may, inside the private tmux
  server, and never while another ytm instance runs (ADR 0001).
- Bash 3.2 compatible (macOS stock bash): no `mapfile`, no associative arrays,
  use `${var}` before multibyte text.
- Pass values to `herdr` as argv, never as hand-built JSON.
- Missing tools (`jq`, `ytm`, `tmux`) are reported as a toast, never a crash.
- Tests must not touch the real player: they use mocks and their own tmux socket.
- Live tests against a running player: restore its state afterwards (e.g. `next`
  then `prev`), and ask before `like` — it changes the user's account.
