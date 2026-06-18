#!/bin/sh
# PluribusAI installer for Cursor + Grok — desktop toasts on macOS and Windows.
#
# Usage:
#   ./install-cursor.sh
#   PLURIBUSAI_ENDPOINT=http://localhost:8787 PLURIBUSAI_TOKEN=xxx PLURIBUSAI_USER=you ./install-cursor.sh
#   ./install-cursor.sh --uninstall
#
# macOS: launchd long-poll poller + osascript notifications
# Windows (Git Bash): schtasks poller + PowerShell balloon toasts

set -e

ENDPOINT="${PLURIBUSAI_ENDPOINT:-http://localhost:8787}"
ENDPOINT="${ENDPOINT%/}"
DIR="$HOME/.pluribusai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\033[36m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  *) die "Unsupported OS — use macOS or Windows (Git Bash)." ;;
esac

if [ "$1" = "--uninstall" ]; then
  say "Uninstalling PluribusAI (Cursor + Grok)..."
  if [ "$PLATFORM" = macos ]; then
    PLIST="$HOME/Library/LaunchAgents/com.pluribusai.poll.plist"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
  else
    schtasks //Delete //TN pluribusai-poll //F 2>/dev/null || true
  fi
  rm -rf "$DIR"
  python3 "$SCRIPT_DIR/cursor_util.py" uninstall 2>/dev/null \
    || python "$SCRIPT_DIR/cursor_util.py" uninstall 2>/dev/null || true
  python3 "$SCRIPT_DIR/grok_hooks_util.py" uninstall 2>/dev/null \
    || python "$SCRIPT_DIR/grok_hooks_util.py" uninstall 2>/dev/null || true
  if command -v grok >/dev/null 2>&1; then
    grok mcp remove pluribusai 2>/dev/null || true
  fi
  say "Removed."
  exit 0
fi

if [ "$PLATFORM" = windows ]; then
  command -v schtasks >/dev/null 2>&1 || die "schtasks not found."
  command -v powershell >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1 \
    || die "powershell not found."
  PY=python
  command -v python >/dev/null 2>&1 || die "python not found."
else
  command -v python3 >/dev/null 2>&1 || die "python3 not found."
  command -v curl >/dev/null 2>&1 || die "curl not found."
  PY=python3
fi

TOKEN="${PLURIBUSAI_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  printf "Enter PluribusAI bearer token (empty if auth disabled): "
  read -r TOKEN
fi

USER_ID="${PLURIBUSAI_USER:-}"
if [ -z "$USER_ID" ]; then
  printf "Enter your username (e.g. first name, lowercase): "
  read -r USER_ID
fi
[ -n "$USER_ID" ] || die "No username provided."

mkdir -p "$DIR"
if [ "$PLATFORM" = macos ]; then
  mkdir -p "$HOME/Library/LaunchAgents"
fi

say "Registering PluribusAI with Cursor ($USER_ID)..."
CURSOR_CFG=$($PY "$SCRIPT_DIR/cursor_util.py" install "$ENDPOINT" "$TOKEN" "$USER_ID")
say "  cursor -> $CURSOR_CFG"

if [ "$PLATFORM" = macos ]; then
  cat > "$DIR/env" <<EOF
PLURIBUSAI_TOKEN="$TOKEN"
PLURIBUSAI_ENDPOINT="$ENDPOINT"
PLURIBUSAI_USER="$USER_ID"
EOF
  chmod 600 "$DIR/env"
  cp "$SCRIPT_DIR/poll-macos.sh" "$DIR/poll.sh"
  chmod +x "$DIR/poll.sh"
  cp "$SCRIPT_DIR/session-start.sh" "$DIR/session-start.sh"
  chmod +x "$DIR/session-start.sh"
  cp "$SCRIPT_DIR/click-handler.py" "$DIR/click-handler.py"

  PLIST="$HOME/Library/LaunchAgents/com.pluribusai.poll.plist"
  LABEL="com.pluribusai.poll"
  say "Installing launchd poller ($LABEL) — macOS desktop notifications..."
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$DIR/poll.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DIR/poll.err</string>
  <key>StandardOutPath</key><string>$DIR/poll.out</string>
