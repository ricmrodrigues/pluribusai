"""Install or remove PluribusAI in Cursor ~/.cursor/mcp.json."""
import json
import os
import sys


def cursor_mcp_path():
    return os.path.join(os.path.expanduser("~"), ".cursor", "mcp.json")


def install_cursor(endpoint, token):
    endpoint = endpoint.rstrip("/")
    path = cursor_mcp_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    entry = {"url": f"{endpoint}/mcp"}
    if token:
        entry["headers"] = {"Authorization": f"Bearer {token}"}
    data.setdefault("mcpServers", {})["pluribusai"] = entry
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    return path


def uninstall_cursor():
    path = cursor_mcp_path()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None
    servers = data.get("mcpServers", {})
    servers.pop("pluribusai", None)
    if servers:
        data["mcpServers"] = servers
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    elif os.path.isfile(path):
        os.remove(path)
    return path


if __name__ == "__main__":
    action = sys.argv[1]
    if action == "install":
        install_cursor(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
        print(cursor_mcp_path())
    elif action == "uninstall":
        uninstall_cursor()