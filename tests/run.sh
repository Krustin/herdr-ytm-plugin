#!/usr/bin/env bash
# Test runner for JLoPlaya. No bats needed: `bash tests/run.sh`.
# Uses mock ytm/herdr binaries, never the real player.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
MOCK="$ROOT/tests/mock"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/jloplaya-test.XXXXXX")"
trap 'rm -rf "$WORK"; tmux -L "jloplaya-test-$$" kill-server 2>/dev/null' EXIT

# Run the plugin under macOS's stock bash 3.2 when present, to catch bashisms.
BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains '$2'" "$3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "not containing '$2'" "$3" ;; *) ok "$1" ;; esac; }

# ---- unit: lib/format.sh -----------------------------------------------------
# shellcheck source=../lib/format.sh
. "$ROOT/lib/format.sh"

eq "hms 0"            "0:00"    "$(hms 0)"
eq "hms float"        "0:03"    "$(hms 3.437)"
eq "hms minutes"      "3:53"    "$(hms 233.661)"
eq "hms hour"         "1:02:05" "$(hms 3725)"
eq "hms negative"     "0:00"    "$(hms -5)"
eq "hms garbage"      "?"       "$(hms abc)"
eq "bar empty"        "░░░░░░░░░░" "$(progress_bar 0 200)"
eq "bar half"         "█████░░░░░" "$(progress_bar 100 200)"
eq "bar overflow"     "██████████" "$(progress_bar 300 200)"
eq "bar no duration"  ""        "$(progress_bar 10 0)"

format_now "$(cat "$FIX/playing.json")"
eq "playing title"  "▶ Mariah Carey — Dreamlover" "$TOAST_TITLE"
eq "playing body"   "Music Box
0:03 / 3:53  ░░░░░░░░░░" "$TOAST_BODY"

format_now "$(cat "$FIX/paused_liked.json")"
eq "paused title w/ quotes" "⏸ Dr. Dre, Snoop Dogg — Nuthin' But A \"G\" Thang" "$TOAST_TITLE"
eq "paused body liked" "The Chronic
2:00 / 3:57  █████░░░░░  ♥" "$TOAST_BODY"

format_now "$(cat "$FIX/long_noalbum.json")"
eq "control chars flattened" "▶ DJ — Mix With Newline" "$TOAST_TITLE"
eq "album==artist hidden, no duration" "1:02:05" "$TOAST_BODY"

format_now "$(cat "$FIX/single.json")"
eq "album==title hidden" "0:00 / 3:45  ░░░░░░░░░░" "$TOAST_BODY"

format_now "null"
eq "null title" "■ Nothing playing" "$TOAST_TITLE"

if format_now "<html>"; then bad "invalid json rejected" "rc 1" "rc 0"; else ok "invalid json rejected"; fi
if format_now ""; then bad "empty rejected" "rc 1" "rc 0"; else ok "empty rejected"; fi

# ---- integration: ytm.sh with mocks -------------------------------------------
# run FIXTURE STATE ARGS... -> sets OUT, RC, YLOG (ytm calls), HLOG (herdr argv)
run() {
  local fixture=$1 state=$2; shift 2
  : > "$WORK/ytm.log"; : > "$WORK/herdr.log"
  OUT="$(MOCK_YTM_NOW="$FIX/$fixture" MOCK_YTM_STATE="$state" \
        MOCK_YTM_LOG="$WORK/ytm.log" MOCK_HERDR_LOG="$WORK/herdr.log" \
        HERDR_BIN_PATH="$MOCK/herdr" YTM_BIN="$MOCK/ytm" YTM_SETTLE=0 \
        HERDR_PLUGIN_CONFIG_DIR="$WORK/noconfig" YTM_TMUX_SOCKET="jloplaya-test-$$" \
        "$BASH_UNDER_TEST" "$ROOT/ytm.sh" "$@" 2>&1)"
  RC=$?
  YLOG="$(tr '\n' ' ' < "$WORK/ytm.log")"
  HLOG="$(cat "$WORK/herdr.log")"
}

run playing.json running now
eq  "now: rc"          0 "$RC"
has "now: toast cmd"   "[notification]
[show]
[▶ Mariah Carey — Dreamlover]
[--body]" "$HLOG"
has "now: position"    "[--position]
[top-right]
[--sound]
[none]" "$HLOG"
eq  "now: only reads"  "now " "$YLOG"

run playing.json running toggle
eq  "toggle playing -> pause" "now pause now " "$YLOG"

