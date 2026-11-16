# JLoPlaya — ytm-player for herdr

Control a running [ytm-player](https://github.com/peternaame-boop/ytm-player)
(YouTube Music in the terminal) from any [herdr](https://herdr.dev) workspace:
play/pause, skip, like, and a now-playing toast.

```
▶ Mariah Carey — Dreamlover
Music Box
1:23 / 3:54  ███░░░░░░░  ♥
```

The control actions only talk to an **already running** ytm over its local IPC
socket, via the `ytm` CLI. Only the floating player (`open`) ever starts ytm,
and only when none runs yet. The plugin never reads or writes
`~/.config/ytm-player/`, makes no network calls of its own and has no telemetry.
(`like` asks ytm to like the track; ytm then talks to YouTube Music itself.)

## Requirements

- herdr ≥ 0.8.0 (tested with 0.9.5 only), macOS or Linux
- ytm-player ≥ 2.2 (`ytm` on PATH, e.g. `~/.local/bin/ytm` via pipx)
- `jq`
- bash (macOS' stock bash 3.2 is fine)
- tmux, only for the floating player

## Installation

```sh
herdr plugin install Krustin/herdr-ytm-plugin
herdr plugin action list --plugin jloplaya
```

For local development, clone the repo and link it instead:

```sh
git clone https://github.com/Krustin/herdr-ytm-plugin
cd herdr-ytm-plugin
herdr plugin link .
```

Then start ytm-player in any pane (`ytm`) and try:

```sh
herdr plugin action invoke now --plugin jloplaya
```

## Actions

| Action | Qualified name | What it does |
|---|---|---|
| `toggle` | `jloplaya.toggle` | Pause when playing, resume otherwise; toast shows the new state |
| `next` | `jloplaya.next` | Next track + toast |
| `prev` | `jloplaya.prev` | Previous track (or restart of the current one, as ytm decides) + toast |
| `now` | `jloplaya.now` | Toast: state icon, artist — title, album, progress, ♥ if liked |
| `like` | `jloplaya.like` | Like the current track |
| `open` | `jloplaya.open` | Show/hide the floating ytm player (see below) |

## Floating player

The `open` action shows the full ytm TUI as a floating popup (70% × 60%).
ytm lives in a private tmux server (`tmux -L jloplaya`, config `tmux.conf`: no
status bar, no prefix, no tmux keys) and the popup only attaches to it:

- **Hide:** `ctrl+d` inside the float, or press the `open` key again. The music
  keeps playing. Every other key goes to ytm.
- **Show again:** the `open` key.
- **`q` inside ytm** quits ytm itself (music stops). The tmux session ends with
  it, so nothing is left behind and the popup closes.
- `open` only starts ytm when **no ytm runs anywhere**. If you already run ytm
  in a normal pane, it shows a toast and does nothing; quit that one first.
- ytm's own `resume_on_launch` restores the queue but may not resume playback;
  press play in ytm.
- Requires `tmux` (any recent version). It never touches your own tmux server.

## Keybindings

herdr plugins cannot declare keybindings. Add your own to herdr's `config.toml`
(usually `~/.config/herdr/config.toml`), then run `herdr server reload-config`:

```toml
[[keys.command]]
key = "prefix+y"
type = "plugin_action"
command = "jloplaya.toggle"
description = "ytm: play/pause"

[[keys.command]]
key = "prefix+u"
type = "plugin_action"
command = "jloplaya.next"
description = "ytm: next track"

[[keys.command]]
key = "prefix+shift+u"
type = "plugin_action"
command = "jloplaya.prev"
description = "ytm: previous track"

[[keys.command]]
key = "prefix+i"
type = "plugin_action"
command = "jloplaya.now"
description = "ytm: now playing"

[[keys.command]]
key = "prefix+shift+l"
type = "plugin_action"
command = "jloplaya.like"
description = "ytm: like track"

[[keys.command]]
key = "prefix+shift+y"
type = "plugin_action"
command = "jloplaya.open"
description = "ytm: floating player (show/hide)"
```

These keys are unbound in herdr 0.9.5's defaults. Pick others if they collide
with your own bindings. Avoid `prefix+alt+…` chords on macOS: iTerm often
swallows them (they only work in profiles where Option sends Esc+).

## Configuration (optional)

Create `config.sh` in the plugin's config directory
(`herdr plugin config-dir jloplaya`). It is sourced by the script:

```sh
YTM_BIN="$HOME/.local/bin/ytm"   # path to ytm, if it is not on PATH
YTM_TOAST_POSITION="bottom-right" # top-left | top-right | bottom-left | bottom-right
YTM_SETTLE=0.4                    # seconds to wait before reading the new state
YTM_FLOAT_WIDTH="70%"             # floating player size (cells or percent)
YTM_FLOAT_HEIGHT="60%"
```

## Troubleshooting

- **"ytm not running"** — start ytm-player in a pane (`ytm`) or use the
  floating player. The control actions never start ytm themselves. `ytm now`
  in a shell should print JSON.
- **"ytm not found" / "jq not found"** — herdr runs plugins with a minimal
  environment. The script adds `~/.local/bin`, `/opt/homebrew/bin`,
  `/usr/local/bin` to PATH; anything elsewhere needs `YTM_BIN` in `config.sh`.
- **No toast appears** — check the output of the last runs:
  `herdr plugin log list --plugin jloplaya` (every run also prints the toast
  text to stdout, so it shows up there).
- **Key does nothing** — the `command` must be the qualified name
  (`jloplaya.toggle`), and the config must be reloaded.
- **Can't close the float** — `ctrl+d` inside it. From any shell:
  `tmux -L jloplaya detach-client -s ytm` hides it too (music keeps playing).
- **Stop the float player entirely** — `q` in ytm, or
  `tmux -L jloplaya kill-server`.

## Development

```sh
bash tests/run.sh   # mocked ytm + herdr, never touches the real player
```

## License

MIT, see [LICENSE](LICENSE).
