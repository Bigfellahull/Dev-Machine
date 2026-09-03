"""Tests for the provider-neutral collab helper."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import partner_turn  # noqa: E402


class PartnerTurnTests(unittest.TestCase):
    """Verify command safety, schema normalization, and preserved diagnostics."""

    def _args(self, **overrides: object) -> argparse.Namespace:
        values = {
            "resume_session_id": None,
            "model": None,
            "effort": None,
            "max_budget_usd": None,
            "grok_safety": "sandboxed",
            "grok_max_turns": 30,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_claude_command_is_isolated_and_has_no_shell(self) -> None:
        """Claude uses isolated read tools without plan mode or shell access."""
        command = partner_turn._build_claude_command("/bin/claude", self._args())

        self.assertIn("--safe-mode", command)
        self.assertIn("--restricted", command)
        self.assertEqual(command[command.index("--tools") + 1], "Read,Grep,Glob")
        self.assertNotIn("plan", command)
        self.assertIn("Bash", command[command.index("--disallowedTools") + 1])

    def test_grok_prompt_file_command_is_read_only_and_resumable(self) -> None:
        """Grok uses prompt-file input, read tools, sandboxing, and resume."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / "brief.md"
            output_parent = root / "scratch"
            output_parent.mkdir()
            prompt.write_text("problem", encoding="utf-8")
            paths = partner_turn._TurnPaths(
                cwd=root,
                prompt=prompt,
                output=output_parent / "round.json",
                stderr=output_parent / "round.json.stderr",
            )
            args = self._args(resume_session_id="session-1")

            command, execution_cwd = partner_turn._build_grok_command(
                "/bin/grok", args, paths, "problem", supports_prompt_file=True
            )

        self.assertEqual(execution_cwd, root)
        self.assertIn("--prompt-file", command)
        self.assertNotIn("-p", command)
        self.assertEqual(
            command[command.index("--tools") + 1], "read_file,grep,list_dir"
        )
        self.assertEqual(command[command.index("--sandbox") + 1], "read-only")
        self.assertEqual(command[command.index("--resume") + 1], "session-1")

    def test_grok_context_only_uses_scratch_directory_and_no_tools(self) -> None:
        """Context-only mode hides the repository and removes built-in tools."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            scratch = root / "scratch"
            repository.mkdir()
            scratch.mkdir()
            prompt = scratch / "brief.md"
            prompt.write_text("problem", encoding="utf-8")
            paths = partner_turn._TurnPaths(
                cwd=repository,
                prompt=prompt,
                output=scratch / "round.json",
                stderr=scratch / "round.json.stderr",
            )

            command, execution_cwd = partner_turn._build_grok_command(
                "/bin/grok",
                self._args(grok_safety="context-only"),
                paths,
                "problem",
                supports_prompt_file=True,
            )

        self.assertEqual(execution_cwd, scratch)
        self.assertEqual(command[command.index("--cwd") + 1], str(scratch))
        self.assertEqual(command[command.index("--tools") + 1], "")
        self.assertNotIn("--sandbox", command)

    def test_partner_responses_are_normalized(self) -> None:
        """Provider-specific response fields map to one internal contract."""
        claude = partner_turn._parse_partner_response(
            "claude",
            {"session_id": "c-1", "result": "Claude answer"},
            "opus",
        )
        grok = partner_turn._parse_partner_response(
            "grok",
            {
                "sessionId": "g-1",
                "text": "Grok answer",
                "stopReason": "end_turn",
                "total_cost_usd": 0.01,
                "modelUsage": {"grok-4.6-build": {}},
            },
            None,
        )

        self.assertEqual((claude.session_id, claude.answer), ("c-1", "Claude answer"))
        self.assertEqual((grok.session_id, grok.answer), ("g-1", "Grok answer"))
        self.assertEqual(grok.stop_reason, "end_turn")
        self.assertEqual(grok.model, "grok-4.6-build")

    def test_secret_scan_reports_labels_without_secret_values(self) -> None:
        """Credential scanning identifies categories without echoing credentials."""
        cases = (
            ("private key", "-----BEGIN " + "PRIVATE KEY-----", "private key"),
            ("AWS long-term", "AK" + "IA" + "A" * 16, "AWS access key"),
            ("AWS temporary", "AS" + "IA" + "B" * 16, "AWS access key"),
            ("Slack", "xox" + "b-" + "c" * 24, "Slack token"),
            ("API", "xa" + "i-" + "d" * 24, "API key"),
            ("GitHub classic", "gh" + "p_" + "e" * 24, "GitHub token"),
            (
                "GitHub fine-grained",
                "github" + "_pat_" + "f" * 24,
                "GitHub token",
            ),
            ("GitLab", "gl" + "pat-" + "g" * 24, "GitLab token"),
        )

        for case_name, value, expected_label in cases:
            with self.subTest(case_name):
                self.assertEqual(
                    partner_turn._find_secret_labels(f"token {value}"),
                    [expected_label],
                )

    def test_repository_snapshot_excludes_untracked_and_git_metadata(self) -> None:
        """Partners receive tracked working files without private untracked state."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            subprocess.run(
                ["git", "init", "--quiet", str(repository)], check=True
            )
            (repository / ".gitignore").write_text(".env\n", encoding="utf-8")
            tracked = repository / "tracked.txt"
            tracked.write_text("indexed version\n", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(repository), "add", ".gitignore", "tracked.txt"],
                check=True,
            )
            tracked.write_text("working tree version\n", encoding="utf-8")
            (repository / ".env").write_text("private runtime value\n", encoding="utf-8")

            handle, snapshot, labels = partner_turn._create_repository_snapshot(
                repository
            )
            self.addCleanup(handle.cleanup)

            self.assertEqual(
                (snapshot / "tracked.txt").read_text(encoding="utf-8"),
                "working tree version\n",
            )
            self.assertFalse((snapshot / ".env").exists())
            self.assertFalse((snapshot / ".git").exists())
            self.assertEqual(labels, [])

    def test_repository_snapshot_scans_tracked_content(self) -> None:
        """Tracked credential-shaped content is detected before a partner call."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            subprocess.run(
                ["git", "init", "--quiet", str(repository)], check=True
            )
            token = "github" + "_pat_" + "h" * 24
            (repository / "tracked.txt").write_text(token, encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(repository), "add", "tracked.txt"], check=True
            )

            handle, _, labels = partner_turn._create_repository_snapshot(repository)
            self.addCleanup(handle.cleanup)

            self.assertEqual(labels, ["GitHub token"])

    def test_repository_snapshot_rejects_escaping_symlinks(self) -> None:
        """A tracked symlink cannot expose a path outside the sanitized snapshot."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            subprocess.run(
                ["git", "init", "--quiet", str(repository)], check=True
            )
            (repository / "escape").symlink_to("../private")
            subprocess.run(
                ["git", "-C", str(repository), "add", "escape"], check=True
            )

            with self.assertRaises(partner_turn._PartnerError):
                partner_turn._create_repository_snapshot(repository)

    def test_context_only_run_does_not_snapshot_the_repository(self) -> None:
        """Prompt-only Grok runs neither enumerate nor scan repository files."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            scratch = root / "scratch"
            repository.mkdir()
            scratch.mkdir()
            prompt = scratch / "brief.md"
            prompt.write_text("problem", encoding="utf-8")
            args = argparse.Namespace(
                provider="grok",
                grok_safety="context-only",
                cwd=repository,
                prompt_file=prompt,
                output_file=scratch / "round.json",
                skip_secret_scan=False,
            )
            expected = {"repository_scope": "prompt-only"}

            with mock.patch.object(
                partner_turn,
                "_create_repository_snapshot",
                side_effect=AssertionError("context-only must not snapshot"),
            ), mock.patch.object(
                partner_turn, "_run_partner", return_value=expected
            ) as run_partner:
                result = partner_turn._run(args)

            self.assertEqual(result, expected)
            called_paths = run_partner.call_args.args[1]
            self.assertEqual(called_paths.cwd, scratch.resolve())
            self.assertEqual(
                run_partner.call_args.kwargs["repository_scope"], "prompt-only"
            )

    def test_repository_snapshot_rejects_tracked_submodules(self) -> None:
        """A gitlink cannot be silently omitted from the partner's repository view."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            subprocess.run(
                ["git", "init", "--quiet", str(repository)], check=True
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repository),
                    "update-index",
                    "--add",
                    "--cacheinfo",
                    "160000," + "1" * 40 + ",dependency",
                ],
                check=True,
            )

            with self.assertRaisesRegex(
                partner_turn._PartnerError, "tracked submodules"
            ):
                partner_turn._create_repository_snapshot(repository)

    def test_output_inside_working_directory_is_rejected(self) -> None:
        """Raw partner transcripts cannot be written into the repository."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root.parent / f"{root.name}-brief.md"
            prompt.write_text("problem", encoding="utf-8")
            args = argparse.Namespace(
                cwd=root,
                prompt_file=prompt,
                output_file=root / "round.json",
            )
            self.addCleanup(prompt.unlink, missing_ok=True)

            with self.assertRaises(partner_turn._PartnerError):
                partner_turn._resolve_paths(args)

    def test_sandbox_fail_open_and_fail_closed_messages_are_detected(self) -> None:
        """Known Grok sandbox failure wording is treated as unsafe."""
        self.assertTrue(
            partner_turn._has_sandbox_failure(
                "warning: sandbox could not be applied; continuing without enforcement"
            )
        )
        self.assertTrue(
            partner_turn._has_sandbox_failure(
                "Refusing to start with its protections missing."
            )
        )

    def test_timeout_preserves_partial_stdout_and_stderr(self) -> None:
        """Timeout diagnostics remain available in the scratch artifacts."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = partner_turn._TurnPaths(
                cwd=root,
                prompt=root / "brief.md",
                output=root / "round.json",
                stderr=root / "round.json.stderr",
            )
            error = subprocess.TimeoutExpired(
                ["partner"], 10, output="partial output", stderr="partial error"
            )

            partner_turn._write_timeout_artifacts(paths, error)

            self.assertEqual(paths.output.read_text(encoding="utf-8"), "partial output")
            self.assertEqual(paths.stderr.read_text(encoding="utf-8"), "partial error")

    def test_grok_inspect_is_validated_and_preserved(self) -> None:
        """Grok's inherited configuration surface is stored as valid JSON."""
        completed = subprocess.CompletedProcess(
            ["grok", "inspect", "--json"], 0, stdout='{"hooks": []}', stderr=""
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "round.json"
            with mock.patch.object(partner_turn.subprocess, "run", return_value=completed):
                inspect_file = partner_turn._run_grok_inspect(
                    "/bin/grok", root, {}, output
                )

            self.assertEqual(
                inspect_file.read_text(encoding="utf-8"), '{"hooks": []}'
            )


if __name__ == "__main__":
    unittest.main()
