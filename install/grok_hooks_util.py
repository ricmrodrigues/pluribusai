"""Install PluribusAI SessionStart hook for Grok CLI (~/.grok/hooks/)."""
import json
import os
import sys

HOOK_NAME = "pluribusai-session.json"


def hook_path():
    return os.path.join(os.path.expanduser("~"), ".grok", "hooks", HOOK_NAME)


def install_hook(command=None):
    cmd = command or "sh ~/.pluribusai/session-start.sh"
    os.makedirs(os.path.dirname(hook_path()), exist_ok=True)
    data = {
        "hooks": {
            "SessionStart": [
                {
                    "matcher": "startup|resume",
                    "hooks": [{"type": "command", "command": cmd}],
                }
            ]
        }
    }
    with open(hook_path(), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    return hook_path()


def uninstall_hook():
    path = hook_path()
    if os.path.isfile(path):
        os.remove(path)
    return path


if __name__ == "__main__":
    if sys.argv[1] == "install":
        print(install_hook(sys.argv[2] if len(sys.argv) > 2 else None))
    elif sys.argv[1] == "uninstall":
        uninstall_hook()