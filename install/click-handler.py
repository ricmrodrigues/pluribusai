#!/usr/bin/env python3
"""Cross-platform toast click handler: focus.json + clipboard prompt + focus app."""
import argparse
import json
import os
import subprocess
import sys
import time


def pluribusai_dir():
    return os.path.join(os.path.expanduser("~"), ".pluribusai")


def focus_path():
    return os.path.join(pluribusai_dir(), "focus.json")


def _escape_preview(text):
    s = str(text or "").replace("\n", " ").strip()
    return s[:200] + ("…" if len(s) > 200 else "")


def build_prompt(event_type, message_id, sender=None, author=None, preview=None):
    prev = _escape_preview(preview)
    prev_line = f'\nPreview: "{prev}"' if prev else ""
    if event_type == "reply":
        who = author or "someone"
        return (
            f"PluribusAI: open thread {message_id} — {who} replied. "
            f"Use get_message or get_thread_updates, summarize unread replies, "
            f"and help me draft a response if needed.{prev_line}"
        )
    who = sender or "someone"
    return (
        f"PluribusAI: read message {message_id} (from {who}). "
        f"Use read_message/get_message, summarize, and suggest next steps.{prev_line}"
    )


def write_focus(event_type, message_id, sender=None, author=None, preview=None):
    prompt = build_prompt(event_type, message_id, sender, author, preview)
    data = {
        "type": event_type,
        "message_id": message_id,
        "sender": sender,
        "author": author,
        "preview": _escape_preview(preview),
        "prompt": prompt,
        "clicked_at": time.time(),
    }
    os.makedirs(pluribusai_dir(), exist_ok=True)
    with open(focus_path(), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    return prompt


def read_focus(max_age_secs=3600):
    path = focus_path()
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None
    clicked = float(data.get("clicked_at", 0))
    if clicked and time.time() - clicked > max_age_secs:
        return None
    return data


def clear_focus():
    path = focus_path()
    if os.path.isfile(path):
        os.remove(path)


def copy_to_clipboard(text):
    if sys.platform == "darwin":
        p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
        p.communicate(text.encode("utf-8"))
        return p.returncode == 0
    if sys.platform == "win32":
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Add-Type -AssemblyName System.Windows.Forms; "
             "$input | Set-Clipboard"],
            input=text,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return r.returncode == 0
    # Linux / fallback
    for cmd in (["xclip", "-selection", "clipboard"], ["wl-copy"]):
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
            p.communicate(text.encode("utf-8"))
            if p.returncode == 0:
                return True
        except FileNotFoundError:
            continue
    return False


def focus_agent_app():
    if sys.platform == "darwin":
        for app in ("Cursor", "Grok"):
            r = subprocess.run(
                ["osascript", "-e", f'tell application "{app}" to activate'],
                capture_output=True,
                timeout=5,
            )
            if r.returncode == 0:
                return app
        return None
    if sys.platform == "win32":
        ps_path = os.path.join(pluribusai_dir(), "_focus.ps1")
        ps_body = r"""
$ErrorActionPreference = 'SilentlyContinue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr p);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@
function Force-Foreground([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return $false }
  $fg = [NativeMethods]::GetForegroundWindow()
  $fgThread = [NativeMethods]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $winThread = [NativeMethods]::GetWindowThreadProcessId($hwnd, [IntPtr]::Zero)
  $myThread = [NativeMethods]::GetCurrentThreadId()
  if ($fgThread -ne $winThread) {
    [NativeMethods]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
    [NativeMethods]::AttachThreadInput($winThread, $fgThread, $true) | Out-Null
  }
  if ([NativeMethods]::IsIconic($hwnd)) {
    [NativeMethods]::ShowWindowAsync($hwnd, 9) | Out-Null
  }
  $ok = [NativeMethods]::SetForegroundWindow($hwnd)
  if ($fgThread -ne $winThread) {
    [NativeMethods]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
    [NativeMethods]::AttachThreadInput($winThread, $fgThread, $false) | Out-Null
  }
  return $ok
}
foreach ($name in @('Cursor', 'Grok')) {
  $p = Get-Process -Name $name -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
    Sort-Object { $_.MainWindowTitle.Length } -Descending |
    Select-Object -First 1
  if ($p) {
    [void](Force-Foreground $p.MainWindowHandle)
    Write-Output $name
    exit 0
  }
}
exit 1
"""
        os.makedirs(pluribusai_dir(), exist_ok=True)
        with open(ps_path, "w", encoding="utf-8") as f:
            f.write(ps_body)
        r = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return None


def load_payload_file(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    event_type = data.get("type")
    message_id = data.get("message_id")
    if event_type == "reply":
        return event_type, message_id, None, data.get("person"), data.get("preview")
    return event_type, message_id, data.get("person"), None, data.get("preview")


def handle_click(event_type, message_id, sender=None, author=None, preview=None):
    prompt = write_focus(event_type, message_id, sender, author, preview)
    copy_to_clipboard(prompt)
    focus_agent_app()
    return prompt


def consume_focus():
    data = read_focus()
    if not data:
        return 0
    print("PluribusAI notification (clicked):")
    print(data.get("prompt", ""))
    print("Paste from clipboard if needed — prompt was copied on click.")
    clear_focus()
    return 0


def main():
    parser = argparse.ArgumentParser(description="PluribusAI toast click handler")
    parser.add_argument("--consume-focus", action="store_true",
                        help="Print pending focus.json for SessionStart and clear it")
    parser.add_argument("--type", choices=["message", "reply"])
    parser.add_argument("--message-id")
    parser.add_argument("--sender")
    parser.add_argument("--author")
    parser.add_argument("--preview", default="")
    parser.add_argument("--payload-file",
                        help="JSON payload from toast click (avoids shell quoting issues)")
    args = parser.parse_args()

    if args.consume_focus:
        return consume_focus()

    if args.payload_file:
        event_type, message_id, sender, author, preview = load_payload_file(
            args.payload_file)
    else:
        event_type, message_id, sender, author, preview = (
            args.type, args.message_id, args.sender, args.author, args.preview)

    if not event_type or not message_id:
        parser.error("--type and --message-id are required unless using --payload-file")

    handle_click(
        event_type,
        message_id,
        sender=sender,
        author=author,
        preview=preview,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())