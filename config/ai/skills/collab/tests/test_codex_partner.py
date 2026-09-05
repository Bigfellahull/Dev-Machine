"""Exercise Codex partner turns through the real helper and a local CLI boundary."""

from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import partner_turn  # noqa: E402


_FAKE_CODEX = r'''
import json
import os
import pathlib
import sys

if "--help" in sys.argv:
    print("--json --sandbox --cd --ignore-user-config --ignore-rules --strict-config")
    raise SystemExit(0)

cwd = pathlib.Path.cwd()
record = {
    "arguments": sys.argv[1:],
    "cwd": str(cwd),
    "prompt": sys.stdin.read(),
    "tracked": (cwd / "tracked.txt").read_text(),
    "private_exists": (cwd / "private.txt").exists(),
    "git_snapshot": (cwd / ".git/collab-snapshot").exists(),
}
with open(os.environ["COLLAB_FAKE_LOG"], "a") as stream:
    stream.write(json.dumps(record) + "\n")
mode = os.environ.get("COLLAB_FAKE_MODE", "success")
if mode == "malformed":
    print("not json")
    raise SystemExit(0)
if mode == "sandbox_warning":
    print("sandbox could not be applied; continuing without enforcement", file=sys.stderr)
if mode in ("failure", "nonzero_failure"):
    print(json.dumps({"type": "turn.failed", "error": {"message": "authentication failed"}}))
    raise SystemExit(1 if mode == "nonzero_failure" else 0)
print(json.dumps({"type": "thread.started", "thread_id": "00000000-0000-4000-8000-000000000123"}))
print(json.dumps({"type": "turn.started"}))
print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": "Inspection update"}}))
answer = " " if mode == "empty" else "Use the independently verified plan."
print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": answer}}))
if mode != "unfinished":
    print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 100, "output_tokens": 20}}))
'''