run paused_liked.json running toggle
eq  "toggle paused -> play"   "now play now " "$YLOG"

run null.json running toggle
eq  "toggle nothing loaded -> play" "now play now " "$YLOG"

run playing.json running next
eq  "next: calls"  "now next now " "$YLOG"
run playing.json running prev
eq  "prev: calls"  "now prev now " "$YLOG"

run playing.json down now
eq  "down: rc 0"       0 "$RC"
has "down: toast"      "[ytm not running]" "$HLOG"
eq  "down: no control call, never launches" "now " "$YLOG"
run playing.json down toggle
eq  "down toggle: no play/pause" "now " "$YLOG"
run playing.json down next
eq  "down next: no next" "now " "$YLOG"

run playing.json broken now
has "broken json toast" "[ytm: unexpected response]" "$HLOG"

run playing.json running like
eq  "like: calls"  "now like " "$YLOG"
has "like: toast"  "[♥ Liked]
[--body]
[Mariah Carey — Dreamlover]" "$HLOG"

run null.json running like
eq  "like nothing: no like call" "now " "$YLOG"
has "like nothing: toast" "[ytm: nothing to like]" "$HLOG"

: > "$WORK/ytm.log"; : > "$WORK/herdr.log"
OUT="$(MOCK_YTM_LIKE_FAIL=1 MOCK_YTM_NOW="$FIX/playing.json" MOCK_YTM_LOG="$WORK/ytm.log" \
      MOCK_HERDR_LOG="$WORK/herdr.log" HERDR_BIN_PATH="$MOCK/herdr" YTM_BIN="$MOCK/ytm" \
      YTM_SETTLE=0 HERDR_PLUGIN_CONFIG_DIR="$WORK/noconfig" "$BASH_UNDER_TEST" "$ROOT/ytm.sh" like 2>&1)"
has "like failure surfaced" "[ytm: like failed]
[--body]
[Error: like failed: 401]" "$(cat "$WORK/herdr.log")"

run playing.json running open
eq  "open: ytm elsewhere -> no start" "now " "$YLOG"
has "open: refuses second ytm" "[ytm already runs in another pane]" "$HLOG"
hasnt "open: no session server" "[server]" "$HLOG"

run playing.json running bogus
eq  "usage: rc 2" 2 "$RC"
has "usage: message" "usage:" "$OUT"

: > "$WORK/herdr.log"
OUT="$(MOCK_HERDR_LOG="$WORK/herdr.log" HERDR_BIN_PATH="$MOCK/herdr" YTM_BIN="$WORK/no-such-ytm" \
      HERDR_PLUGIN_CONFIG_DIR="$WORK/noconfig" "$BASH_UNDER_TEST" "$ROOT/ytm.sh" now 2>&1)"
eq  "missing ytm: rc 1" 1 "$?"
has "missing ytm: toast" "[JLoPlaya: ytm not found]" "$(cat "$WORK/herdr.log")"

# No herdr reachable: still prints, does not crash.
OUT="$(MOCK_YTM_NOW="$FIX/playing.json" HERDR_BIN_PATH="$WORK/no-such-herdr" YTM_BIN="$MOCK/ytm" \
      HERDR_PLUGIN_CONFIG_DIR="$WORK/noconfig" "$BASH_UNDER_TEST" "$ROOT/ytm.sh" now 2>&1)"
eq  "no herdr: stdout fallback" "▶ Mariah Carey — Dreamlover
Music Box
0:03 / 3:53  ░░░░░░░░░░" "$OUT"

# Minimal environment (as herdr may launch it): no PATH, config via config.sh.
mkdir -p "$WORK/cfg"
cat > "$WORK/cfg/config.sh" <<EOF
YTM_BIN="$MOCK/ytm"
YTM_SETTLE=0
YTM_TOAST_POSITION=bottom-left
export MOCK_YTM_NOW="$FIX/playing.json" MOCK_HERDR_LOG="$WORK/herdr.log"
EOF
: > "$WORK/herdr.log"
OUT="$(env -i HOME="$HOME" HERDR_BIN_PATH="$MOCK/herdr" HERDR_PLUGIN_CONFIG_DIR="$WORK/cfg" \
      /bin/bash "$ROOT/ytm.sh" now 2>&1)"
eq  "minimal env: rc" 0 "$?"
has "minimal env + config.sh position" "[bottom-left]" "$(cat "$WORK/herdr.log")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
