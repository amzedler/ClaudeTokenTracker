# Claude Token Tracker

A lightweight macOS menu bar app that tracks your Claude Code session costs and token usage over time.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## What it does

- Shows your **trailing 7-day cost** in the menu bar as plain text
- Click to see a **daily cost bar chart**, current session details, and a scrollable list of past sessions
- Each session row is expandable to show token breakdown (input, output, cache) and duration
- Tracks session history automatically — detects new sessions when cost resets or there's a >10 minute gap

## How it works

Claude Code's [status line](https://docs.anthropic.com/en/docs/claude-code) hook writes session data to `~/.claude/token-usage.json` after every assistant response. The menu bar app polls that file every 2 seconds and maintains a session history in `~/.claude/token-sessions.json` (up to 200 sessions).

### Data flow

```
Claude Code → statusline.sh hook → ~/.claude/token-usage.json → menu bar app
                                  → ~/.claude/token-sessions.json (history)
```

## Setup

### 1. Build the app

```bash
git clone https://github.com/amzedler/ClaudeTokenTracker.git
cd ClaudeTokenTracker
swift build -c release
```

### 2. Create the .app bundle

```bash
mkdir -p ClaudeTokenTracker.app/Contents/MacOS
cp .build/release/ClaudeTokenTracker ClaudeTokenTracker.app/Contents/MacOS/
```

The `Info.plist` is already included — it sets `LSUIElement` so the app lives in the menu bar only (no dock icon).

### 3. Install the status line hook

Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  }
}
```

Then copy the hook script to `~/.claude/statusline.sh`:

```bash
#!/bin/bash
input=$(cat)

DATA_FILE="$HOME/.claude/token-usage.json"
HISTORY_FILE="$HOME/.claude/token-sessions.json"

new_json=$(echo "$input" | jq '{
  model: (.model.display_name // "Claude"),
  input_tokens: (.context_window.total_input_tokens // 0),
  output_tokens: (.context_window.total_output_tokens // 0),
  cache_read: (.context_window.current_usage.cache_read_input_tokens // 0),
  cache_write: (.context_window.current_usage.cache_creation_input_tokens // 0),
  cost_usd: (.cost.total_cost_usd // 0),
  duration_ms: (.cost.total_duration_ms // 0),
  api_duration_ms: (.cost.total_api_duration_ms // 0),
  context_pct: (.context_window.used_percentage // 0),
  context_size: (.context_window.context_window_size // 0),
  updated_at: now
}')

new_cost=$(echo "$new_json" | jq -r '.cost_usd')
new_time=$(echo "$new_json" | jq -r '.updated_at')

is_new_session=false
if [ -f "$DATA_FILE" ]; then
  old_cost=$(jq -r '.cost_usd // 0' "$DATA_FILE" 2>/dev/null)
  old_time=$(jq -r '.updated_at // 0' "$DATA_FILE" 2>/dev/null)
  time_gap=$(echo "$new_time - $old_time" | bc 2>/dev/null || echo "0")
  if [ "$(echo "$new_cost < $old_cost - 0.001" | bc -l 2>/dev/null)" = "1" ] || \
     [ "$(echo "$time_gap > 600" | bc -l 2>/dev/null)" = "1" ]; then
    is_new_session=true
  fi
fi

if [ "$is_new_session" = true ] && [ -f "$DATA_FILE" ]; then
  old_data=$(cat "$DATA_FILE")
  old_cost_check=$(echo "$old_data" | jq -r '.cost_usd // 0')
  if [ "$(echo "$old_cost_check > 0" | bc -l 2>/dev/null)" = "1" ]; then
    if [ ! -f "$HISTORY_FILE" ] || ! jq -e 'type == "array"' "$HISTORY_FILE" >/dev/null 2>&1; then
      echo "[]" > "$HISTORY_FILE"
    fi
    jq --argjson session "$old_data" '. + [$session] | .[-200:]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && \
      mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
  fi
fi

if [ "$is_new_session" = true ] || [ ! -f "$DATA_FILE" ]; then
  new_json=$(echo "$new_json" | jq --arg t "$new_time" '. + {session_started: ($t | tonumber)}')
else
  started=$(jq -r '.session_started // 0' "$DATA_FILE" 2>/dev/null)
  new_json=$(echo "$new_json" | jq --arg t "$started" '. + {session_started: ($t | tonumber)}')
fi

echo "$new_json" > "$DATA_FILE"

# Compact output for Claude Code's inline status
seven_day_cost="0"
if [ -f "$HISTORY_FILE" ]; then
  cutoff=$(echo "$new_time - 604800" | bc)
  seven_day_cost=$(jq --arg c "$cutoff" '[.[] | select(.updated_at > ($c | tonumber)) | .cost_usd] | add // 0' "$HISTORY_FILE" 2>/dev/null || echo "0")
fi
total_7d=$(echo "$seven_day_cost + $new_cost" | bc -l 2>/dev/null || echo "$new_cost")
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
printf '7d:$%.2f  now:$%.2f  %s%%' "$total_7d" "$new_cost" "$pct"
```

Make it executable: `chmod +x ~/.claude/statusline.sh`

### 4. Launch

```bash
open ClaudeTokenTracker.app
```

To start on login: **System Settings > General > Login Items** and add the app.

## Requirements

- macOS 13+
- `jq` (for the status line hook): `brew install jq`
- Claude Code with status line support
