# Claude Code Notifier

Native macOS notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Know when Claude Code finishes or needs your input.

![demo](assets/demo.gif)

## Features

- **Two notification types** — "Done" when Claude finishes, "Needs Input" when Claude needs approval
- **tmux context** — shows session name, window number, and window name so you know exactly where to look
- **Project name** — displays the current project directory
- **Smart suppression** — skips notifications when you're already viewing the Claude Code session
- **Custom icon** — optionally use your own app icon instead of the default Script Editor icon
- **Sound** — plays a distinct sound per notification type (Glass for done, Ping for needs input)

### Example notification

```
Claude Code — Done
myproject w3 > feature-branch · my-app
Claude has finished and is awaiting further instructions
```

## Requirements

- macOS (uses native notification APIs)
- [jq](https://jqlang.github.io/jq/) — `brew install jq`
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) (optional, for custom icon) — `brew install terminal-notifier`

## Install

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-notifier.git
cd claude-code-notifier
./install.sh
```

The install script:
1. Symlinks `notify.sh` into `~/.claude/hooks/`
2. If `icon.png` exists in the repo, builds a `ClaudeNotifier.app` with your custom icon
3. Prints the hooks config to add to your `settings.json`

### Custom icon

Place a **1024x1024 PNG** named `icon.png` in the repo root before running `install.sh`. This gets baked into a minimal `.app` bundle that macOS uses as the notification icon.

Without `icon.png`, notifications fall back to `osascript` (Script Editor icon) or `terminal-notifier` (Terminal icon).

## Manual setup

If you prefer not to use `install.sh`:

**1. Symlink the script:**

```bash
mkdir -p ~/.claude/hooks
ln -sf /path/to/claude-code-notifier/notify.sh ~/.claude/hooks/notify.sh
```

**2. Add hooks to `~/.claude/settings.json`:**

```json
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
```

**3. Restart your Claude Code session.**

Hooks are snapshotted at session start — you must restart for changes to take effect.

## How it works

Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) runs shell commands on lifecycle events:

| Hook | Event | Notification |
|------|-------|-------------|
| `Stop` | Claude finishes responding | "Claude Code — Done" |
| `Notification` | Claude needs approval (permission prompt) | "Claude Code — Needs Input" |

The script reads JSON from stdin (provided by Claude Code), extracts the working directory, and queries tmux for session/window context. If you're already looking at the session in a supported terminal (Ghostty, iTerm2, Alacritty, kitty, WezTerm, Terminal), the notification is suppressed.

## Notification priority

The script tries these in order:

1. **`ClaudeNotifier.app`** — custom icon, requires `terminal-notifier` + `icon.png` setup
2. **`terminal-notifier`** — Terminal icon, no setup beyond `brew install`
3. **`osascript`** — Script Editor icon, zero dependencies

## Troubleshooting

**Notifications don't appear when screen recording or mirroring:**
macOS suppresses banners during screen sharing as a privacy feature. Fix: System Settings > Notifications > "Allow notifications when mirroring or sharing the display" > Allow Notifications.

**Notifications show in Notification Center but not as banners:**
Check System Settings > Notifications > find "ClaudeNotifier" (or "terminal-notifier") > set alert style to "Banners" or "Alerts".

**tmux info not showing:**
Make sure Claude Code is running inside a tmux session. The `$TMUX` and `$TMUX_PANE` environment variables must be set.

**Square brackets in subtitle cause it to disappear:**
Known `terminal-notifier` bug. The script avoids brackets by default.

## License

MIT
