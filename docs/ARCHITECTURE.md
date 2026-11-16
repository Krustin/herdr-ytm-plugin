# Architecture

## Shape
A small Bash plugin with **one entry point**: every herdr action and the popup
pane run `bash ytm.sh <subcommand>`. Pure formatting lives in a separate,
side-effect-free library so it can be unit-tested without herdr or ytm.

## Boundaries & dependency direction

| Part | Owns | Depends on |
|---|---|---|
| `herdr-plugin.toml` | Manifest: actions `toggle next prev now like open`, pane `player` | `ytm.sh` |
| `ytm.sh` | Dispatch, ytm calls, toasts, error handling, floating player | `lib/format.sh`, `ytm` CLI, `herdr` CLI, `tmux`, `jq` |
| `lib/format.sh` | `ytm now` JSON → toast title/body (`hms`, `progress_bar`, `format_now`) | `jq` only |
| `tmux.conf` | Config of the private tmux server that hosts the floating player | — |
| `tests/` | `run.sh` + mock `ytm`/`herdr` + JSON fixtures | `ytm.sh`, `lib/format.sh` |

Dependencies point one way: manifest → `ytm.sh` → `lib/format.sh`. No cycles.
External tools are only ever called, never vendored.

## Key patterns
- **ytm only through its CLI.** `ytm now|play|pause|next|prev|like` over ytm's
  local IPC socket. No direct socket protocol, no reading of ytm's config or
  data files. See [ADR 0002](adr/0002-control-ytm-only-through-its-cli.md).
- **Toasts via `herdr notification show`**, values passed as argv — never as
  hand-built JSON, so titles with quotes cannot break anything. Every toast is
  also printed to stdout, which lands in `herdr plugin log`.
- **Floating player = private tmux server** (`tmux -L jloplaya`, own config, no
  status bar, no prefix, `ctrl+d` detaches). The herdr popup only attaches a
  client. See [ADR 0001](adr/0001-floating-player-in-private-tmux.md).
- **Minimal environment.** herdr may start actions with a bare PATH; `ytm.sh`
  appends the usual install locations itself. Code stays compatible with macOS'
  stock bash 3.2.
- **User overrides** via `config.sh` (and optionally `tmux.conf`) in
  `herdr plugin config-dir jloplaya`, sourced before anything is derived.

## Entry points
- Actions: `herdr-plugin.toml` → `bash ytm.sh {toggle|next|prev|now|like|open}`.
  Control actions read `ytm now`, run the transport command, wait
  `YTM_SETTLE`, then toast the fresh state.
- `open`: if a tmux client is attached → detach it (hide). Otherwise ensure the
  tmux session runs ytm (refusing when ytm already runs elsewhere), then
  `herdr plugin pane open --entrypoint player --placement popup`.
- Pane `player`: `bash ytm.sh attach` → `tmux attach-session` in the popup.
