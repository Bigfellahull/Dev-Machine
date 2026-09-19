# Partner execution

Read the sections for the selected external participants. Use `scripts/partner_turn.py`; do not
replace its safety controls with bare CLI calls. The helper defaults to Claude when `--provider` is
omitted for compatibility, so always pass the provider and model for panel calls.
All providers default to `high` reasoning effort. Pass `--effort` to override it
for a particular call; isolated partners do not rely on user configuration.

## Shared Git history

Partners may inspect the snapshot's history using `scripts/git_history.py`. The helper supplies the
exact invocation and permits these queries from the current snapshot root:

- `log [revision] [--limit N] [--path path]`
- `show [revision] [--path path]`
- `file revision path`
- `diff [revision] [target] [--path path]`
- `blame path [--revision revision]`
- `branches`

Revisions default to `HEAD`; `diff` without a target compares against the tracked working-tree
snapshot. The history helper validates paths/revisions, disables external diff/text conversion, and
accepts no arbitrary Git options or writes. Use it instead of raw Git, redirection, pipelines, or
compound commands. Other executable checks belong to the lead. Each call creates a fresh temporary
snapshot; resumed participants must use the supplied current working directory, not an old path.

## Claude

Default model: `claude-fable-5-1`. Default per-call timeout: 600 seconds.

The helper uses safe/restricted modes, `Read`, `Grep`, `Glob`, and history-helper `Bash` access. It
removes edit tools, disables customizations and MCP configuration, uses `dontAsk` permissions, and
does not use plan mode. Follow-ups use `--resume` and the returned session ID. Optional `--effort`
and `--max-budget-usd` apply to this provider; the latter is a per-call API budget, not a panel cap.

## Grok

Default model: `grok-4.6`. Default per-call timeout: 900 seconds.

Default `--grok-safety tool-restricted` is authorized without another confirmation. It audits inherited
configuration using `grok inspect --json` and preserves the audit beside the raw response. The helper
exposes `read_file`, `grep`, `list_dir`, and `run_terminal_cmd`, allows the history helper, removes
edit/web/subagent/memory/MCP access, and loads `agents/grok-partner.md`. Follow-ups use `--resume`.
Optional `--effort` maps to Grok's reasoning effort; `--grok-max-turns` defaults to 30 internal agent
turns per call and is separate from the debate-round budget.

This mode does not request an OS sandbox. Inherited instructions, skills, plugins, hooks, MCP
definitions, and shell allow rules may remain; hooks/plugin code are unsandboxed and inherited allow
rules may broaden command permissions. Report the audit surface as a caveat, particularly for debates
about models or providers. There is no documented equivalent to Claude's complete safe mode.

Other modes, when requested:

- `--grok-safety sandboxed`: request the read-only sandbox. Sandbox warnings fail the call even after
  a successful exit. Stop if enforcement fails; never silently downgrade.
- `--grok-safety context-only`: run from scratch with no built-in repository tools, using only the
  prompt. No repository snapshot or repository scan; the prompt is still scanned. User configuration
  and session hooks may still load. State the evidence-access asymmetry to the panel.

## Codex

Default model: `gpt-6-astra`. Default per-call timeout: 900 seconds.

The helper uses `codex exec --json` and resumes with `codex exec ... resume <session-id> -`. It
reapplies an explicit read-only sandbox, never-approve policy, working directory, model, and controls
on every invocation. It ignores user config and execpolicy rules, disables automatic AGENTS.md
injection, web search, apps, plugins, hooks, memories, browser/computer tools, and subagents, and
avoids login shells and shell snapshots. Read-only file inspection uses the sandboxed shell; Git
history uses the shared helper. Instructions prohibit other tools and external-state changes.

The adapter requires the installed CLI's isolation flags and fails when they are unavailable; it
does not fall back to inherited defaults. `--strict-config` rejects unsupported configuration fields.
These controls do not constitute a complete filesystem read boundary or remove every managed
configuration/skill discovery surface. Respect managed policy and report any resulting limitation;
do not claim Claude-equivalent isolation. Optional `--effort` sets `model_reasoning_effort`.

Codex emits JSONL events. The helper requires a completed turn, nonempty final agent message, and
thread ID; it preserves the raw stream and normalizes the answer/session/usage for the lead.
The selected model is recorded; token usage is not a dollar-cost estimate. Neither Codex nor Grok
supports this helper's `--max-budget-usd`; passing it is an error.

Provider mechanics were checked against Codex CLI 0.153.4 and the official
[non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode) and
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

## Retention and failures

All providers use their native persistent sessions for resuming. Scratch cleanup removes this
workflow's prompts, replies, and audits, but does not delete native provider session stores. Do not
silently remove unrelated CLI state or imply zero retention. Honor user retention requirements before
calling a provider; resumable sessions may not meet a no-persistence requirement.

The helper preserves raw stdout and stderr on provider failures/timeouts. A successful process exit
alone is insufficient: malformed output, empty answers, and sandbox enforcement failures are errors.
Do not fabricate agreement from an unavailable partner. Retry only as allowed by `SKILL.md`.
