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
import git_history  # noqa: E402


class PartnerTurnTests(unittest.TestCase):
    """Verify command safety, schema normalization, and preserved diagnostics."""

    def _git(self, repository: Path, *arguments: str) -> str:
        return partner_turn._run_git(repository, *arguments).stdout.decode("utf-8").strip()

    def _commit_file(self, repository: Path, contents: str, message: str) -> str:
        (repository / "tracked.txt").write_text(contents, encoding="utf-8")
        self._git(repository, "add", "tracked.txt")
        self._git(
            repository, "-c", "user.name=Collab Test",
            "-c", "user.email=collab@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "--quiet", "-m", message,
        )
        return self._git(repository, "rev-parse", "HEAD")

    def _args(self, **overrides: object) -> argparse.Namespace:
        values = {
            "resume_session_id": None,
            "model": None,
            "effort": None,
            "max_budget_usd": None,
            "grok_safety": "tool-restricted",
            "grok_max_turns": 30,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_cli_model_defaults_and_overrides_reach_partner_commands(self) -> None:
        """CLI defaults select the requested models and preserve explicit overrides."""
        cases = (
            ([], "claude-fable-5-1"),
            (["--provider", "claude"], "claude-fable-5-1"),
            (["--provider", "grok"], "grok-4.6"),
            (["--provider", "claude", "--model", "sonnet"], "sonnet"),
            (["--provider", "grok", "--model", "custom-grok"], "custom-grok"),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = partner_turn._TurnPaths(
                cwd=root,
                prompt=root / "brief.md",
                output=root / "round.json",
                stderr=root / "round.json.stderr",
            )
            for selectors, expected_model in cases:
                with self.subTest(selectors=selectors):
                    args = partner_turn._parse_args(
                        [
                            "--cwd", str(paths.cwd),
                            "--prompt-file", str(paths.prompt),
                            "--output-file", str(paths.output),
                            *selectors,
                        ]
                    )
                    self.assertEqual(args.effort, "high")
                    if args.provider == "claude":
                        command = partner_turn._build_claude_command("/bin/claude", args)
                    else:
                        command, execution_cwd = partner_turn._build_grok_command(
                            "/bin/grok", args, paths, "problem", supports_prompt_file=True
                        )
                        self.assertEqual(args.grok_safety, "tool-restricted")
                        self.assertEqual(execution_cwd, root)
                        self.assertNotIn("--sandbox", command)
                        self.assertEqual(
                            command[command.index("--tools") + 1],
                            "read_file,grep,list_dir,run_terminal_cmd",
                        )
                        self.assertIn(f"Bash({partner_turn._history_command()} *)", command)
                    self.assertEqual(command[command.index("--model") + 1], expected_model)

    def test_claude_command_is_isolated_and_allows_history_queries(self) -> None:
        """Claude isolates customizations and explicitly permits the history helper."""
        command = partner_turn._build_claude_command("/bin/claude", self._args())

        self.assertIn("--safe-mode", command)
        self.assertIn("--restricted", command)
        self.assertEqual(command[command.index("--tools") + 1], "Read,Grep,Glob,Bash")
        self.assertNotIn("plan", command)
        self.assertEqual(command[command.index("--permission-mode") + 1], "dontAsk")
        self.assertEqual(
            command[command.index("--allowedTools") + 1],
            f"Bash({partner_turn._history_command()} *)",
        )
        self.assertIn("Write", command[command.index("--disallowedTools") + 1])

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
            args = self._args(resume_session_id="session-1", grok_safety="sandboxed")

            command, execution_cwd = partner_turn._build_grok_command(
                "/bin/grok", args, paths, "problem", supports_prompt_file=True
            )

        self.assertEqual(execution_cwd, root)
        self.assertIn("--prompt-file", command)
        self.assertNotIn("-p", command)
        self.assertEqual(
            command[command.index("--tools") + 1], "read_file,grep,list_dir,run_terminal_cmd"
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
        self.assertNotIn(f"Bash({partner_turn._history_command()} *)", command)
        self.assertIn("run_terminal_cmd", command[command.index("--disallowed-tools") + 1])

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

    def test_repository_snapshot_excludes_untracked_and_keeps_git_history(self) -> None:
        """Partners receive current tracked files and independently readable commits."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            subprocess.run(
                ["git", "init", "--quiet", str(repository)], check=True
            )
            (repository / ".gitignore").write_text(".env\n", encoding="utf-8")
            self._git(repository, "add", ".gitignore")
            commit = self._commit_file(repository, "committed version\n", "initial content")
            (repository / "tracked.txt").write_text("working tree version\n", encoding="utf-8")
            (repository / ".env").write_text("private runtime value\n", encoding="utf-8")
            (repository / "untracked.txt").write_text("private draft\n", encoding="utf-8")

            handle, snapshot, labels = partner_turn._create_repository_snapshot(
                repository
            )
            self.addCleanup(handle.cleanup)

            self.assertEqual(
                (snapshot / "tracked.txt").read_text(encoding="utf-8"),
                "working tree version\n",
            )
            self.assertFalse((snapshot / ".env").exists())
            self.assertFalse((snapshot / "untracked.txt").exists())
            self.assertTrue((snapshot / ".git").is_dir())
            self.assertEqual(self._git(snapshot, "rev-parse", "HEAD"), commit)
            self.assertEqual(self._git(snapshot, "show", "HEAD:tracked.txt"), "committed version")
            self.assertIn("+working tree version", self._git(snapshot, "diff", "HEAD"))
            self.assertEqual(labels, [])

    def test_snapshot_omits_local_git_state_and_stashed_untracked_content(self) -> None:
        """Committed refs survive without source config, hooks, reflogs, or stash objects."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            self._git(repository, "init", "--quiet")
            commit = self._commit_file(repository, "committed\n", "initial")
            self._git(repository, "update-ref", "refs/remotes/origin/main", commit)
            self._git(repository, "tag", "v1")
            self._git(
                repository, "config", "remote.origin.url", "https://example.invalid/private.git"
            )
            self._git(repository, "config", "alias.private-setting", "private configuration")
            (repository / ".git" / "private-note").write_text("local state\n", encoding="utf-8")
            (repository / ".git" / "hooks").mkdir(exist_ok=True)
            (repository / ".git" / "hooks" / "post-checkout").write_text(
                "#!/bin/sh\nexit 1\n", encoding="utf-8"
            )
            (repository / "untracked.txt").write_text("private stash draft\n", encoding="utf-8")
            self._git(
                repository, "-c", "user.name=Collab Test",
                "-c", "user.email=collab@example.invalid",
                "stash", "push", "--include-untracked", "--quiet",
            )
            stash_blob = self._git(repository, "rev-parse", "refs/stash^3:untracked.txt")

            handle, snapshot, _ = partner_turn._create_repository_snapshot(repository)
            self.addCleanup(handle.cleanup)

            self.assertEqual(self._git(snapshot, "rev-parse", "refs/remotes/origin/main"), commit)
            self.assertEqual(self._git(snapshot, "rev-parse", "v1"), commit)
            self.assertNotIn("refs/stash", self._git(snapshot, "show-ref"))
            self.assertNotIn("private", self._git(snapshot, "config", "--local", "--list"))
            self.assertNotIn("remote.origin", self._git(snapshot, "config", "--local", "--list"))
            for excluded in ("hooks", "logs", "private-note", "objects/info/alternates"):
                self.assertFalse((snapshot / ".git" / excluded).exists(), excluded)
            missing_blob = partner_turn._run_git(
                snapshot, "cat-file", "-e", stash_blob, check=False
            )
            self.assertNotEqual(missing_blob.returncode, 0)

    def test_snapshot_preserves_a_linked_worktrees_own_head(self) -> None:
        """A linked worktree gets self-contained history at its own checked-out commit."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            repository.mkdir()
            self._git(repository, "init", "--quiet")
            self._commit_file(repository, "initial\n", "initial")
            linked = root / "linked"
            self._git(repository, "worktree", "add", "--quiet", "--detach", str(linked))
            commit = self._commit_file(linked, "linked content\n", "linked commit")

            handle, snapshot, _ = partner_turn._create_repository_snapshot(linked)
            self.addCleanup(handle.cleanup)

            self.assertTrue((linked / ".git").is_file())
            self.assertTrue((snapshot / ".git").is_dir())
            self.assertEqual(self._git(snapshot, "rev-parse", "HEAD"), commit)
            self.assertEqual(self._git(snapshot, "show", "HEAD:tracked.txt"), "linked content")

    def test_history_queries_read_commits_and_current_differences(self) -> None:
        """The allowed helper returns useful history without changing either repository."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            self._git(repository, "init", "--quiet")
            first = self._commit_file(repository, "first version\n", "initial version")
            self._commit_file(repository, "second version\n", "second change")
            (repository / "tracked.txt").write_text("working version\n", encoding="utf-8")
            (repository / "new.txt").write_text("newly tracked content\n", encoding="utf-8")
            self._git(repository, "add", "new.txt")
            handle, snapshot, _ = partner_turn._create_repository_snapshot(repository)
            self.addCleanup(handle.cleanup)
            before = self._git(snapshot, "status", "--porcelain")
            queries = (
                (["log", "--path", "tracked.txt"], "initial version"),
                (["show", "HEAD"], "+second version"),
                (["file", first, "tracked.txt"], "first version"),
                (["diff", first, "HEAD"], "+second version"),
                (["diff"], "+working version"),
                (["diff", "--path", "new.txt"], "+newly tracked content"),
                (["blame", "tracked.txt"], "second version"),
                (["branches"], "refs/heads/"),
            )
            for arguments, expected in queries:
                with self.subTest(arguments=arguments):
                    completed = subprocess.run(
                        [sys.executable, "-B", str(SCRIPTS_DIR / "git_history.py"), *arguments],
                        cwd=snapshot, capture_output=True, text=True, check=True,
                    )
                    self.assertIn(expected, completed.stdout)
            self.assertEqual(self._git(snapshot, "status", "--porcelain"), before)
            self.assertEqual((repository / "tracked.txt").read_text(), "working version\n")

    def test_history_queries_do_not_run_external_diff_or_textconv_drivers(self) -> None:
        """History inspection ignores executable Git content converters."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            self._git(repository, "init", "--quiet")
            (repository / ".gitattributes").write_text(
                "tracked.txt diff=custom\n", encoding="utf-8"
            )
            self._git(repository, "add", ".gitattributes")
            self._commit_file(repository, "first version\n", "initial")
            self._commit_file(repository, "second version\n", "changed")
            handle, snapshot, _ = partner_turn._create_repository_snapshot(repository)
            self.addCleanup(handle.cleanup)
            self._git(snapshot, "config", "diff.external", "false")
            self._git(snapshot, "config", "diff.custom.command", "false")
            self._git(snapshot, "config", "diff.custom.textconv", "false")
            queries = (
                ["show"], ["file", "HEAD", "tracked.txt"],
                ["diff", "HEAD~1", "HEAD"], ["blame", "tracked.txt"],
            )
            for arguments in queries:
                with self.subTest(arguments=arguments):
                    output = git_history._query(snapshot, git_history._parse_args(arguments))
                    self.assertIn(b"second version", output)

    def test_history_helper_rejects_writes_options_and_escaping_paths(self) -> None:
        """History queries cannot inject Git options, write files, or read outside the snapshot."""
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repo"
            repository.mkdir()
            self._git(repository, "init", "--quiet")
            self._commit_file(repository, "tracked\n", "initial")
            handle, snapshot, _ = partner_turn._create_repository_snapshot(repository)
            self.addCleanup(handle.cleanup)
            output = Path(directory) / "unwanted-output"
            queries = (
                ["show", f"--output={output}"],
                ["show", "--", f"--output={output}"],
                ["file", "HEAD", "../private"],
                ["file", "HEAD", str(output)],
                ["file", "HEAD", ".git/config"],
                ["reset", "--hard"],
                ["show", "--ext-diff"],
                ["show", "--textconv"],
            )
            for arguments in queries:
                with self.subTest(arguments=arguments):
                    completed = subprocess.run(
                        [sys.executable, "-B", str(SCRIPTS_DIR / "git_history.py"), *arguments],
                        cwd=snapshot, capture_output=True, text=True, check=False,
                    )
                    self.assertNotEqual(completed.returncode, 0)
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(partner_turn._PartnerError, "snapshot root"):
                git_history._query(repository, git_history._parse_args(["log"]))

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
