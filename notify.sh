#!/bin/bash
# Claude Code notification hook for macOS
# Sends native notifications with tmux session/window context.
#
# Usage: Called by Claude Code hooks with JSON on stdin.
#   notify.sh needs_input   — Claude needs you to approve something
#   notify.sh done           — Claude finished and is idle

set -euo pipefail

NOTIFY_TYPE="${1:-done}"

# Read hook JSON from stdin (Claude Code pipes event data)
INPUT=$(cat)

# --- Skip notification if user is already viewing this session ---
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION_ATTACHED=$(tmux display-message -t "$TMUX_PANE" -p '#{session_attached}' 2>/dev/null || echo "0")
    PANE_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null || echo "0")
    WINDOW_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{window_active}' 2>/dev/null || echo "0")
    if [ "$SESSION_ATTACHED" != "0" ] && [ "$PANE_ACTIVE" = "1" ] && [ "$WINDOW_ACTIVE" = "1" ]; then
        FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
        FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')
        case "$FRONTMOST_LOWER" in
            terminal|iterm2|alacritty|kitty|wezterm|ghostty)
                exit 0
                ;;
        esac
    fi
fi

# --- Notification type ---
if [ "$NOTIFY_TYPE" = "needs_input" ]; then
    TITLE="Claude Code — Needs Input"
    BODY="Claude is waiting for your input"
    SOUND="Ping"
else
    TITLE="Claude Code — Done"
    BODY="Claude has finished and is awaiting further instructions"
    SOUND="Glass"
fi

# --- tmux context (session, window number, window name) ---
TMUX_INFO=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null || echo "")
    WIN_INDEX=$(tmux display-message -t "$TMUX_PANE" -p '#I' 2>/dev/null || echo "")
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null || echo "")
    if [ -n "$SESSION" ]; then
        TMUX_INFO="${SESSION}"
        if [ -n "$WIN_INDEX" ] && [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} w${WIN_INDEX} > ${WINDOW}"
        elif [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} > ${WINDOW}"
        fi
    fi
fi

# --- Click-to-focus: detect terminal bundle ID ---
# __CFBundleIdentifier is set by macOS for GUI apps — it's already the bundle ID.
# Falls back to mapping TERM_PROGRAM for non-GUI-launched terminals.
TERM_BUNDLE_ID="${__CFBundleIdentifier:-}"
if [ -z "$TERM_BUNDLE_ID" ]; then
    TERM_PROG="${TERM_PROGRAM:-}"
    if [ "$TERM_PROG" = "tmux" ] && [ -n "${TMUX:-}" ]; then
        TERM_PROG=$(tmux show-environment TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || echo "")
    fi
    case "$TERM_PROG" in
        Apple_Terminal) TERM_BUNDLE_ID="com.apple.Terminal" ;;
        iTerm.app)     TERM_BUNDLE_ID="com.googlecode.iterm2" ;;
        ghostty)       TERM_BUNDLE_ID="com.mitchellh.ghostty" ;;
        Alacritty)     TERM_BUNDLE_ID="org.alacritty" ;;
        WezTerm)       TERM_BUNDLE_ID="com.github.wez.wezterm" ;;
        kitty)         TERM_BUNDLE_ID="net.kovidgoyal.kitty" ;;
    esac
fi

# Build click command: activate terminal + switch to the correct tmux window/pane.
# Everything goes into -execute because -activate and -execute conflict in terminal-notifier.
# Full paths are required because terminal-notifier runs -execute via bare /bin/sh (no PATH).
CLICK_CMD=""
if [ -n "$TERM_BUNDLE_ID" ]; then
    CLICK_CMD="open -b '${TERM_BUNDLE_ID}'"
    TMUX_BIN=$(command -v tmux 2>/dev/null || echo "")
    if [ -n "$TMUX_BIN" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "${SESSION:-}" ] && [ -n "${WIN_INDEX:-}" ]; then
        CLICK_CMD="${CLICK_CMD} && '${TMUX_BIN}' switch-client -t '${SESSION}' && '${TMUX_BIN}' select-window -t '${SESSION}:${WIN_INDEX}' && '${TMUX_BIN}' select-pane -t '${TMUX_PANE}'"
    fi
fi

# --- Project name from cwd ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# --- Subtitle ---
SUBTITLE=""
if [ -n "$TMUX_INFO" ] && [ -n "$PROJECT" ]; then
    SUBTITLE="${TMUX_INFO} · ${PROJECT}"
elif [ -n "$TMUX_INFO" ]; then
    SUBTITLE="${TMUX_INFO}"
elif [ -n "$PROJECT" ]; then
    SUBTITLE="${PROJECT}"
fi

# --- Send notification ---
# Use custom ccnotifs.app if installed (for custom icon),
# otherwise fall back to terminal-notifier, then osascript.
CUSTOM_NOTIFIER="$HOME/.claude/ccnotifs.app/Contents/MacOS/terminal-notifier"

if [ -x "$CUSTOM_NOTIFIER" ]; then
    ARGS=(-title "$TITLE" -message "$BODY")
    [ -n "$SUBTITLE" ] && ARGS+=(-subtitle "$SUBTITLE")
    [ -n "$CLICK_CMD" ] && ARGS+=(-execute "$CLICK_CMD")
    "$CUSTOM_NOTIFIER" "${ARGS[@]}"
elif command -v terminal-notifier &>/dev/null; then
    ARGS=(-title "$TITLE" -message "$BODY" -sound "$SOUND")
    [ -n "$SUBTITLE" ] && ARGS+=(-subtitle "$SUBTITLE")
    [ -n "$CLICK_CMD" ] && ARGS+=(-execute "$CLICK_CMD")
    terminal-notifier "${ARGS[@]}"
else
    # Fallback: osascript (shows Script Editor icon)
    TITLE_ESC="${TITLE//\"/\\\"}"
    BODY_ESC="${BODY//\"/\\\"}"
    if [ -n "$SUBTITLE" ]; then
        SUBTITLE_ESC="${SUBTITLE//\"/\\\"}"
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" subtitle \"${SUBTITLE_ESC}\" sound name \"${SOUND}\""
    else
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" sound name \"${SOUND}\""
    fi
fi

# Play sound via afplay (routes through system audio, capturable by BlackHole etc.)
SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"
if [ -f "$SOUND_FILE" ]; then
    afplay "$SOUND_FILE" &
fi
