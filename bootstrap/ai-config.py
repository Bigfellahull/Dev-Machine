#!/usr/bin/env python3
"""Converge managed AI settings without importing identities or runtime state."""

from __future__ import annotations

import argparse
from collections.abc import MutableMapping
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

import tomlkit


ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "config/ai"
MARKETPLACE = "claude-plugins-official"
MARKETPLACE_SOURCE = {"source": "github", "repo": "anthropics/claude-plugins-official"}
TRANSPORT_FIELDS = {"url", "command", "args", "type", "enabled"}
PORTABLE_SERVER_FIELDS = {
    "startup_timeout_sec", "startup_timeout_ms", "tool_timeout_sec", "required",
    "enabled_tools", "disabled_tools", "tools", "default_tools_approval_mode",
}


class _ConfigError(Exception):
    """Carry diagnostics that contain no private configuration values."""


def _safe_path(home: Path, relative: str) -> Path:
    path = home / relative
    for item in [path, *path.parents]:
        if item == home:
            break
        if item.is_symlink():
            raise _ConfigError(f"Refusing symlinked AI state: {relative}")
    if path.exists() and not path.is_file():
        raise _ConfigError(f"Expected a regular AI configuration file: {relative}")
    return path


def _read(path: Path):
    if not path.exists():
        return tomlkit.document() if path.suffix == ".toml" else {}
    try:
        source = path.read_text(encoding="utf-8")
        value = tomlkit.parse(source) if path.suffix == ".toml" else json.loads(source)
    except (ValueError, tomlkit.exceptions.ParseError) as error:
        # Parser diagnostics can quote credentials from the input.
        raise _ConfigError(f"Invalid AI configuration: {path.name}") from error
    if not isinstance(value, MutableMapping):
        raise _ConfigError(f"Expected an object in {path.name}")
    return value


def _merge(target, desired):
    for key, value in desired.items():
        if isinstance(value, MutableMapping) and isinstance(target.get(key), MutableMapping):
            _merge(target[key], value)
        else:
            target[key] = copy.deepcopy(value)


def _table(document, name):
    if name not in document:
        document[name] = {}
    if not isinstance(document[name], MutableMapping):
        raise _ConfigError(f"Expected an object for AI setting {name}")
    return document[name]


def _servers(profile: str):
    if profile == "personal":
        return _read(TEMPLATES / "mcp.personal.json")
    path = _safe_path(ROOT, "config/local/mcp.work.json")
    config = _read(path)
    for name, server in config.items():
        if (not re.fullmatch(r"[A-Za-z0-9_-]+", name)
                or name in {"railway", "linear", "openaiDeveloperDocs"}
                or not isinstance(server, dict) or set(server) != {"url"}):
            raise _ConfigError("mcp.work.json requires non-reserved server names and URL-only definitions")
        url = server["url"]
        if not isinstance(url, str):
            raise _ConfigError("Local MCP servers require HTTPS endpoints")
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
                or parsed.query or parsed.fragment
                or parsed.hostname == "example.com" or parsed.hostname.endswith(".example.com")):
            raise _ConfigError("Local MCP servers require real HTTPS endpoints without embedded credentials")
    return config


def _configure_servers(document, key, servers, profile, claude=False):
    target = _table(document, key)
    forbidden = set() if profile == "personal" else {"railway", "linear"}
    for name in forbidden:
        target.pop(name, None)
    for name, definition in servers.items():
        entry = _table(target, name)
        transport_changed = any(entry.get(field) != definition.get(field)
                                for field in ("url", "command", "args"))
        # Unknown fields may supply credentials in newer clients; fail closed on destination changes.
        sensitive_fields = set(entry) - TRANSPORT_FIELDS - PORTABLE_SERVER_FIELDS
        if transport_changed and any(entry[field] for field in sensitive_fields):
            raise _ConfigError("Review authentication and non-portable settings before changing a managed MCP destination")
        # Transport fields from a previous installation must not mask the managed transport.
        for field in TRANSPORT_FIELDS:
            entry.pop(field, None)
        _merge(entry, definition)
        if claude:
            entry["type"] = "http" if "url" in definition else "stdio"
        else:
            entry["enabled"] = True
    if not target:
        document.pop(key)


