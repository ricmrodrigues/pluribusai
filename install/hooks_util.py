"""Merge PluribusAI hooks into Claude settings.json without clobbering others."""
import json
import sys


def _is_pluribus_session_start(hook):
    cmd = hook.get("command", "")
    return "session-start.sh" in cmd or "session-start.ps1" in cmd


def install_session_start(settings_path, command):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    hooks = data.setdefault("hooks", {})
    groups = [g for g in hooks.get("SessionStart", [])
              if not any(_is_pluribus_session_start(h) for h in g.get("hooks", []))]
    groups.append({
        "matcher": "startup|resume",
        "hooks": [{"type": "command", "command": command}],
    })
    hooks["SessionStart"] = groups
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def uninstall_session_start(settings_path):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return
    hooks = data.get("hooks", {})
    if "SessionStart" not in hooks:
        return
    hooks["SessionStart"] = [
        g for g in hooks["SessionStart"]
        if not any(_is_pluribus_session_start(h) for h in g.get("hooks", []))
    ]
    if not hooks["SessionStart"]:
        hooks.pop("SessionStart", None)
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    action, path, *rest = sys.argv[1:]
    if action == "install":
        install_session_start(path, rest[0])
    elif action == "uninstall":
        uninstall_session_start(path)