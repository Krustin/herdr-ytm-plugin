#!/usr/bin/env bash
#
# JLoPlaya — control a running ytm-player from herdr. One entry point for every
# plugin action:
#
#   ytm.sh toggle   play/pause
#   ytm.sh play     resume
#   ytm.sh pause    pause
#   ytm.sh next     next track
#   ytm.sh prev     previous track
#   ytm.sh now      now-playing toast
#   ytm.sh like     like the current track
#   ytm.sh open     show/hide the floating player (full ytm TUI in private tmux)
#   ytm.sh attach   attach to it (run by the popup pane)
#
# Everything goes through the `ytm` CLI, which talks to the TUI over its local
# IPC socket. The only place that ever starts ytm is `open`, and only inside
# the plugin's private tmux server, and never while ytm already runs elsewhere.
# Nothing here reads or writes ~/.config/ytm-player/ or makes network calls.
#
# Requires: herdr, ytm (ytm-player >= 2.2), jq; tmux for the floating player.
set -uo pipefail

# herdr runs plugin commands with a minimal environment; make sure the usual
# install locations are searchable (appended, so the caller's PATH wins).
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin /usr/bin /bin; do
  case ":${PATH:-}:" in *":$d:"*) ;; *) PATH="${PATH:+$PATH:}$d" ;; esac
done
export PATH

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
PLUGIN_ID="jloplaya"
PLUGIN_NAME="JLoPlaya"

# ---- configuration ----------------------------------------------------------
# Optional overrides in "$(herdr plugin config-dir jloplaya)/config.sh".
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/$PLUGIN_ID}"
# shellcheck source=/dev/null
[ -f "$CONFIG_DIR/config.sh" ] && . "$CONFIG_DIR/config.sh"

YTM_BIN="${YTM_BIN:-ytm}"
TOAST_POSITION="${YTM_TOAST_POSITION:-top-right}"
# Seconds to wait after a transport command so the toast shows the new state.
SETTLE="${YTM_SETTLE:-0.4}"
HERDR="${HERDR_BIN_PATH:-herdr}"

# shellcheck source=lib/format.sh
. "$SELF_DIR/lib/format.sh"

# ---- output -----------------------------------------------------------------
# Always echo to stdout (lands in `herdr plugin log` and in a terminal when run
# by hand); additionally raise a herdr toast when herdr is reachable.
toast() {
  printf '%s\n%s\n' "$1" "$2"
  if command -v "$HERDR" >/dev/null 2>&1; then
    "$HERDR" notification show "$1" --body "$2" \
      --position "$TOAST_POSITION" --sound none >/dev/null 2>&1 || true
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  toast "$PLUGIN_NAME: $2 not found" "Install $2 or set its path in $CONFIG_DIR/config.sh"
  exit 1
}

# ---- ytm --------------------------------------------------------------------
YTM_OUT=""
YTM_ERR=""

# run_ytm ARGS... -> sets YTM_OUT, YTM_ERR; returns ytm's exit code.
run_ytm() {
  local errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/jloplaya.XXXXXX")" || errf=/dev/null
  YTM_OUT="$("$YTM_BIN" "$@" 2>"$errf")"
  rc=$?
  YTM_ERR=""
  if [ "$errf" != /dev/null ]; then
    YTM_ERR="$(head -n 1 "$errf")"
    rm -f "$errf"
  fi
  return "$rc"
}

# Report a failed ytm call. "Not running" gets its own, friendlier toast.
report_failure() {
  case "$YTM_ERR" in
    *"not running"*|*"not responding"*)
      toast "ytm not running" "Start ytm-player in a pane first (this plugin never starts it)" ;;
    *)
      toast "ytm: $1 failed" "${YTM_ERR:-unknown error}" ;;
  esac
}

# Fetch `ytm now` into NOW_JSON. Returns 1 after reporting when unavailable.
NOW_JSON=""
fetch_now() {
  if ! run_ytm now; then
    report_failure now
    return 1
  fi
  NOW_JSON=$YTM_OUT
  return 0
}

show_now() {
  fetch_now || return 0
  if ! format_now "$NOW_JSON"; then
    toast "ytm: unexpected response" "$(printf '%s' "$NOW_JSON" | head -c 120)"
    return 0
  fi
  toast "$TOAST_TITLE" "$TOAST_BODY"
}

# transport CMD: only against a running player, then show the new state.
transport() {
  fetch_now || return 0
  if ! run_ytm "$1"; then
    report_failure "$1"
    return 0
  fi
  sleep "$SETTLE"
  show_now
}

toggle() {
  local playing
  fetch_now || return 0
  playing="$(printf '%s' "$NOW_JSON" | jq -r 'if type == "object" then (.is_playing // false) else false end' 2>/dev/null)"
  if [ "$playing" = "true" ]; then
    run_ytm pause || { report_failure pause; return 0; }
  else
    run_ytm play || { report_failure play; return 0; }
  fi
  sleep "$SETTLE"
  show_now
}

like() {
  fetch_now || return 0
  if ! format_now "$NOW_JSON" || [ "$TOAST_TITLE" = "■ Nothing playing" ]; then
    toast "ytm: nothing to like" "No track is loaded"
    return 0
  fi
  local what
  what="$(printf '%s' "$NOW_JSON" | jq -r '[.track.artist, .track.title] | map(select(. != null and . != "")) | join(" — ")')"
  if ! run_ytm like; then
    report_failure like
    return 0
  fi
  toast "♥ Liked" "$what"
}