class CodexPartnerTests(unittest.TestCase):
    """Verify normalized output, resume routing, snapshot boundaries, and failures."""

    def setUp(self) -> None:
        """Create an isolated repository and substitute only the provider executable."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repository = self.root / "repo"
        self.repository.mkdir()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()
        self.prompt = self.scratch / "brief.md"
        self.prompt.write_text("Investigate the neutral problem independently.")
        subprocess.run(["git", "init", "--quiet", str(self.repository)], check=True)
        (self.repository / "tracked.txt").write_text("current tracked evidence")
        (self.repository / "private.txt").write_text("untracked private content")
        subprocess.run(
            ["git", "-C", str(self.repository), "add", "tracked.txt"], check=True
        )
        binary_directory = self.root / "bin"
        binary_directory.mkdir()
        binary = binary_directory / "codex"
        binary.write_text(f"#!{sys.executable}\n" + _FAKE_CODEX)
        binary.chmod(0o700)
        self.log = self.scratch / "calls.jsonl"
        patch = mock.patch.dict(os.environ, {
            "PATH": str(binary_directory) + os.pathsep + os.environ.get("PATH", ""),
            "COLLAB_FAKE_LOG": str(self.log),
            "COLLAB_FAKE_MODE": "success",
        })
        patch.start()
        self.addCleanup(patch.stop)

    def _args(self, name: str = "round-0", *extra: str) -> list[str]:
        return [
            "--provider", "codex", "--cwd", str(self.repository),
            "--prompt-file", str(self.prompt),
            "--output-file", str(self.scratch / f"{name}.raw.json"), *extra,
        ]

    def _invoke(self, *arguments: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = partner_turn.main(list(arguments))
        return status, stdout.getvalue(), stderr.getvalue()

    def test_initial_and_resumed_turn_preserve_read_only_scope_and_context(self) -> None:
        """Both calls inspect snapshots and resume the exact selected session with stdin context."""
        status, stdout, stderr = self._invoke(*self._args())
        self.assertEqual(status, 0, stderr)
        first = json.loads(stdout)
        self.assertEqual(first["answer"], "Use the independently verified plan.")
        self.assertEqual(first["model"], "gpt-6-astra")
        self.assertEqual(first["usage"], {"input_tokens": 100, "output_tokens": 20})
        self.assertIsNone(first["cost_usd"])
        self.assertEqual(first["safety_mode"], "sandboxed-read-only")
        raw = Path(first["raw_output_file"]).read_text()
        self.assertEqual(json.loads(raw.splitlines()[0])["type"], "thread.started")

        packet = "Shared packet: Claude proposes A; Grok proposes B; Codex proposes C."
        self.prompt.write_text(packet)
        status, stdout, stderr = self._invoke(*self._args(
            "round-1", "--resume-session-id", first["session_id"],
            "--model", "requested-codex-model", "--effort", "high",
        ))
        self.assertEqual(status, 0, stderr)
        second = json.loads(stdout)
        self.assertEqual(second["session_id"], first["session_id"])
        self.assertEqual(second["model"], "requested-codex-model")
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]["prompt"], "Investigate the neutral problem independently.")
        self.assertEqual(calls[1]["prompt"], packet)
        self.assertEqual(calls[1]["arguments"][-3:], ["resume", first["session_id"], "-"])
        for call in calls:
            command = call["arguments"]
            self.assertEqual(command[command.index("--sandbox") + 1], "read-only")
            self.assertEqual(Path(command[command.index("--cd") + 1]).resolve(), Path(call["cwd"]).resolve())
            self.assertIn("--ignore-user-config", command)
            self.assertIn("--ignore-rules", command)
            for setting in (
                'approval_policy="never"', 'web_search="disabled"', 'agents.enabled=false',
                'features.hooks=false', 'features.plugins=false', 'features.apps=false',
            ):
                self.assertIn(setting, command)
            self.assertNotEqual(Path(call["cwd"]), self.repository)
            self.assertEqual(call["tracked"], "current tracked evidence")
            self.assertTrue(call["git_snapshot"])
            self.assertFalse(call["private_exists"])
            self.assertFalse(Path(call["cwd"]).exists())
        self.assertEqual((self.repository / "tracked.txt").read_text(), "current tracked evidence")
        self.assertEqual((self.repository / "private.txt").read_text(), "untracked private content")

    def test_unsuccessful_streams_never_produce_a_successful_answer(self) -> None:
        """Zero process exit cannot hide malformed, unfinished, empty, or unsafe results."""
        for mode, expected_status, detail in (
            ("malformed", 65, "invalid JSONL"),
            ("unfinished", 65, "did not complete"),
            ("empty", 65, "textual output"),
            ("failure", 69, "authentication failed"),
            ("nonzero_failure", 69, "authentication failed"),
            ("sandbox_warning", 77, "sandbox was not applied"),
        ):
            with self.subTest(mode=mode), mock.patch.dict(os.environ, {"COLLAB_FAKE_MODE": mode}):
                status, stdout, stderr = self._invoke(*self._args(mode))
                self.assertEqual(status, expected_status)
                self.assertEqual(stdout, "")
                self.assertIn(detail, stderr)
                self.assertTrue((self.scratch / f"{mode}.raw.json").exists())
                self.assertTrue((self.scratch / f"{mode}.raw.json.stderr").exists())

    def test_credentials_are_rejected_before_codex_starts(self) -> None:
        """Neither prompt nor tracked-file credentials reach the provider process."""
        token = "github" + "_pat_" + "h" * 24
        for target in (self.prompt, self.repository / "tracked.txt"):
            with self.subTest(target=target):
                previous = target.read_text()
                target.write_text(token)
                status, stdout, stderr = self._invoke(*self._args())
                target.write_text(previous)
                self.assertEqual(status, 77)
                self.assertEqual(stdout, "")
                self.assertIn("credentials", stderr)
                self.assertFalse(self.log.exists())

    def test_unsupported_budget_is_rejected_before_provider_calls(self) -> None:
        """A monetary ceiling cannot be silently ignored for Codex or Grok."""
        for provider in ("codex", "grok"):
            with self.subTest(provider=provider), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    partner_turn._parse_args([
                        *self._args(), "--provider", provider, "--max-budget-usd", "1",
                    ])
                self.assertEqual(raised.exception.code, 2)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
