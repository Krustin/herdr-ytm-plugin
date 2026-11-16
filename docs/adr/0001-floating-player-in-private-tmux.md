# 0001. Floating player runs ytm in a private tmux server

Date: 2026-11-16
Status: accepted

## Context
ytm-player keeps its audio inside the TUI process. A plain herdr popup ends its
command when it closes, which would stop the music. The first implementation
followed herdr-cliamp: ytm in a detached, nested herdr session, with the popup
running `herdr session attach`.

In real use this failed: the nested herdr client loads the user's own herdr
config, so the float showed a second herdr UI (sidebar included) and swallowed
the outer prefix and commands. There was no obvious way to close it; pressing
`q` quit ytm, after which herdr kept spawning shell workspaces in the empty
session. It also required `allow_nested = true` in the user's config.

## Decision
Host ytm in a **private tmux server** (`tmux -L jloplaya`) with its own
`tmux.conf`: no status bar, no prefix, no tmux bindings except `ctrl+d` =
detach, mouse passed through to ytm. The herdr popup only runs
`tmux attach-session`. The `open` action toggles: with a client attached it
detaches it (hide), otherwise it starts the session if needed and opens the
popup. The session's only process is ytm, so quitting ytm ends the session and
closes the popup.

The hide key was first `ctrl+\`; it is barely typeable on a German Mac layout
(`\` = Option+Shift+7), so it became `ctrl+d`, which ytm does not bind.

## Consequences
- tmux becomes a dependency of the floating player (not of the control actions).
- No `allow_nested` needed; the user's own tmux server is never touched.
- Popups do not appear in `herdr pane list`, so "is the float open?" is answered
  by tmux (`list-clients`) plus the attach process (`pgrep`).
- `open` starts ytm — but only in this server, and never while another ytm runs.
