#!/bin/bash
# Status line: model, effort, context window use, 5-hour / 7-day plan usage.
# Preview sample states: ~/.claude/statusline.sh --demo
# jq: from PATH, else common install locations (Claude Code may run with a minimal PATH).
JQ=$(command -v jq)
for c in /home/linuxbrew/.linuxbrew/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do
  [ -n "$JQ" ] && break; [ -x "$c" ] && JQ=$c
done
[ "$1" != "--demo" ] && [ -z "$JQ" ] && { echo "statusline: jq not found"; exit 0; }
CACHE="$HOME/.claude/statusline-cache"

# ---------- colors (256-color) ----------
E=$'\e'; R="$E[0m"; DIM="$E[2m"; B="$E[1m"
fg() { printf '%s[38;5;%sm' "$E" "$1"; }
bg() { printf '%s[48;5;%sm' "$E" "$1"; }
SEP="$(fg 240)│$R"

# ---------- settings (override in ~/.claude/statusline.conf) ----------
# Thresholds are "yellow orange red" (green below the first).
CTX_THRESHOLDS="50 65 80"      # context window used, % of the window
CTX_TOKEN_THRESHOLDS="150000 250000 400000"  # ...and in tokens; the worse of the two wins (matters on 1M windows)
LIMIT_COLOR_MODE=pace          # 5h/7d bar color: pace | usage
USAGE_THRESHOLDS="50 75 90"    # usage mode: % of the window used
PACE_THRESHOLDS="100 120 150"  # pace mode: projected % used by reset at the current rate
PACE_MIN_USED=20               # pace mode: below this % used it's too early to judge -> green
PACE_HARD_RED=90               # pace mode: at or above this % used -> red regardless of pace
CONF="$HOME/.claude/statusline.conf"
[ -r "$CONF" ] && . "$CONF"

# Color for a value against "yellow orange red" thresholds (empty = unknown).
level_color() {
  local v=$1 y o r
  read -r y o r <<< "$2"
  [ -z "$v" ] && { fg 240; return; }
  if   [ "$v" -ge "$r" ]; then fg 196
  elif [ "$v" -ge "$o" ]; then fg 208
  elif [ "$v" -ge "$y" ]; then fg 220
  else fg 114; fi
}

# Severity 0-3 of a value against "yellow orange red" thresholds.
level() {
  local v=$1 y o r
  read -r y o r <<< "$2"
  if [ "$v" -ge "$r" ]; then echo 3; elif [ "$v" -ge "$o" ]; then echo 2
  elif [ "$v" -ge "$y" ]; then echo 1; else echo 0; fi
}

# Context color: worse of the % level and the absolute-token level.
ctx_color() {
  local pct=$1 size=${2:-200000} a b
  a=$(level "$pct" "$CTX_THRESHOLDS")
  b=$(level $(( pct * size / 100 )) "$CTX_TOKEN_THRESHOLDS")
  [ "$b" -gt "$a" ] && a=$b
  case $a in 3) fg 196 ;; 2) fg 208 ;; 1) fg 220 ;; *) fg 114 ;; esac
}

# Color for a rate-limit window: used %, resets_at, window length in seconds.
limit_color() {
  local used=$1 at=$2 win=$3 left elapsed proj
  if [ "$LIMIT_COLOR_MODE" != pace ] || [ -z "$used" ] || [ -z "$at" ]; then
    level_color "$used" "$USAGE_THRESHOLDS"; return
  fi
  [ "$used" -ge "$PACE_HARD_RED" ] && { fg 196; return; }
  [ "$used" -lt "$PACE_MIN_USED" ] && { fg 114; return; }
  left=$(( at - $(date +%s) )); elapsed=$(( win - left ))
  [ "$elapsed" -lt 1 ] && elapsed=1
  proj=$(( used * win / elapsed ))   # % used by reset if the current rate holds
  level_color "$proj" "$PACE_THRESHOLDS"
}

# Effort: glyph + color, low -> max.
effort_style() {
  case $1 in
    low)    EG='○'; EC=$(fg 220)$B ;;
    medium) EG='◑'; EC=$(fg 114)$B ;;
    high)   EG='●'; EC=$(fg 153)$B ;;
    xhigh)  EG='◉'; EC=$(fg 147)$B ;;
    max)    EG='✦'; EC=$(fg 203)$B ;;
    *)      EG='·'; EC=$(fg 240) ;;
  esac
}

# Effort word, padded to 6; "max" gets a static rainbow like /effort.
effort_word() {
  if [ "$1" = max ]; then
    printf '%s%sm%sa%sx%s   ' "$B" "$(fg 203)" "$(fg 215)" "$(fg 221)" "$R"
  else
    printf '%s%-6s%s' "$EC" "${1:---}" "$R"
  fi
}

# Fixed-width "NNN%" (or " --%").
pct_text() { [ -z "$1" ] && printf ' --%%' || printf '%3d%%' "$1"; }

# Fixed-width (5 chars) time until reset: "4h59m" / "6d23h" / "   --".
until_text() {
  local t=$1 now d
  [ -z "$t" ] && { printf '   --'; return; }
  now=$(date +%s); d=$(( t - now ))
  [ "$d" -le 0 ] && { printf '   --'; return; }
  if [ "$d" -ge 86400 ]; then printf '%dd%02dh' $((d/86400)) $((d%86400/3600))
  else printf '%dh%02dm' $((d/3600)) $((d%3600/60)); fi | awk '{printf "%5s", $0}'
}

