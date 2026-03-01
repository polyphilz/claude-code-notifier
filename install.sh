#!/bin/bash
# Install claude-code-notifier
# Symlinks notify.sh into ~/.claude/hooks/ and optionally sets up a custom icon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"

echo "Installing claude-code-notifier..."

# --- Symlink notify.sh ---
mkdir -p "$HOOKS_DIR"
ln -sf "$SCRIPT_DIR/notify.sh" "$HOOKS_DIR/notify.sh"
echo "  Symlinked notify.sh -> $HOOKS_DIR/notify.sh"

# --- Custom icon (optional) ---
ICON_SRC="$SCRIPT_DIR/icon.png"
APP_DIR="$HOME/.claude/ClaudeNotifier.app"

if [ -f "$ICON_SRC" ]; then
    echo "  Found icon.png — building ClaudeNotifier.app..."

    # Check for terminal-notifier
    TN_APP=$(find /opt/homebrew/Cellar/terminal-notifier -name "terminal-notifier.app" -maxdepth 2 2>/dev/null | head -1)
    if [ -z "$TN_APP" ]; then
        echo "  terminal-notifier not found. Install it with: brew install terminal-notifier"
        echo "  Skipping custom icon setup."
    else
        # Build iconset
        ICONSET=$(mktemp -d)/ClaudeNotifier.iconset
        mkdir -p "$ICONSET"
        for size in 16 32 64 128 256 512; do
            sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
            double=$((size * 2))
            sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
        done
        cp "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"
        ICNS=$(mktemp).icns
        iconutil -c icns "$ICONSET" -o "$ICNS"

        # Copy terminal-notifier.app and replace icon
        rm -rf "$APP_DIR"
        cp -R "$TN_APP" "$APP_DIR"

        # Find the icon filename referenced in the plist
        ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo "AppIcon")
        cp "$ICNS" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"

        # Update bundle identifier
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claude-code.notifier" "$APP_DIR/Contents/Info.plist"

        # Register with Launch Services and clear icon cache
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
        killall NotificationCenter 2>/dev/null || true

        echo "  ClaudeNotifier.app installed with custom icon."
    fi
else
    echo "  No icon.png found — skipping custom icon setup."
    echo "  To use a custom icon, place a 1024x1024 PNG as icon.png in this directory and re-run."
fi

# --- Print hooks config ---
cat << 'HOOKS'

Add this to your ~/.claude/settings.json:

{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh needs_input"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh done"
          }
        ]
      }
    ]
  }
}

Restart your Claude Code session to activate.
HOOKS

echo ""
echo "Done!"
