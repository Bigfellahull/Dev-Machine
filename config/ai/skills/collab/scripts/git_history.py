#!/usr/bin/env python3
"""Expose read-only Git history queries inside a collab repository snapshot."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Sequence

from partner_turn import _PartnerError, _positive_int, _run_git


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    log = commands.add_parser("log", help="List commits with optional path filtering")
    log.add_argument("revision", nargs="?", default="HEAD")
    log.add_argument("--limit", type=_positive_int, default=40)
    log.add_argument("--path")
    show = commands.add_parser("show", help="Show a commit message and patch")
    show.add_argument("revision", nargs="?", default="HEAD")
    show.add_argument("--path")
    file = commands.add_parser("file", help="Read a file at a committed revision")
    file.add_argument("revision")
    file.add_argument("path")
    diff = commands.add_parser("diff", help="Compare commits or a commit with the snapshot")
    diff.add_argument("revision", nargs="?", default="HEAD")
    diff.add_argument("target", nargs="?")
    diff.add_argument("--path")
    blame = commands.add_parser("blame", help="Show line provenance at a committed revision")
    blame.add_argument("path")
    blame.add_argument("--revision", default="HEAD")
    commands.add_parser("branches", help="List the snapshot's branches and tags")
    return parser.parse_args(argv)


def _relative_path(value: str) -> str:
    path = Path(value)
    if (
        not value
        or path.is_absolute()
        or ".." in path.parts
        or any(part.lower() == ".git" for part in path.parts)
    ):
        raise _PartnerError("path must stay within tracked repository content", exit_code=77)
    return str(path)


def _commit(repository: Path, revision: str) -> str:
    return _run_git(
        repository, "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"
    ).stdout.decode("ascii").strip()


def _query(repository: Path, args: argparse.Namespace) -> bytes:
    if not (repository / ".git" / "collab-snapshot").is_file():
        raise _PartnerError("run history queries from the collab snapshot root", exit_code=77)
    if args.command == "branches":
        return _run_git(
            repository, "for-each-ref", "--format=%(objectname) %(refname)",
            "refs/heads", "refs/remotes", "refs/tags",
        ).stdout

    revision = _commit(repository, args.revision)
    path = _relative_path(args.path) if args.path is not None else None
    no_drivers = ["--no-ext-diff", "--no-textconv", "--no-color"]
    if args.command == "log":
        command = [
            "log", "--format=fuller", "--no-notes", "--no-show-signature",
            f"--max-count={args.limit}", *no_drivers, revision,
        ]
    elif args.command == "show":
        command = [
            "show", "--format=fuller", "--no-notes", "--no-show-signature",
            *no_drivers, revision,
        ]
    elif args.command == "file":
        return _run_git(repository, "show", *no_drivers, f"{revision}:{path}").stdout
    elif args.command == "diff":
        command = ["diff", *no_drivers, revision]
        if args.target:
            command.append(_commit(repository, args.target))
    else:
        command = ["blame", "--no-textconv", "--no-progress", revision]
    command.append("--")
    if path is not None:
        command.append(path)
    return _run_git(repository, "--literal-pathspecs", *command).stdout


def main(argv: Sequence[str] | None = None) -> int:
    """Run a validated history query without accepting arbitrary Git options."""
    args = _parse_args(argv)
    try:
        output = _query(Path.cwd(), args)
    except _PartnerError as error:
        print(f"git_history.py: {error}", file=sys.stderr)
        return error.exit_code
    sys.stdout.buffer.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
