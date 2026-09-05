#!/usr/bin/env python3
"""Run one resumable, read-only turn with a supported reasoning partner."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Sequence


_READ_ONLY_INSTRUCTION = (
    "Act as an independent reasoning partner. Inspect only the supplied working "
    "directory and context. Do not create, edit, move, or delete files; run shell "
    "commands except the supplied Git history helper; invoke subagents, skills, "
    "plugins, hooks, MCP tools, memory, or web "
    "tools; or change repository or external state. Support factual claims with "
    "specific evidence."
)
_DEFAULT_TIMEOUTS = {"claude": 600, "grok": 900, "codex": 900}
_DEFAULT_MODELS = {
    "claude": "claude-fable-5-1", "grok": "grok-4.6", "codex": "gpt-6-astra"
}
_SECRET_PATTERNS = (
    ("private key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("API key", re.compile(r"\b(?:sk|xai)-[A-Za-z0-9_-]{20,}\b")),
    (
        "GitHub token",
        re.compile(
            r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"
        ),
    ),
    ("GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
)
_SANDBOX_FAILURE_MARKERS = (
    "sandbox could not be applied",
    "could not apply the 'read-only' sandbox",
    "continuing without enforcement",
    "sandbox enforcement failed",
    "refusing to start with its protections missing",
)


class _PartnerError(Exception):
    def __init__(self, message: str, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class _TurnPaths:
    cwd: Path
    prompt: Path
    output: Path
    stderr: Path


@dataclass(frozen=True)
class _PartnerResponse:
    provider: str
    session_id: str
    answer: str
    stop_reason: str | None
    model: str | None
    usage: dict[str, Any] | None
    cost_usd: int | float | None


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _positive_decimal(value: str) -> Decimal:
    try:
        parsed = Decimal(value)
    except InvalidOperation as error:
        raise argparse.ArgumentTypeError("must be a decimal number") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one resumable, read-only partner turn."
    )
    parser.add_argument(
        "--provider", choices=("claude", "grok", "codex"), default="claude"
    )
    parser.add_argument("--cwd", required=True, type=Path, help="Repository root")
    parser.add_argument("--prompt-file", required=True, type=Path)
    parser.add_argument("--output-file", required=True, type=Path)
    parser.add_argument(
        "--resume-session-id",
        "--session-id",
        dest="resume_session_id",
        help="Partner session ID to resume; --session-id is a compatibility alias",
    )
    parser.add_argument(
        "--model",
        help="Provider model override (defaults: Claude claude-fable-5-1; Grok grok-4.6; Codex gpt-6-astra)",
    )
    parser.add_argument("--effort", help="Optional provider reasoning effort")
    parser.add_argument(
        "--timeout-seconds",
        type=_positive_int,
        help="Maximum turn duration; defaults to 600 for Claude and 900 for Grok/Codex",
    )
    parser.add_argument(
        "--max-budget-usd",
        type=_positive_decimal,
        help="Optional Claude API budget ceiling for this turn",
    )
    parser.add_argument(
        "--grok-max-turns",
        type=_positive_int,
        default=30,
        help="Maximum Grok agent turns (default: 30)",
    )
    parser.add_argument(
        "--grok-safety",
        choices=("sandboxed", "tool-restricted", "context-only"),
        default="tool-restricted",
        help="Grok safety mode (default: tool-restricted; read-only built-in tools)",
    )
    parser.add_argument(
        "--skip-secret-scan",
        action="store_true",
        help="Send a prompt containing a detected credential pattern",
    )
    args = parser.parse_args(argv)
    if args.max_budget_usd is not None and args.provider != "claude":
        parser.error("--max-budget-usd is supported only by Claude")
    if args.model is None:
        args.model = _DEFAULT_MODELS[args.provider]
    return args


def _resolve_paths(args: argparse.Namespace) -> _TurnPaths:
    cwd = args.cwd.expanduser().resolve()
    prompt = args.prompt_file.expanduser().resolve()
    output = args.output_file.expanduser().resolve()
    stderr = output.with_name(f"{output.name}.stderr")

    if not cwd.is_dir():
        raise _PartnerError(f"working directory does not exist: {cwd}")
    if not prompt.is_file():
        raise _PartnerError(f"prompt file does not exist: {prompt}")
    if not output.parent.is_dir():
        raise _PartnerError(f"output directory does not exist: {output.parent}")
    if prompt in (output, stderr):
        raise _PartnerError("output and stderr files must differ from the prompt file")
    if output.is_dir() or stderr.is_dir():
        raise _PartnerError("output and stderr paths must not be directories")
    if output == cwd or cwd in output.parents:
        raise _PartnerError("output file must be outside the working directory")

    return _TurnPaths(cwd=cwd, prompt=prompt, output=output, stderr=stderr)


def _find_secret_labels(prompt: str) -> list[str]:
    return [label for label, pattern in _SECRET_PATTERNS if pattern.search(prompt)]


def _git_environment() -> dict[str, str]:
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    environment.update(
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_TERMINAL_PROMPT="0",
        GIT_NO_REPLACE_OBJECTS="1",
        GIT_OPTIONAL_LOCKS="0",
    )
    return environment


def _run_git(
    repository: Path, *arguments: str, check: bool = True
) -> subprocess.CompletedProcess[bytes]:
    try:
        completed = subprocess.run(
            [
                "git", "--no-pager",
                "-c", f"core.hooksPath={os.devnull}",
                "-c", "core.fsmonitor=false",
                "-C", str(repository), *arguments,
            ],
            env=_git_environment(),
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as error:
        raise _PartnerError("git executable not found on PATH", exit_code=127) from error
    if check and completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise _PartnerError(
            f"Git operation failed: {detail or 'git failed'}",
            exit_code=69,
        )
    return completed


def _tracked_repository_paths(repository: Path) -> list[Path]:
    completed = _run_git(repository, "ls-files", "-z", "--stage")

    paths = []
    for index_record in completed.stdout.split(b"\0"):
        if not index_record:
            continue
        try:
            metadata, encoded_path = index_record.split(b"\t", 1)
            mode, _, stage = metadata.split(b" ", 2)
        except ValueError as error:
            raise _PartnerError("git returned malformed index data", exit_code=65) from error
        if mode == b"160000":
            raise _PartnerError(
                "tracked submodules are not supported by the sanitized snapshot",
                exit_code=77,
            )
        if stage != b"0":
            raise _PartnerError(
                "unmerged index entries are not supported by the sanitized snapshot",
                exit_code=77,
            )
        relative_path = Path(os.fsdecode(encoded_path))
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise _PartnerError("git returned an unsafe tracked path", exit_code=77)
        paths.append(relative_path)
    return paths


def _copy_regular_file(source: Path, destination: Path) -> None:
    open_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    source_descriptor = os.open(source, open_flags)
    try:
        source_stat = os.fstat(source_descriptor)
        if not stat.S_ISREG(source_stat.st_mode):
            raise _PartnerError(
                f"tracked path changed while preparing the snapshot: {source}",
                exit_code=77,
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        with os.fdopen(source_descriptor, "rb", closefd=False) as source_file:
            with destination.open("xb") as destination_file:
                shutil.copyfileobj(source_file, destination_file)
        destination.chmod(stat.S_IMODE(source_stat.st_mode))
    finally:
        os.close(source_descriptor)


def _snapshot_secret_labels(snapshot: Path) -> list[str]:
    labels: set[str] = set()
    for candidate in snapshot.rglob("*"):
        if not candidate.is_file() or candidate.is_symlink():
            continue
        with candidate.open("r", encoding="utf-8", errors="ignore") as source_file:
            for line in source_file:
                labels.update(_find_secret_labels(line))
    return sorted(labels)


def _copy_git_history(repository: Path, snapshot: Path) -> None:
    # Transport cloning excludes local-only objects such as stashed untracked files.
    _run_git(
        repository,
        "clone", "--bare", "--no-local", "--template=", "--quiet",
        "--", str(repository), str(snapshot / ".git"),
    )
    _run_git(
        snapshot, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head",
        str(repository), "+refs/remotes/*:refs/remotes/*",
    )
    _run_git(snapshot, "config", "--local", "core.bare", "false")
    _run_git(snapshot, "config", "--local", "--remove-section", "remote.origin")
    head = _run_git(snapshot, "rev-parse", "--verify", "--quiet", "HEAD", check=False)
    _run_git(snapshot, "read-tree", "HEAD" if head.returncode == 0 else "--empty")
    _run_git(snapshot, "add", "--intent-to-add", "--all", "--force")
    (snapshot / ".git" / "collab-snapshot").write_text("1\n", encoding="utf-8")


def _create_repository_snapshot(
    repository: Path,
) -> tuple[tempfile.TemporaryDirectory[str], Path, list[str]]:
    temporary_directory = tempfile.TemporaryDirectory(prefix="collab-repository-")
    snapshot = Path(temporary_directory.name)
    symlinks: list[tuple[Path, str]] = []
    try:
        for relative_path in _tracked_repository_paths(repository):
            source = repository / relative_path
            try:
                source_stat = source.lstat()
            except FileNotFoundError:
                continue
            destination = snapshot / relative_path
            if stat.S_ISREG(source_stat.st_mode):
                _copy_regular_file(source, destination)
            elif stat.S_ISLNK(source_stat.st_mode):
                link_target = os.readlink(source)
                if Path(link_target).is_absolute():
                    raise _PartnerError(
                        f"tracked symlink has an absolute target: {relative_path}",
                        exit_code=77,
                    )
                normalized_target = Path(
                    os.path.normpath(str(destination.parent / link_target))
                )
                if normalized_target != snapshot and snapshot not in normalized_target.parents:
                    raise _PartnerError(
                        f"tracked symlink escapes the repository: {relative_path}",
                        exit_code=77,
                    )
                symlinks.append((destination, link_target))
            elif stat.S_ISDIR(source_stat.st_mode):
                continue
            else:
                raise _PartnerError(
                    f"tracked path has an unsupported file type: {relative_path}",
                    exit_code=77,
                )

        for destination, link_target in symlinks:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(link_target)
        secret_labels = _snapshot_secret_labels(snapshot)
        _copy_git_history(repository, snapshot)
        return temporary_directory, snapshot, secret_labels
    except Exception:
        temporary_directory.cleanup()
        raise


def _read_cli_help(executable: str, cwd: Path, *subcommands: str) -> str:
    try:
        completed = subprocess.run(
            [executable, *subcommands, "--help"],
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as error:
        raise _PartnerError(
            f"{Path(executable).name} --help exceeded 30 seconds", exit_code=124
        ) from error
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "no error detail"
        raise _PartnerError(
            f"{Path(executable).name} --help exited with status "
            f"{completed.returncode}: {detail}",
            exit_code=69,
        )
    return completed.stdout


def _require_flags(provider: str, help_text: str, flags: Sequence[str]) -> None:
    missing = [flag for flag in flags if flag not in help_text]
    if missing:
        joined = ", ".join(missing)
        raise _PartnerError(
            f"installed {provider} CLI lacks required safety flags: {joined}",
            exit_code=69,
        )


def _history_command() -> str:
    script = Path(__file__).resolve().with_name("git_history.py")
    return shlex.join([sys.executable, "-B", str(script)])


def _partner_instruction(history_access: bool = True) -> str:
    if not history_access:
        return _READ_ONLY_INSTRUCTION + " No Git history helper is available in this mode."
    return (
        _READ_ONLY_INSTRUCTION
        + " The working directory contains tracked working-tree files and isolated Git "
        "history. For read-only history queries, run "
        + _history_command()
        + " from the snapshot root, followed by: log [revision] [--limit N] [--path path]; "
        "show [revision] [--path path]; file revision path; diff [revision] [target] "
        "[--path path]; blame path [--revision revision]; or branches. Use the helper "
        "instead of raw git commands. Do not use shell redirection, pipelines, or "
        "compound commands. Other executable checks must be requested from the lead agent."
    )


def _build_claude_command(
    executable: str, args: argparse.Namespace
) -> list[str]:
    command = [
        executable,
        "--print",
        "--output-format",
        "json",
        "--safe-mode",
        "--restricted",
        "--strict-mcp-config",
        "--permission-mode",
        "dontAsk",
        "--tools",
        "Read,Grep,Glob,Bash",
        "--allowedTools",
        f"Bash({_history_command()} *)",
        "--disallowedTools",
        "Edit,Write,NotebookEdit",
        "--append-system-prompt",
        _partner_instruction(),
    ]
    if args.resume_session_id:
        command.extend(("--resume", args.resume_session_id))
    if args.model:
        command.extend(("--model", args.model))
    if args.effort:
        command.extend(("--effort", args.effort))
    if args.max_budget_usd is not None:
        command.extend(("--max-budget-usd", str(args.max_budget_usd)))
    return command


def _build_codex_command(
    executable: str, args: argparse.Namespace, cwd: Path
) -> list[str]:
    instruction = _partner_instruction().replace(
        "commands except the supplied Git history helper",
        "commands except read-only file inspection and the supplied Git history helper",
    )
    command = [
        executable, "exec", "--json", "--color", "never",
        "--sandbox", "read-only", "--cd", str(cwd),
        "--ignore-user-config", "--ignore-rules", "--strict-config",
    ]
    settings = {
        "approval_policy": "never",
        "web_search": "disabled",
        "project_doc_max_bytes": 0,
        "agents.enabled": False,
        "features.apps": False,
        "features.plugins": False,
        "features.hooks": False,
        "features.memories": False,
        "features.browser_use": False,
        "features.computer_use": False,
        "features.shell_snapshot": False,
        "allow_login_shell": False,
        "shell_environment_policy.inherit": "core",
        "shell_environment_policy.ignore_default_excludes": False,
        "developer_instructions": instruction,
    }
    for key, value in settings.items():
        command.extend(("--config", f"{key}={json.dumps(value)}"))
    if args.model:
        command.extend(("--model", args.model))
    if args.effort:
        command.extend(("--config", f"model_reasoning_effort={json.dumps(args.effort)}"))
    if args.resume_session_id:
        command.extend(("resume", args.resume_session_id))
    command.append("-")
    return command


def _parse_codex_response(stdout: str, requested_model: str | None) -> _PartnerResponse:
    session_id = None
    answer = None
    usage = None
    completed = False
    for line in stdout.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as error:
            raise _PartnerError(f"codex returned invalid JSONL: {error}", exit_code=65) from error
        if not isinstance(event, dict):
            raise _PartnerError("codex event must be a JSON object", exit_code=65)
        kind = event.get("type")
        if kind in ("error", "turn.failed"):
            detail = event.get("error") or event.get("message") or "no error detail"
            raise _PartnerError(f"codex reported an error: {detail}", exit_code=69)
        if kind == "thread.started":
            session_id = event.get("thread_id")
        elif kind == "item.completed":
            item = event.get("item")
            if isinstance(item, dict) and item.get("type") == "agent_message":
                answer = item.get("text")
        elif kind == "turn.completed":
            completed = True
            usage = event.get("usage")
    if not completed:
        raise _PartnerError("codex stream did not complete its turn", exit_code=65)
    return _parse_partner_response(
        "codex",
        {"sessionId": session_id, "text": answer, "usage": usage, "stopReason": "completed"},
        requested_model,
    )


def _build_grok_command(
    executable: str,
    args: argparse.Namespace,
    paths: _TurnPaths,
    prompt: str,
    supports_prompt_file: bool,
) -> tuple[list[str], Path]:
    execution_cwd = paths.prompt.parent if args.grok_safety == "context-only" else paths.cwd
    command = [executable]
    if supports_prompt_file:
        command.extend(("--prompt-file", str(paths.prompt)))
    else:
        if len(prompt.encode("utf-8")) > 200_000:
            raise _PartnerError(
                "installed Grok CLI lacks --prompt-file and the prompt is too large "
                "for the compatibility fallback",
                exit_code=69,
            )
        command.extend(("-p", prompt))

    tools = "" if args.grok_safety == "context-only" else "read_file,grep,list_dir,run_terminal_cmd"
    agent_profile = Path(__file__).resolve().parent.parent / "agents" / "grok-partner.md"
    command.extend(
        (
            "--output-format",
            "json",
            "--cwd",
            str(execution_cwd),
            "--permission-mode",
            "dontAsk",
            "--tools",
            tools,
            "--disallowed-tools",
            "search_replace,Agent" if tools else "search_replace,run_terminal_cmd,Agent",
            "--disable-web-search",
            "--no-subagents",
            "--deny",
            "MCPTool(*)",
            "--agent",
            str(agent_profile),
            "--rules",
            _partner_instruction(history_access=bool(tools)),
            "--max-turns",
            str(args.grok_max_turns),
        )
    )
    if tools:
        command.extend(("--allow", "Read", "--allow", "Grep"))
        command.extend(("--allow", f"Bash({_history_command()} *)"))
    if args.grok_safety == "sandboxed":
        command.extend(("--sandbox", "read-only"))
    if args.resume_session_id:
        command.extend(("--resume", args.resume_session_id))
    if args.model:
        command.extend(("--model", args.model))
    if args.effort:
        command.extend(("--reasoning-effort", args.effort))
    return command, execution_cwd


def _grok_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "GROK_MEMORY": "0",
            "GROK_SUBAGENTS": "0",
            "GROK_WEB_FETCH": "0",
        }
    )
    return environment


def _run_grok_inspect(
    executable: str,
    cwd: Path,
    environment: dict[str, str],
    output_file: Path,
) -> Path:
    inspect_file = output_file.with_name(f"{output_file.name}.preflight.json")
    try:
        completed = subprocess.run(
            [executable, "inspect", "--json"],
            cwd=cwd,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as error:
        raise _PartnerError("grok inspect exceeded 30 seconds", exit_code=124) from error
    inspect_file.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "no error detail"
        raise _PartnerError(
            f"grok inspect exited with status {completed.returncode}: {detail}",
            exit_code=69,
        )
    try:
        inspected = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise _PartnerError(
            f"grok inspect returned invalid JSON: {error}", exit_code=65
        ) from error
    if not isinstance(inspected, dict):
        raise _PartnerError("grok inspect JSON must be an object", exit_code=65)
    return inspect_file


def _coerce_output(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _write_timeout_artifacts(
    paths: _TurnPaths, error: subprocess.TimeoutExpired
) -> None:
    paths.output.write_text(_coerce_output(error.stdout), encoding="utf-8")
    paths.stderr.write_text(_coerce_output(error.stderr), encoding="utf-8")


def _has_sandbox_failure(stderr: str) -> bool:
    lowered = stderr.lower()
    return any(marker in lowered for marker in _SANDBOX_FAILURE_MARKERS)


def _infer_model(response: dict[str, Any], requested: str | None) -> str | None:
    if requested:
        return requested
    model_usage = response.get("modelUsage")
    if isinstance(model_usage, dict) and len(model_usage) == 1:
        model = next(iter(model_usage))
        if isinstance(model, str):
            return model
    model = response.get("model")
    return model if isinstance(model, str) else None


def _parse_partner_response(
    provider: str, response: Any, requested_model: str | None
) -> _PartnerResponse:
    if not isinstance(response, dict):
        raise _PartnerError(f"{provider} response JSON must be an object", exit_code=65)

    if provider == "claude":
        session_id = response.get("session_id")
        answer = response.get("result")
        stop_reason = response.get("stop_reason")
    else:
        session_id = response.get("sessionId")
        answer = response.get("text")
        stop_reason = response.get("stopReason")

    if response.get("is_error") is True or response.get("error"):
        detail = answer if isinstance(answer, str) and answer else response.get("error")
        raise _PartnerError(f"{provider} reported an error: {detail}", exit_code=69)
    if not isinstance(session_id, str) or not session_id:
        raise _PartnerError(
            f"{provider} response did not contain a session ID", exit_code=65
        )
    if not isinstance(answer, str) or not answer.strip():
        raise _PartnerError(
            f"{provider} response did not contain textual output", exit_code=65
        )

    usage = response.get("usage")
    return _PartnerResponse(
        provider=provider,
        session_id=session_id,
        answer=answer,
        stop_reason=stop_reason if isinstance(stop_reason, str) else None,
        model=_infer_model(response, requested_model),
        usage=usage if isinstance(usage, dict) else None,
        cost_usd=response.get("total_cost_usd")
        if isinstance(response.get("total_cost_usd"), (int, float))
        else None,
    )


def _failure_detail(
    provider: str, stdout: str, stderr: str, returncode: int
) -> str:
    if provider == "codex":
        for line in reversed(stdout.splitlines()):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and event.get("type") in ("error", "turn.failed"):
                detail = event.get("error") or event.get("message")
                if isinstance(detail, dict):
                    detail = detail.get("message")
                if isinstance(detail, str) and detail.strip():
                    return detail.strip()
    try:
        response = json.loads(stdout)
    except json.JSONDecodeError:
        response = None
    if isinstance(response, dict):
        candidate = response.get("result") if provider == "claude" else response.get("text")
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
        error = response.get("error")
        if isinstance(error, str) and error.strip():
            return error.strip()
    return stderr.strip() or f"no error detail (status {returncode})"


def _run_partner(
    args: argparse.Namespace,
    paths: _TurnPaths,
    prompt: str,
    repository_scope: str,
) -> dict[str, Any]:
    executable = shutil.which(args.provider)
    if executable is None:
        raise _PartnerError(
            f"{args.provider} executable not found on PATH", exit_code=127
        )
    subcommands = ("exec",) if args.provider == "codex" else ()
    help_text = _read_cli_help(executable, paths.cwd, *subcommands)
    preflight_file: Path | None = None
    execution_cwd = paths.cwd
    environment = None
    process_input = prompt

    if args.provider == "claude":
        _require_flags(
            "claude",
            help_text,
            (
                "--safe-mode",
                "--restricted",
                "--strict-mcp-config",
                "--tools",
                "--allowedTools",
                "--disallowedTools",
                "--permission-mode",
            ),
        )
        command = _build_claude_command(executable, args)
    elif args.provider == "codex":
        _require_flags(
            "codex exec", help_text,
            ("--json", "--sandbox", "--cd", "--ignore-user-config", "--ignore-rules", "--strict-config"),
        )
        command = _build_codex_command(executable, args, paths.cwd)
    else:
        _require_flags(
            "grok",
            help_text,
            (
                "--output-format",
                "--cwd",
                "--permission-mode",
                "--tools",
                "--disallowed-tools",
                "--disable-web-search",
                "--no-subagents",
                "--deny",
                "--agent",
                "--rules",
                "--max-turns",
            ),
        )
        command, execution_cwd = _build_grok_command(
            executable,
            args,
            paths,
            prompt,
            supports_prompt_file="--prompt-file" in help_text,
        )
        environment = _grok_environment()
        preflight_file = _run_grok_inspect(
            executable, execution_cwd, environment, paths.output
        )
        process_input = None

    timeout = args.timeout_seconds or _DEFAULT_TIMEOUTS[args.provider]
    try:
        completed = subprocess.run(
            command,
            cwd=execution_cwd,
            env=environment,
            input=process_input,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        _write_timeout_artifacts(paths, error)
        raise _PartnerError(
            f"{args.provider} exceeded the {timeout}-second timeout; partial output "
            "was preserved",
            exit_code=124,
        ) from error

    paths.output.write_text(completed.stdout, encoding="utf-8")
    paths.stderr.write_text(completed.stderr, encoding="utf-8")

    requires_sandbox = args.provider == "codex" or (
        args.provider == "grok" and args.grok_safety == "sandboxed"
    )
    if requires_sandbox and _has_sandbox_failure(completed.stderr):
        raise _PartnerError(
            f"{args.provider}'s read-only sandbox was not applied; refusing to continue with "
            "weaker protections",
            exit_code=77,
        )
    if completed.returncode != 0:
        detail = _failure_detail(
            args.provider, completed.stdout, completed.stderr, completed.returncode
        )
        raise _PartnerError(
            f"{args.provider} exited with status {completed.returncode}: {detail}",
            exit_code=69,
        )

    if args.provider == "codex":
        parsed = _parse_codex_response(completed.stdout, args.model)
    else:
        try:
            response = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise _PartnerError(
                f"{args.provider} returned invalid JSON: {error}", exit_code=65
            ) from error
        parsed = _parse_partner_response(args.provider, response, args.model)
    return {
        "provider": parsed.provider,
        "model": parsed.model,
        "session_id": parsed.session_id,
        "answer": parsed.answer,
        "result": parsed.answer,
        "stop_reason": parsed.stop_reason,
        "usage": parsed.usage,
        "cost_usd": parsed.cost_usd,
        "safety_mode": {
            "claude": "isolated-read-only",
            "codex": "sandboxed-read-only",
            "grok": args.grok_safety,
        }[args.provider],
        "repository_scope": repository_scope,
        "raw_output_file": str(paths.output),
        "stderr_file": str(paths.stderr),
        "preflight_file": str(preflight_file) if preflight_file else None,
    }


def _run(args: argparse.Namespace) -> dict[str, Any]:
    original_paths = _resolve_paths(args)
    prompt = original_paths.prompt.read_text(encoding="utf-8")
    secret_labels = _find_secret_labels(prompt)
    if secret_labels and not args.skip_secret_scan:
        raise _PartnerError(
            "prompt contains possible credentials: "
            f"{', '.join(secret_labels)}; remove them or obtain explicit approval "
            "before using --skip-secret-scan",
            exit_code=77,
        )

    if args.provider == "grok" and args.grok_safety == "context-only":
        prompt_only_paths = _TurnPaths(
            cwd=original_paths.prompt.parent,
            prompt=original_paths.prompt,
            output=original_paths.output,
            stderr=original_paths.stderr,
        )
        return _run_partner(
            args, prompt_only_paths, prompt, repository_scope="prompt-only"
        )

    snapshot_directory, snapshot_root, repository_secret_labels = (
        _create_repository_snapshot(original_paths.cwd)
    )
    try:
        if repository_secret_labels and not args.skip_secret_scan:
            raise _PartnerError(
                "tracked repository files contain possible credentials: "
                f"{', '.join(repository_secret_labels)}; remove them or obtain "
                "explicit approval before using --skip-secret-scan",
                exit_code=77,
            )
        snapshot_paths = _TurnPaths(
            cwd=snapshot_root,
            prompt=original_paths.prompt,
            output=original_paths.output,
            stderr=original_paths.stderr,
        )
        return _run_partner(
            args,
            snapshot_paths,
            prompt,
            repository_scope="tracked-working-tree-and-git-history-snapshot",
        )
    finally:
        snapshot_directory.cleanup()


def main(argv: Sequence[str] | None = None) -> int:
    """Run one provider turn and print its normalized response."""
    args = _parse_args(argv)
    try:
        result = _run(args)
    except _PartnerError as error:
        print(f"partner_turn.py: {error}", file=sys.stderr)
        return error.exit_code
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
