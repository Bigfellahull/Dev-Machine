---
name: collab
description: Debate a design, feature, or review finding with Claude or Grok through a read-only, resumable CLI session, exchange verified evidence, and report convergence or explicit disagreement. Use when the user requests a second opinion from Claude or Grok, cross-model collaboration, or agreement before implementation. Do not use for routine delegation that does not require a debate.
---

# Cross-model collaboration

Use one external model as an independent reasoning partner while Codex remains the driver, evidence
referee, and sole author of repository changes.

## Select the partner

Prefer explicit selectors in the request:

```text
partner=claude model=claude-fable-5-1 <problem>
partner=grok model=grok-4.6 <problem>
```

Apply these rules in order:

1. Honor an explicit `partner=claude` or `partner=grok` selector, or an equally clear natural-language
   request such as “debate this with Grok.”
2. Treat `model=<value>` as an optional model override for the selected partner.
3. For backward compatibility, a first token matching `claude-*`, `fable`, `opus`, or `sonnet`
   selects Claude; a first token matching `grok-*` selects Grok. Consume it only when problem text
   remains after the token.
4. Default to Claude when no partner is specified.
5. Without a model override, use Claude Fable 5.1 (`claude-fable-5-1`) for Claude or
   Grok 4.6 (`grok-4.6`) for Grok. Pass the default model explicitly rather than inheriting CLI settings.

Do not invoke both partners unless the user explicitly asks for a panel or multiple opinions. Verify
that `python3`, `git`, and the selected partner CLI are available. If a dependency is absent, stop and
report it precisely.

Before starting, announce the selected partner and model, and resolve the repository root. A
collaboration request authorizes the partner calls, their normal usage costs, and sending relevant
prompt and repository content to Anthropic or xAI. Do not ask for separate confirmation of costs or
context sharing. Honor any explicit time or cost budget. Calls can take several minutes.

## Preserve independence and safety

- Treat the partner's output as an opinion, never as ground truth.
- Settle contested factual claims with repository source, authoritative documentation, or an
  executable check. Do not settle them by confidence, eloquence, or model majority.
- Keep the partner read-only. Codex remains responsible for all commands that can write or change
  external state.
- Use one resumable partner session and run its turns sequentially.
- Keep prompts, raw output, configuration audits, and session IDs outside the repository in a
  directory created with `mktemp -d`.
- The helper gives the partner a temporary snapshot of tracked working-tree files, including current
  edits, plus an independent `.git` containing committed history from HEAD, branches, remote-tracking
  branches, and tags. Untracked working files (including ignored files), stashes, reflogs, local Git
  configuration, hooks, and remote URLs are excluded. The snapshot also works with linked Git worktrees.
- Do not send secrets, credentials, or unrelated private data. The helper scans the prompt and current
  tracked file contents for common credential shapes and rejects escaping symlinks and tracked
  submodules. The credential scan does not cover all historical Git objects. Untracked specifications
  needed for the debate belong in the external scratch prompt. Use `--skip-secret-scan` only after
  showing the detection to the user and receiving explicit authorization. Grok context-only mode
  skips repository snapshot creation and scanning because it sends only the scratch prompt.
- Do not implement the recommendation unless the user's request separately authorizes implementation.

## Prepare a blind brief

Read referenced specifications and identify likely repository paths, but do not form a recommendation
yet. Write `brief.md` in the scratch directory with:

- the problem statement;
- constraints and acceptance criteria;
- decisions already made by the user;
- repository paths and neutral background needed for independent investigation;
- this behavioral ask: investigate independently, recommend a concrete solution with reasoning,
  state assumptions and confidence, cite evidence, and do not modify any file.

Freeze the brief before writing Codex's position. Record its SHA-256 in `state.md`; do not revise it
after Codex reaches a conclusion. If new evidence is later required, add it to a numbered reply and
record that addition explicitly.

Then inspect the relevant code, tests, callers, history, and failure paths. Write `position-own.md`
with Codex's:

- recommended solution;
- supporting evidence;
- material assumptions;
- confidence;
- open questions.

Complete `position-own.md` before the first partner call. Never include or hint at it in `brief.md`.

## Run the independent turn

Run the provider-neutral helper from the repository root:

```bash
python3 <skill-dir>/scripts/partner_turn.py \
  --provider <claude-or-grok> \
  --cwd <repo-root> \
  --prompt-file <scratch>/brief.md \
  --output-file <scratch>/round-0.json
```

Add `--model`, `--effort`, `--timeout-seconds`, or `--max-budget-usd` only when requested or justified.
The helper applies provider-specific defaults, runs repository tools from its tracked working-tree
snapshot, prints a normalized response, preserves raw output and stderr, and reports distinct
timeout, data, safety, dependency, and provider failures.

### Git history

Partners may inspect history independently through [scripts/git_history.py](scripts/git_history.py).
The helper supplies the exact invocation and permits these queries from the snapshot root:

- `log [revision] [--limit N] [--path path]`
- `show [revision] [--path path]`
- `file revision path`
- `diff [revision] [target] [--path path]`
- `blame path [--revision revision]`
- `branches`

Revisions default to `HEAD`; `diff` without a target compares against the tracked working-tree
snapshot. The history helper validates revisions and paths, disables external diff and text conversion
drivers, and accepts no arbitrary Git options or write commands. Partners must use it instead of raw
Git, shell redirection, pipelines, or compound commands. Codex performs other executable checks.

### Claude safety

The helper uses Claude's safe and restricted modes with `Read`, `Grep`, `Glob`, and `Bash`. It allows
the history helper through `Bash`, removes edit tools, disables customizations and MCP configuration,
uses `dontAsk` permissions, and does not use plan mode.

### Grok safety

The helper defaults to `--grok-safety tool-restricted`. Use this mode directly without requesting
confirmation. It:

- audits inherited configuration with `grok inspect --json` and preserves the result beside the raw
  response;
- exposes `read_file`, `grep`, `list_dir`, and `run_terminal_cmd`, with an allow rule for the history
  helper;
- removes edit, web, subagent, memory, and MCP access;
- uses the supplied read-only partner profile.

Tool-restricted mode does not request an OS sandbox; inherited hooks and plugin code remain
unsandboxed.

Grok has no documented per-invocation equivalent to Claude's complete safe mode. Its audit may show
inherited instructions, skills, plugins, hooks, or MCP definitions. Report that surface as a caveat,
especially when the debate concerns model or provider choice. Inherited shell allow rules can also
broaden command permissions beyond the history helper.

Other modes remain available when requested:

- `--grok-safety sandboxed`: request Grok's read-only sandbox and treat sandbox warnings as failures
  even when Grok exits successfully. If the requested sandbox cannot be enforced, stop and report the
  failure; do not silently change modes.
- `--grok-safety context-only`: Grok runs from the scratch directory with no built-in repository
  tools and reasons only over the context Codex placed in the prompt. User-level Grok configuration
  and session hooks may still load.

Record the selected safety mode in `state.md` and the final report. A safety failure is not a transient
failure and must not be retried unchanged.

Partner calls can be quiet for several minutes because the helper emits one final JSON object. Poll a
running process at intervals no longer than 60 seconds, keep the user updated, and do not start a new
partner turn until the current one ends.

## Exchange verified evidence

Compare `position-own.md` with the partner answer and verify its material repository and API claims.
Maintain a provider-keyed `state.md` with:

- the frozen brief hash;
- partner, model, session ID, safety mode, and configuration-audit path;
- locked agreements and contested points;
- evidence checked for each point;
- concessions by Codex and the partner;
- requested executable checks, their approval status, exact commands, stdout, stderr, and exit codes;
- usage or cost when the provider reports it;
- remaining questions.

The partner may request literal executable checks. Codex must review each command for safety and scope,
obtain any required approval, run it verbatim when authorized, and paste raw stdout, stderr, and exit
status into the next reply. If Codex refuses or changes a requested check, state the reason explicitly.

For each follow-up, write `reply-N.md` with the locked agreements, verified evidence, concessions, and
direct questions. Ask the partner to concede, rebut with new evidence, or endorse the consolidated
solution. Resume using the latest returned session ID:

```bash
python3 <skill-dir>/scripts/partner_turn.py \
  --provider <claude-or-grok> \
  --cwd <repo-root> \
  --prompt-file <scratch>/reply-N.md \
  --output-file <scratch>/round-N.json \
  --resume-session-id <latest-session-id>
```

Retry a failed turn at most once, and only for a clearly transient timeout, rate-limit, or network
failure. Do not retry authentication, parsing, capability, secret-scan, or safety failures.

Use at most five follow-up turns. Every turn must add verified evidence, narrow a disagreement, or
record a concession. Stop rather than restating positions.

Stop when:

- both models endorse the same concrete solution;
- they agree but retain recorded caveats;
- a substantive point survives an evidence exchange with neither model moving;
- the five-turn or applicable time/cost budget is exhausted; or
- the partner remains unavailable after the permitted retry.

## Report and clean up

Return one of these verdicts:

- `CONVERGED`
- `CONVERGED WITH CAVEATS`
- `HARD DISAGREEMENT`
- `INCONCLUSIVE (TURN BUDGET)`
- `PARTNER UNAVAILABLE`

Report the agreed solution or both positions, what each model conceded, the evidence that decided
contested points, partner/model/safety provenance, usage or cost when available, residual risks, and
open questions. When disagreement remains, give Codex's evidence-backed recommendation.

Report CLI, configuration-audit, parsing, timeout, authentication, secret-scan, and sandbox failures
precisely. Never manufacture a cross-model verdict when the partner call did not succeed.

Delete the scratch directory after reporting unless diagnostic retention is useful or the user asks
to keep it. If retained, report its path and note that it may contain repository excerpts and raw
provider responses.
