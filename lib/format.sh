# shellcheck shell=bash
#
# Pure formatting helpers for JLoPlaya. No herdr, no ytm, no side effects, so
# tests can source this file and call the functions directly.
#
# Must stay compatible with macOS /bin/bash 3.2: herdr may run plugin commands
# with a minimal PATH where that is the only bash.

# Seconds -> m:ss, or h:mm:ss from one hour on. Accepts floats ("3.43").
hms() {
  local t=${1%%.*}
  case "$t" in ''|-*) t=0 ;; *[!0-9]*) printf '?'; return ;; esac
  if [ "$t" -ge 3600 ]; then
    printf '%d:%02d:%02d' $((t / 3600)) $((t % 3600 / 60)) $((t % 60))
  else
    printf '%d:%02d' $((t / 60)) $((t % 60))
  fi
}

# progress_bar POS DUR [WIDTH] -> "██████░░░░". Empty output when DUR is unknown.
progress_bar() {
  local pos=${1%%.*} dur=${2%%.*} width=${3:-10} filled i out=""
  case "$pos" in ''|-*|*[!0-9]*) pos=0 ;; esac
  case "$dur" in ''|-*|*[!0-9]*) return 0 ;; esac
  [ "$dur" -gt 0 ] || return 0
  [ "$pos" -le "$dur" ] || pos=$dur
  filled=$((pos * width / dur))
  i=0
  while [ "$i" -lt "$width" ]; do
    if [ "$i" -lt "$filled" ]; then out="${out}█"; else out="${out}░"; fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

state_icon() {
  if [ "$1" = "true" ]; then printf '▶'
  elif [ "$2" = "true" ]; then printf '⏸'
  else printf '■'
  fi
}

# format_now JSON
# Sets TOAST_TITLE and TOAST_BODY from a `ytm now` / `ytm status` response.
# Returns 1 (and sets nothing useful) when JSON is not valid JSON.
format_now() {
  local json=$1 fields playing paused title artist album pos dur like
  local progress bar headline body sep
  TOAST_TITLE=""
  TOAST_BODY=""

  printf '%s' "$json" | jq -e . >/dev/null 2>&1
  case $? in 0|1) ;; *) return 1 ;; esac   # 1 = valid but null/false

  if printf '%s' "$json" | jq -e '. == null or .track == null' >/dev/null 2>&1; then
    TOAST_TITLE="■ Nothing playing"
    TOAST_BODY="ytm is running, but no track is loaded"
    return 0
  fi

  # One jq call; fields joined by the ASCII unit separator, which (unlike tab)
  # is not IFS whitespace, so empty fields survive `read`.
  sep=$(printf '\037')
  fields=$(printf '%s' "$json" | jq -r '
    [ (.is_playing // false), (.is_paused // false),
      (.track.title // ""), (.track.artist // ""), (.track.album // ""),
      (.position // 0), (.duration // .track.duration // 0),
      (.track.likeStatus // "") ]
    | map(tostring | gsub("[\u001f\n\r\t]"; " ")) | join("\u001f")') || return 1
  IFS="$sep" read -r playing paused title artist album pos dur like <<EOF
$fields
EOF

  [ -n "$title" ] || title="(untitled)"
  headline=$title
  [ -n "$artist" ] && headline="$artist — $title"
  TOAST_TITLE="$(state_icon "$playing" "$paused") $headline"

  body=""
  if [ -n "$album" ] && [ "$album" != "$artist" ] && [ "$album" != "$title" ]; then body=$album; fi

  bar=$(progress_bar "$pos" "$dur" 10)
  if [ -n "$bar" ]; then
    progress="$(hms "$pos") / $(hms "$dur")  $bar"
  else
    progress=$(hms "$pos")
  fi
  body="${body:+$body
}$progress"

  case "$like" in
    LIKE) body="$body  ♥" ;;
    DISLIKE) body="$body  ✗" ;;
  esac
  TOAST_BODY=$body
  return 0
}
