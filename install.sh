#!/bin/bash
# Install the Claude Code status line into ~/.claude.
#   ./install.sh          copy the script (re-run after `git pull` to update)
#   ./install.sh --link   symlink it to this repo instead (`git pull` updates it)
set -euo pipefail
cd "$(dirname "$0")"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

command -v jq >/dev/null || { echo "jq is required: apt install jq / brew install jq" >&2; exit 1; }
mkdir -p "$CLAUDE_DIR"

# 1. Script
if [ "${1:-}" = "--link" ]; then
  ln -sfn "$PWD/statusline.sh" "$CLAUDE_DIR/statusline.sh"
  echo "linked   $CLAUDE_DIR/statusline.sh -> $PWD/statusline.sh"
else
  rm -f "$CLAUDE_DIR/statusline.sh"  # drop an old symlink so we don't write into the repo
  install -m 755 statusline.sh "$CLAUDE_DIR/statusline.sh"
  echo "copied   $CLAUDE_DIR/statusline.sh"
fi

# 2. Config: never overwrite your own.
if [ -e "$CLAUDE_DIR/statusline.conf" ]; then
  echo "kept     $CLAUDE_DIR/statusline.conf (exists)"
else
  cp statusline.conf.example "$CLAUDE_DIR/statusline.conf"
  echo "created  $CLAUDE_DIR/statusline.conf"
fi

# 3. settings.json: set statusLine, keep everything else.
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.before-statusline"
tmp=$(mktemp)
jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh", refreshInterval: 60}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "updated  $SETTINGS (previous copy: $SETTINGS.before-statusline)"

echo
"$CLAUDE_DIR/statusline.sh" --demo
echo "Done. Restart Claude Code if the status line doesn't change."
