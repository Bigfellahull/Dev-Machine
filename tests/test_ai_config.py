"""Verify AI configuration convergence and profile isolation in temporary homes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest

import tomlkit


ROOT = Path(__file__).resolve().parents[1]


class AiConfigTests(unittest.TestCase):
    """Exercise provisioning without invoking real AI clients or credentials."""

    def setUp(self):
        """Create isolated user state and a deterministic plugin installer."""
        self.temp = tempfile.TemporaryDirectory(prefix="dev-machine-ai-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        (self.repo / "bootstrap").mkdir(parents=True)
        self.helper = self.repo / "bootstrap/ai-config.py"
        shutil.copyfile(ROOT / "bootstrap/ai-config.py", self.helper)
        (self.repo / "config/ai").mkdir(parents=True)
        for template in (ROOT / "config/ai").glob("*.*"):
            if template.is_file():
                shutil.copyfile(template, self.repo / "config/ai" / template.name)
        self.home = self.root / "home"
        self.home.mkdir()
        mocks = self.root / "bin"
        mocks.mkdir()
        shutil.copyfile(ROOT / "tests/fixtures/claude", mocks / "claude")
        (mocks / "claude").chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{mocks}:{Path(sys.executable).parent}:{os.environ['PATH']}")

    def _run(self, command="apply", profile="personal", ok=True):
        result = subprocess.run([sys.executable, "-B", str(self.helper), command, "--profile", profile],
                                env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def _write(self, relative, content):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def _read(self, relative):
        text = (self.home / relative).read_text()
        return tomllib.loads(text) if relative.endswith(".toml") else json.loads(text)

    def _snapshot(self):
        return {str(p.relative_to(self.home)): (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_mode)
                for p in self.home.rglob("*") if p.is_file()}

    def _work_endpoint(self):
        path = self.repo / "config/local/mcp.work.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"work-service": {"url": "https://support.example.org/mcp"}}))
        return path

    def test_fresh_defaults_and_repeat_preserve_bytes_and_mtime(self):
        """Fresh personal state has all defaults and a second run changes nothing."""
        self._run()
        codex = self._read(".codex/config.toml")
        self.assertEqual(codex["model"], "gpt-6-astra")
        self.assertEqual(codex["model_reasoning_effort"], "high")
        self.assertTrue(codex["features"]["goals"])
        self.assertEqual(codex["approvals_reviewer"], "auto_review")
        self.assertEqual(codex["sandbox_mode"], "workspace-write")
        self.assertFalse(codex["shell_environment_policy"]["ignore_default_excludes"])
        claude = self._read(".claude/settings.json")
        self.assertEqual(claude["model"], "claude-fable-5-1")
        self.assertEqual(claude["effortLevel"], "high")
        self.assertNotIn("modelSettings", claude)
        self.assertEqual(claude["permissions"]["defaultMode"], "auto")
        self.assertFalse(claude["sandbox"]["allowUnsandboxedCommands"])
        self.assertTrue(claude["sandbox"]["failIfUnavailable"])
        grok = self._read(".grok/config.toml")
        self.assertEqual(grok["models"], {"default": "grok-4.6", "default_reasoning_effort": "high"})
        self.assertEqual(grok["ui"]["permission_mode"], "auto")
        self.assertFalse(grok["ui"]["yolo"])
        self.assertFalse(grok["features"]["remember_mode"])
        self.assertEqual(grok["sandbox"]["profile"], "safe-workspace")
        self.assertFalse(grok["sandbox"]["auto_allow_bash"])
        self.assertNotIn("fork_secondary_model", grok["ui"])
        before = self._snapshot()
        self._run()
        self._run("verify")
        self.assertEqual(before, self._snapshot())
        self.assertTrue(all(mode & 0o777 == 0o600 for _, _, mode in before.values()))

    def test_existing_settings_preserve_custom_state_and_remove_conflicting_effort(self):
        """Owned fields converge while comments, logins and unrelated settings survive."""
        self._write(".codex/config.toml", '''# Keep this user comment
model = "old-model"
model_reasoning_effort = "xhigh"
sandbox_mode = "danger-full-access"
[features]
goals = false
custom_feature = true
[mcp_servers.custom]
url = "https://custom.example.org/mcp"
http_headers = { Authorization = "private-placeholder" }
''')
        self._write(".grok/config.toml", '''[ui]
permission_mode = "always-approve"
fork_secondary_model = "grok-4.5"
[model."grok-4.6"]
reasoning_effort = "xhigh"
context_window = 100000
''')
        self._write(".claude/settings.json", json.dumps({
            "modelSettings": {"claude-fable-5-1": {"effortLevel": "xhigh", "custom": True},
                              "another-model": {"effortLevel": "low"}},
            "permissions": {"defaultMode": "bypassPermissions", "deny": ["Bash(unwanted-command)"]},
            "env": {"CUSTOM_SETTING": "preserved"},
            "enabledPlugins": {"custom@other": True}
        }))
        self._write(".claude.json", json.dumps({"oauthAccount": {"private": "preserved"},
                                               "projects": {"example": {"trusted": True}}}))
        result = self._run()
        self.assertNotIn("private-placeholder", result.stdout + result.stderr)
        self.assertIn("# Keep this user comment", (self.home / ".codex/config.toml").read_text())
        codex = self._read(".codex/config.toml")
        self.assertTrue(codex["features"]["custom_feature"])
        self.assertEqual(codex["model_reasoning_effort"], "high")
        self.assertEqual(codex["sandbox_mode"], "workspace-write")
        self.assertEqual(codex["mcp_servers"]["custom"]["http_headers"]["Authorization"], "private-placeholder")
        settings = self._read(".claude/settings.json")
        self.assertEqual(settings["modelSettings"]["claude-fable-5-1"], {"custom": True})
        self.assertEqual(settings["modelSettings"]["another-model"]["effortLevel"], "low")
        self.assertEqual(settings["permissions"]["deny"], ["Bash(unwanted-command)"])
        self.assertTrue(settings["enabledPlugins"]["custom@other"])
        self.assertEqual(self._read(".claude.json")["oauthAccount"], {"private": "preserved"})
        self.assertNotIn("reasoning_effort", self._read(".grok/config.toml")["model"]["grok-4.6"])
        self._run("verify")

    def test_profile_mcp_convergence_across_all_clients(self):
        """Named integrations stay on their intended profile, including repeated runs."""
        self._work_endpoint()
        for profile in ["personal", "work", "work"]:
            self._run(profile=profile)
            self._run("verify", profile)
            expected = {"railway", "linear"} if profile == "personal" else {"work-service"}
            for relative, key in [(".codex/config.toml", "mcp_servers"),
                                  (".grok/config.toml", "mcp_servers"), (".claude.json", "mcpServers")]:
                servers = self._read(relative)[key]
                self.assertEqual(set(servers) & {"railway", "linear", "work-service"}, expected)
                if profile == "personal":
                    self.assertEqual(servers["railway"]["command"], "railway")
                    self.assertEqual(servers["railway"]["args"], ["mcp"])
                else:
                    self.assertEqual(servers["work-service"]["url"], "https://support.example.org/mcp")
            before = self._snapshot()
            self._run(profile=profile)
            self.assertEqual(before, self._snapshot())

    def test_work_override_is_optional_and_verified_when_present(self):
        """Work has no private servers until its local override is supplied."""
        self._run(profile="work")
        self._run("verify", "work")
        before = self._snapshot()
        self._run(profile="work")
        self.assertEqual(before, self._snapshot())
        self._work_endpoint()
        self._run("verify", "work", ok=False)
        self._run(profile="work")
        self._run("verify", "work")

    def test_personal_does_not_read_work_override(self):
        """A malformed private work file cannot affect personal provisioning."""
        self._work_endpoint().write_text("private-placeholder-not-valid-json")
        self._run()
        self._run("verify")

    def test_local_override_is_ignored_by_git(self):
        """The private override path stays outside the public change set."""
        result = subprocess.run(["git", "check-ignore", "config/local/mcp.work.json"],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)

    def test_local_override_rejects_extra_fields_reserved_names_and_symlinks(self):
        """Private definitions cannot override public integrations or inject credentials."""
        path = self._work_endpoint()
        for config in [{"linear": {"url": "https://support.example.org/mcp"}},
                       {"openaiDeveloperDocs": {"url": "https://support.example.org/mcp"}},
                       {"private-placeholder": {"url": "https://support.example.org/mcp",
                                                "headers": {"Authorization": "private-placeholder"}}}]:
            path.write_text(json.dumps(config))
            result = self._run(profile="work", ok=False)
            self.assertNotIn("private-placeholder", result.stdout + result.stderr)
            self.assertEqual(self._snapshot(), {})
        path.unlink()
        path.symlink_to(self._write("private.json", "{}"))
        self._run(profile="work", ok=False)

    def test_invalid_private_configuration_is_not_printed_or_partially_applied(self):
        """A malformed late input prevents every write and does not appear in errors."""
        self._write(".claude.json", '{"private": "private-placeholder-must-not-appear"')
        before = self._snapshot()
        result = self._run(ok=False)
        self.assertEqual(before, self._snapshot())
        self.assertNotIn("private-placeholder", result.stdout + result.stderr)

    def test_symlinked_configuration_and_parents_are_rejected(self):
        """Provisioning never follows a config link into another identity's state."""
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / ".codex").symlink_to(outside, target_is_directory=True)
        self._run(ok=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_verify_detects_drift_without_writing(self):
        """Verification checks values and leaves files untouched."""
        self._run()
        path = self.home / ".codex/config.toml"
        path.write_text(path.read_text().replace('"high"', '"xhigh"'))
        before = self._snapshot()
        self._run("verify", ok=False)
        self.assertEqual(before, self._snapshot())

    def test_endpoint_rejects_credentials_and_template_placeholder(self):
        """Private tokens cannot be smuggled into the managed endpoint URL."""
        for url in ["https://support.example.com/mcp", "http://support.example.org/mcp",
                    "https://name:private-placeholder@support.example.org/mcp",
                    "https://support.example.org/mcp?token=private-placeholder"]:
            self._work_endpoint().write_text(json.dumps({"work-service": {"url": url}}))
            result = self._run(profile="work", ok=False)
            self.assertNotIn("private-placeholder", result.stdout + result.stderr)

    def test_endpoint_changes_reject_authentication_before_any_write(self):
        """Every managed endpoint checks original credentials, including template servers."""
        for relative, key, name, fields in [
            (".codex/config.toml", "mcp_servers", "linear",
             ["http_headers", "env_http_headers", "http_headers_helper", "bearer_token_env_var",
              "auth", "oauth", "oauth_resource", "future_auth_field"]),
            (".codex/config.toml", "mcp_servers", "openaiDeveloperDocs", ["http_headers", "env_http_headers"]),
            (".grok/config.toml", "mcp_servers", "linear", ["headers", "bearer_token"]),
            (".claude.json", "mcpServers", "linear", ["headers", "oauth"]),
        ]:
            for field in fields:
                with self.subTest(client=relative, server=name, authentication=field):
                    config = {key: {name: {"url": "https://old.example.org/mcp", field: "private-placeholder"}}}
                    text = tomlkit.dumps(config) if relative.endswith(".toml") else json.dumps(config)
                    path = self._write(relative, text)
                    before = self._snapshot()
                    result = self._run(ok=False)
                    self.assertIn("Review authentication", result.stderr)
                    self.assertNotIn("private-placeholder", result.stdout + result.stderr)
                    self.assertEqual(before, self._snapshot())
                    path.unlink()

    def test_same_destination_preserves_authentication(self):
        """Keeping an endpoint retains its credentials across all three clients."""
        for relative, key, field in [(".codex/config.toml", "mcp_servers", "env_http_headers"),
                                     (".grok/config.toml", "mcp_servers", "headers"),
                                     (".claude.json", "mcpServers", "headers")]:
            config = {key: {"linear": {"url": "https://mcp.linear.app/mcp",
                                      field: {"Authorization": "private-placeholder"}}}}
            self._write(relative, tomlkit.dumps(config) if relative.endswith(".toml") else json.dumps(config))
        self._run()
        for relative, key, field in [(".codex/config.toml", "mcp_servers", "env_http_headers"),
                                     (".grok/config.toml", "mcp_servers", "headers"),
                                     (".claude.json", "mcpServers", "headers")]:
            self.assertEqual(self._read(relative)[key]["linear"][field]["Authorization"], "private-placeholder")
        self._run("verify")

    def test_command_changes_reject_existing_environment_credentials(self):
        """Replacing a stdio command cannot transfer its private environment."""
        self._write(".codex/config.toml", tomlkit.dumps({"mcp_servers": {"railway": {
            "command": "previous-command", "args": ["mcp"], "env": {"TOKEN": "private-placeholder"}
        }}}))
        before = self._snapshot()
        result = self._run(ok=False)
        self.assertNotIn("private-placeholder", result.stdout + result.stderr)
        self.assertEqual(before, self._snapshot())

    def test_unauthenticated_endpoint_change_preserves_portable_settings(self):
        """Endpoint updates without credentials retain timeouts and tool restrictions."""
        self._write(".codex/config.toml", tomlkit.dumps({"mcp_servers": {"linear": {
            "url": "https://old.example.org/mcp", "tool_timeout_sec": 30, "disabled_tools": ["delete"]
        }}}))
        self._run()
        server = self._read(".codex/config.toml")["mcp_servers"]["linear"]
        self.assertEqual(server["url"], "https://mcp.linear.app/mcp")
        self.assertEqual(server["disabled_tools"], ["delete"])
        self.assertEqual(server["tool_timeout_sec"], 30)

    def test_plugins_install_once_and_missing_artifacts_fail_verification(self):
        """Enabled settings alone never masquerade as an installed plugin."""
        self._run()
        self._run("verify-plugins", ok=False)
        self._run("install-plugins")
        self._run("verify-plugins")
        self._run("install-plugins")
        log = (self.home / ".claude/plugins/test-commands.log").read_text().splitlines()
        installs = [json.loads(line) for line in log if json.loads(line)[:2] == ["plugin", "install"]]
        self.assertEqual(len(installs), 3)
        manifest = next((self.home / ".claude/plugins/cache").glob("*/.claude-plugin/plugin.json"))
        manifest.unlink()
        self._run("verify-plugins", ok=False)
        self._run("install-plugins")
        self._run("verify-plugins")

    def test_plugin_failure_and_old_cli_are_reported_without_private_output(self):
        """A failed vendor command cannot leak its captured output."""
        self.env["TEST_PLUGIN_FAILURE"] = "1"
        result = self._run("install-plugins", ok=False)
        self.assertNotIn("private-placeholder", result.stdout + result.stderr)
        self.env.pop("TEST_PLUGIN_FAILURE")
        self.env["TEST_CLAUDE_VERSION"] = "2.1.100"
        result = self._run("install-plugins", ok=False)
        self.assertIn("claude update", result.stderr)

    def test_unexpected_marketplace_is_not_used(self):
        """A conflicting marketplace source is never trusted because its name matches."""
        self._write(".claude/plugins/known_marketplaces.json", json.dumps({
            "claude-plugins-official": {"source": {"source": "github", "repo": "other/repo"}}
        }))
        self._run("install-plugins", ok=False)
        self.assertFalse((self.home / ".claude/plugins/installed_plugins.json").exists())


if __name__ == "__main__":
    unittest.main()