# ---- floating player ----------------------------------------------------------
# The full ytm TUI runs inside a PRIVATE tmux server (socket name "jloplaya",
# own config, no status bar, no prefix). The herdr popup pane only attaches a
# tmux client to it, so hiding the popup (ctrl+d inside, or the open key)
# ends just that client and playback continues.
#
# Why tmux and not a nested herdr session: a nested herdr client loads the
# user's herdr config (sidebar, prefix) and swallows the outer prefix. tmux with
# this config is invisible apart from ytm itself.
#
# Starting rule: ytm is started only by the explicit `open` action, only inside
# that tmux server, and never while another ytm instance is running anywhere.

ytm_is_running() {
  run_ytm now && return 0
  case "$YTM_ERR" in *"not running"*|*"not responding"*) return 1 ;; esac
  return 0   # some other error: a TUI answered, so treat it as running
}

# tmux against the private server only; never the user's own tmux.
tm() { env -u TMUX tmux -L "$TMUX_SOCKET" -f "$TMUX_CONF" "$@"; }

float_session_up() { tm has-session -t "=$TMUX_SESSION" 2>/dev/null; }
float_clients()    { tm list-clients -F '#{client_name}' 2>/dev/null; }
# Second opinion: the popup's process is a tmux client attached to our socket.
float_attach_pids() { pgrep -f "tmux -L $TMUX_SOCKET .*attach-session" 2>/dev/null; }

# Make sure the tmux session runs ytm. Returns 1 after reporting on failure.
ensure_player() {
  local i ytm_path
  float_session_up && return 0

  if ytm_is_running; then
    toast "ytm already runs in another pane" \
      "Only one ytm can run. Quit it there (q), then open the float again."
    return 1
  fi

  # The session's only process is ytm: quitting ytm ends the session, so
  # nothing is left behind and an attached popup closes with it.
  ytm_path="$(command -v "$YTM_BIN")"
  LANG="${LANG:-en_US.UTF-8}" tm new-session -d -s "$TMUX_SESSION" -x 160 -y 45 \
    "exec $(printf '%q' "$ytm_path")" 2>/dev/null || {
    toast "ytm float" "Could not start tmux session '$TMUX_SESSION'"; return 1; }

  for i in $(seq 1 40); do       # up to ~20 s for ytm startup
    ytm_is_running && return 0
    float_session_up || break    # ytm exited right away
    sleep 0.5
  done
  toast "ytm float" "ytm did not come up (tmux session '$TMUX_SESSION')"
  return 1
}

# The same key opens and hides the float. Hiding detaches only the tmux client
# (the popup's process), never the session, so playback continues.
open_float() {
  local clients pids
  clients="$(float_clients)"; pids="$(float_attach_pids)"
  printf 'float: clients=[%s] attach_pids=[%s]\n' "$(echo $clients)" "$(echo $pids)"
  if [ -n "$clients" ] || [ -n "$pids" ]; then
    tm detach-client -a -s "=$TMUX_SESSION" 2>/dev/null
    tm detach-client -s "=$TMUX_SESSION" 2>/dev/null
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill $pids 2>/dev/null
    toast "ytm hidden" "Music keeps playing. Same key brings it back."
    return 0
  fi
  ensure_player || return 0
  # An action has no terminal of its own, so never attach here: hand off to
  # the plugin's popup pane, which runs `ytm.sh attach`.
  if ! "$HERDR" plugin pane open --plugin "$PLUGIN_ID" --entrypoint player \
       --placement popup --width "$FLOAT_WIDTH" --height "$FLOAT_HEIGHT" --focus >/dev/null 2>&1; then
    toast "ytm float" "Could not open the player pane"
    return 0
  fi
  toast "ytm float" "Hide: ctrl+d (music keeps playing). q in ytm quits ytm."
}

# ---- entry point ------------------------------------------------------------
TMUX_SOCKET="${YTM_TMUX_SOCKET:-jloplaya}"
TMUX_SESSION="ytm"
TMUX_CONF="$SELF_DIR/tmux.conf"
[ -f "$CONFIG_DIR/tmux.conf" ] && TMUX_CONF="$CONFIG_DIR/tmux.conf"
FLOAT_WIDTH="${YTM_FLOAT_WIDTH:-70%}"
FLOAT_HEIGHT="${YTM_FLOAT_HEIGHT:-60%}"

cmd="${1:-}"
case "$cmd" in
  toggle|play|pause|next|prev|now|like|open) ;;
  attach)
    # Runs inside the popup pane. When the session is gone (ytm quit), say so
    # instead of flashing an empty popup.
    if ! float_session_up; then
      printf 'ytm float is not running. Use the open key to start it.\n'
      sleep 2; exit 0
    fi
    exec env -u TMUX tmux -L "$TMUX_SOCKET" -f "$TMUX_CONF" attach-session -t "=$TMUX_SESSION" ;;
  *)
    printf 'usage: ytm.sh {toggle|play|pause|next|prev|now|like|open|attach}\n' >&2
    exit 2 ;;
esac

need jq jq
need "$YTM_BIN" ytm

case "$cmd" in
  open) need "$HERDR" herdr; need tmux tmux; open_float ;;
  toggle) toggle ;;
  now) show_now ;;
  like) like ;;
  *) transport "$cmd" ;;
esac
exit 0