# 8-cell bar.
bar() {
  local p=${1:-0} n i out=""
  n=$(( (p * 8 + 50) / 100 )); [ "$n" -gt 8 ] && n=8
  for ((i=0;i<8;i++)); do [ $i -lt $n ] && out+="▰" || out+="▱"; done
  printf '%s' "$out"
}

render() {
  # Inputs: MODEL EFFORT CTX CTX_SIZE FIVE FIVE_AT WEEK WEEK_AT STALE
  local model c5 c7 cc dimrl=""
  model=$(printf '%-10.10s' "${MODEL:---}")
  effort_style "$EFFORT"
  cc=$(ctx_color "$CTX" "$CTX_SIZE")
  c5=$(limit_color "$FIVE" "$FIVE_AT" 18000)
  c7=$(limit_color "$WEEK" "$WEEK_AT" 604800)
  [ -n "$STALE" ] && dimrl="$DIM"   # cached values from an earlier session

  printf '%s%s%s %s%s%s %s %s ctx %s%s %s%s %s 5h %s%s%s %s%s %s↻ %s%s %s 7d %s%s%s %s%s %s↻ %s%s' \
    "$B" "$model" "$R" "$EC" "$EG" "$R" "$(effort_word "$EFFORT")" "$SEP" \
    "$cc" "$(bar "$CTX")" "$(pct_text "$CTX")" "$R" "$SEP" \
    "$dimrl" "$c5" "$(bar "$FIVE")" "$(pct_text "$FIVE")" "$R" "$(fg 244)" "$(until_text "$FIVE_AT")" "$R" "$SEP" \
    "$dimrl" "$c7" "$(bar "$WEEK")" "$(pct_text "$WEEK")" "$R" "$(fg 244)" "$(until_text "$WEEK_AT")" "$R"
  printf '\n'
}

if [ "$1" = "--demo" ]; then
  now=$(date +%s)
  for LIMIT_COLOR_MODE in pace usage; do
    printf '\n  -- 5h/7d colors: %s --\n' "$LIMIT_COLOR_MODE"
    MODEL="Opus 5.5" EFFORT=medium CTX=4 FIVE="" WEEK="" FIVE_AT="" WEEK_AT="" STALE="" render
    MODEL="Opus 5.5" EFFORT=low    CTX=12 FIVE=15 FIVE_AT=$((now+16200)) WEEK=21 WEEK_AT=$((now+400000)) STALE=1 render
    MODEL="Sonnet 5.5" EFFORT=high CTX=47 FIVE=40 FIVE_AT=$((now+14400)) WEEK=30 WEEK_AT=$((now+500000)) STALE="" render
    MODEL="Opus 5.5" EFFORT=xhigh  CTX=81 FIVE=60 FIVE_AT=$((now+1800)) WEEK=55 WEEK_AT=$((now+250000)) STALE="" render
    MODEL="Opus 5.5" EFFORT=high   CTX=30 CTX_SIZE=1000000 FIVE=45 FIVE_AT=$((now+3600)) WEEK=40 WEEK_AT=$((now+120000)) STALE="" render
    MODEL="Opus 5.5" EFFORT=xhigh  CTX=62 FIVE=78 FIVE_AT=$((now+600)) WEEK=80 WEEK_AT=$((now+100000)) STALE="" render
    MODEL="Fable 5.1" EFFORT=max   CTX=100 FIVE=93 FIVE_AT=$((now+600)) WEEK=95 WEEK_AT=$((now+4000)) STALE="" render
  done
  echo; exit 0
fi

# ---------- real input ----------
IFS=$'\x1f' read -r MODEL EFFORT CTX CTX_SIZE FIVE FIVE_AT WEEK WEEK_AT < <(
  $JQ -r '[ .model.display_name // "",
            .effort.level // "",
            (.context_window.used_percentage // 0 | floor),
            .context_window.context_window_size // 200000,
            (.rate_limits.five_hour.used_percentage // "" | if . == "" then . else round end),
            .rate_limits.five_hour.resets_at // "",
            (.rate_limits.seven_day.used_percentage // "" | if . == "" then . else round end),
            .rate_limits.seven_day.resets_at // ""
          ] | map(tostring) | join("\u001f")')
STALE=""
now=$(date +%s)
if [ -n "$FIVE$WEEK" ]; then
  # Fresh reading: remember it for the next session's first seconds.
  printf '%s %s %s %s\n' "${FIVE:--}" "${FIVE_AT:--}" "${WEEK:--}" "${WEEK_AT:--}" > "$CACHE.$$" && mv "$CACHE.$$" "$CACHE"
elif [ -r "$CACHE" ]; then
  # No reading yet this session: show the last known one, dimmed.
  read -r FIVE FIVE_AT WEEK WEEK_AT < "$CACHE"
  for v in FIVE FIVE_AT WEEK WEEK_AT; do [ "${!v}" = "-" ] && printf -v "$v" ''; done
  # A window that has reset since is back to 0.
  [ -n "$FIVE_AT" ] && [ "$FIVE_AT" -le "$now" ] && { FIVE=0; FIVE_AT=""; }
  [ -n "$WEEK_AT" ] && [ "$WEEK_AT" -le "$now" ] && { WEEK=0; WEEK_AT=""; }
  STALE=1
fi
render