def _prepare(home: Path, profile: str):
    servers = _servers(profile)
    changes = []
    for template, relative in [
        ("codex.toml", ".codex/config.toml"),
        ("claude.json", ".claude/settings.json"),
        ("grok.toml", ".grok/config.toml"),
        ("grok-sandbox.toml", ".grok/sandbox.toml"),
        (None, ".claude.json"),
    ]:
        path = _safe_path(home, relative)
        current = _read(path)
        desired = copy.deepcopy(current)
        defaults = _read(TEMPLATES / template) if template else {}
        if template in {"codex.toml", "grok.toml"}:
            managed_servers = dict(defaults.pop("mcp_servers", {}))
            managed_servers.update(servers)
            _configure_servers(desired, "mcp_servers", managed_servers, profile)
        elif template is None:
            _configure_servers(desired, "mcpServers", servers, profile, claude=True)
        _merge(desired, defaults)
        if template == "claude.json":
            for name, settings in _table(desired, "modelSettings").items():
                if name in {"fable", "fable[1m]", "claude-fable-5-1", "claude-fable-5-1[1m]"}:
                    if isinstance(settings, MutableMapping):
                        settings.pop("effortLevel", None)
            if not desired["modelSettings"]:
                desired.pop("modelSettings")
        if template == "grok.toml":
            desired["ui"].pop("fork_secondary_model", None)
            model = desired.get("model", {}).get("grok-4.6", {})
            if isinstance(model, MutableMapping):
                model.pop("reasoning_effort", None)
        if template is None:
            disabled = desired.get("disabledMcpServers", [])
            if isinstance(disabled, list):
                if "disabledMcpServers" in desired:
                    desired["disabledMcpServers"] = [name for name in disabled if name not in servers]
        current_values = current.unwrap() if path.suffix == ".toml" else current
        desired_values = desired.unwrap() if path.suffix == ".toml" else desired
        if desired_values != current_values or not path.exists() or path.stat().st_mode & 0o777 != 0o600:
            rendered = (tomlkit.dumps(desired) if path.suffix == ".toml"
                        else json.dumps(desired, indent=2, ensure_ascii=False) + "\n")
            changes.append((path, rendered))
    return changes


def _write(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".dev-machine-ai-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _plugin_ids():
    return list(_read(TEMPLATES / "claude.json")["enabledPlugins"])


def _installed_plugins(home: Path):
    registry = _read(_safe_path(home, ".claude/plugins/installed_plugins.json"))
    plugins = registry.get("plugins", {})
    if not isinstance(plugins, dict):
        raise _ConfigError("Invalid Claude plugin registry")
    installed = set()
    for name in _plugin_ids():
        entries = plugins.get(name, [])
        if not isinstance(entries, list):
            raise _ConfigError("Invalid Claude plugin registry entries")
        for entry in entries:
            if not isinstance(entry, dict):
                raise _ConfigError("Invalid Claude plugin registry entry")
            location = entry.get("installPath")
            if entry.get("scope") == "user" and isinstance(location, str):
                manifest = Path(location) / ".claude-plugin/plugin.json"
                if manifest.is_file() and _read(manifest).get("name") == name.split("@")[0]:
                    installed.add(name)
    return installed


def _claude(*arguments):
    try:
        result = subprocess.run(["claude", *arguments], capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired as error:
        raise _ConfigError("Claude plugin command timed out; retry provisioning after checking connectivity") from error
    if result.returncode:
        raise _ConfigError("Claude plugin command failed; check the CLI version and marketplace connectivity")
    return result.stdout


def _plugins(home: Path, install: bool):
    version = re.search(r"\b(\d+)\.(\d+)\.(\d+)\b", _claude("--version"))
    if not version or tuple(map(int, version.groups())) < (2, 1, 257):
        raise _ConfigError("Claude Code 2.1.257 or newer is required; run claude update")
    marketplaces = _read(_safe_path(home, ".claude/plugins/known_marketplaces.json"))
    entry = marketplaces.get(MARKETPLACE)
    if entry is not None and (not isinstance(entry, dict) or entry.get("source") != MARKETPLACE_SOURCE):
        raise _ConfigError("Claude official marketplace has an unexpected source; review it before provisioning")
    if entry is None:
        if not install:
            raise _ConfigError("Claude official plugin marketplace is not registered")
        _claude("plugin", "marketplace", "add", MARKETPLACE_SOURCE["repo"])
    missing = set(_plugin_ids()) - _installed_plugins(home)
    if install:
        for plugin in sorted(missing):
            print(f"Installing Claude plugin: {plugin}")
            _claude("plugin", "install", plugin, "--scope", "user")
        missing = set(_plugin_ids()) - _installed_plugins(home)
    if missing:
        raise _ConfigError("Required Claude plugins are missing or incomplete: " + ", ".join(sorted(missing)))


def main() -> int:
    """Apply or inspect repository-owned settings without printing private values."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["apply", "verify", "install-plugins", "verify-plugins"])
    parser.add_argument("--profile", choices=["work", "personal"], required=True)
    args = parser.parse_args()
    home = Path.home().resolve()
    try:
        if args.command.endswith("plugins"):
            _plugins(home, args.command == "install-plugins")
            return 0
        changes = _prepare(home, args.profile)
        if args.command == "apply":
            for path, content in changes:
                _write(path, content)
        else:
            for path, _ in changes:
                print(f"Managed AI settings differ: {path.relative_to(home)}", file=sys.stderr)
        return int(args.command == "verify" and bool(changes))
    except _ConfigError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, TypeError, AttributeError, tomlkit.exceptions.TOMLKitError):
        # Neither subprocess output nor parsed configuration belongs in provisioning logs.
        print("AI configuration failed. Check file formats, paths, CLI version and plugin state; private values withheld.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
