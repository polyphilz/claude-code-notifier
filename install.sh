#!/bin/bash
# Install ccnotifs
# Downloads notify.sh and icon.png from GitHub, sets up hooks and optional custom icon.
#
# Run directly:  curl -fsSL https://raw.githubusercontent.com/polyphilz/ccnotifs/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/polyphilz/ccnotifs/main"
HOOKS_DIR="$HOME/.claude/hooks"

echo "Installing ccnotifs..."

# --- Download notify.sh ---
mkdir -p "$HOOKS_DIR"
curl -fsSL "$REPO_RAW/notify.sh" -o "$HOOKS_DIR/notify.sh"
chmod +x "$HOOKS_DIR/notify.sh"
echo "  Downloaded notify.sh -> $HOOKS_DIR/notify.sh"

# --- Custom icon (optional — requires terminal-notifier) ---
APP_DIR="$HOME/.claude/ccnotifs.app"
TN_APP=$(find /opt/homebrew/Cellar/terminal-notifier -name "terminal-notifier.app" -maxdepth 2 2>/dev/null | head -1)

if [ -n "$TN_APP" ]; then
    echo "  Found terminal-notifier — downloading icon and building ccnotifs.app..."

    TMPDIR_ICON=$(mktemp -d)
    ICON_SRC="$TMPDIR_ICON/icon.png"
    if curl -fsSL "$REPO_RAW/icon.png" -o "$ICON_SRC" 2>/dev/null; then
        # Build iconset
        ICONSET="$TMPDIR_ICON/ccnotifs.iconset"
        mkdir -p "$ICONSET"
        for size in 16 32 64 128 256 512; do
            sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
            double=$((size * 2))
            sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
        done
        cp "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"
        ICNS="$TMPDIR_ICON/ccnotifs.icns"
        iconutil -c icns "$ICONSET" -o "$ICNS"

        # Copy terminal-notifier.app and replace icon
        rm -rf "$APP_DIR"
        cp -R "$TN_APP" "$APP_DIR"

        # Find the icon filename referenced in the plist
        ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo "AppIcon")
        cp "$ICNS" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"

        # Update bundle identifier
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ccnotifs" "$APP_DIR/Contents/Info.plist"

        # Register with Launch Services and clear icon cache
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
        killall NotificationCenter 2>/dev/null || true

        echo "  ccnotifs.app installed with custom icon."
        rm -rf "$TMPDIR_ICON"
    else
        echo "  Could not download icon.png — skipping custom icon setup."
        rm -rf "$TMPDIR_ICON"
    fi
else
    echo "  terminal-notifier not found — skipping custom icon setup."
    echo "  For custom notification icons, install it with: brew install terminal-notifier"
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
