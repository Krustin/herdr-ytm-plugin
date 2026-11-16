# 0002. Control ytm only through its CLI

Date: 2026-11-16
Status: accepted

## Context
ytm-player exposes a local IPC socket and a CLI (`ytm now`, `play`, `pause`,
`next`, `prev`, `like`, …) on top of it. A plugin could speak the socket
protocol directly, read ytm's state files, or launch ytm on demand.

## Decision
The plugin talks to ytm **only through the `ytm` CLI** and never reads or writes
ytm's config or data directory. Control actions never start ytm; only the
explicit `open` action may start it, inside the plugin's private tmux server
(see [ADR 0001](0001-floating-player-in-private-tmux.md)). The plugin makes no
network calls of its own and has no telemetry.

## Consequences
- The plugin depends on ytm's CLI output (JSON fields of `ytm now` and the
  English "not running" error text), which is not a documented, stable API.
  Mitigations: tested version stated in the README (2.2.0); an unknown error
  text falls back to a process-list check instead of assuming ytm runs.
- No coupling to ytm's IPC wire format, credentials or files.
- `like` changes the user's YouTube Music account; that network call is made by
  ytm, not by the plugin.