</dict></plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
else
  PY_WIN=$(cygpath -w "$(command -v python 2>/dev/null || command -v python3)" | sed 's/\\/\\\\/g')
  cat > "$DIR/env.ps1" <<EOF
\$PLURIBUSAI_TOKEN    = '$TOKEN'
\$PLURIBUSAI_ENDPOINT = '$ENDPOINT'
\$PLURIBUSAI_USER     = '$USER_ID'
\$PLURIBUSAI_PYTHON   = '$PY_WIN'
EOF
  cp "$SCRIPT_DIR/poll-windows.ps1" "$DIR/poll.ps1"
  cp "$SCRIPT_DIR/winrt-toast.ps1" "$DIR/winrt-toast.ps1"
  cp "$SCRIPT_DIR/protocol-open.ps1" "$DIR/protocol-open.ps1"
  cp "$SCRIPT_DIR/register-windows-toast.ps1" "$DIR/register-windows-toast.ps1"
  cp "$SCRIPT_DIR/session-start.ps1" "$DIR/session-start.ps1"
  cp "$SCRIPT_DIR/click-handler.py" "$DIR/click-handler.py"
  cp "$SCRIPT_DIR/poll-hidden.vbs" "$DIR/poll-hidden.vbs"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$DIR/register-windows-toast.ps1" >/dev/null 2>&1 || true
  VBS_WIN=$(cygpath -w "$DIR/poll-hidden.vbs")
  schtasks //Delete //TN pluribusai-poll //F 2>/dev/null || true
  say "Starting continuous poll daemon (login only, no minute spam)..."
  schtasks //Create //TN pluribusai-poll //SC ONLOGON //F \
    //TR "wscript.exe \"$VBS_WIN\"" >/dev/null
  wscript.exe "$VBS_WIN" >/dev/null 2>&1 &
fi

say "Installing Grok SessionStart hook..."
if [ "$PLATFORM" = windows ]; then
  SS_WIN=$(cygpath -w "$DIR/session-start.ps1")
  GROK_CMD="powershell -NoProfile -ExecutionPolicy Bypass -File \"$SS_WIN\""
else
  GROK_CMD="sh $DIR/session-start.sh"
fi
$PY "$SCRIPT_DIR/grok_hooks_util.py" install "$GROK_CMD"
say "  grok hook -> ~/.grok/hooks/pluribusai-session.json"

if command -v grok >/dev/null 2>&1; then
  say "Refreshing Grok MCP registration..."
  grok mcp remove pluribusai >/dev/null 2>&1 || true
  if [ -n "$TOKEN" ]; then
    grok mcp add --transport http pluribusai "$ENDPOINT/mcp" \
      --header "Authorization: Bearer $TOKEN" \
      --header "X-PluribusAI-User: $USER_ID" >/dev/null 2>&1 || true
  else
    grok mcp add --transport http pluribusai "$ENDPOINT/mcp" \
      --header "X-PluribusAI-User: $USER_ID" >/dev/null 2>&1 || true
  fi
fi

echo "0" > "$DIR/.activity-cursor"
echo "?" > "$DIR/open-count.txt"

echo
say "Installed for $USER_ID at $ENDPOINT/mcp"
if [ "$PLATFORM" = macos ]; then
  if command -v terminal-notifier >/dev/null 2>&1; then
    echo "   • macOS toasts: terminal-notifier (click → clipboard prompt + focus Cursor)"
  else
    echo "   • macOS toasts: osascript (install terminal-notifier for click-to-open: brew install terminal-notifier)"
  fi
else
  echo "   • Windows: WinRT Action Center toasts (click opens Cursor)"
fi
echo "   • Restart Cursor and Grok to pick up MCP + hooks"
echo "   • Uninstall: ./install-cursor.sh --uninstall"