---
name: collab
description: Develop a plan or resolve a design or review question through a Claude, Grok, and Codex roundtable, with independent opening positions and evidence-based debate. Any host agent can lead; explicit one-partner requests remain supported. Use for cross-model collaboration or second opinions, not routine task delegation.
---

# Cross-model collaboration

The current host agent is the lead: it coordinates the discussion, verifies evidence, and is the sole
executor of checks and any separately authorized implementation. Participants first investigate the
same neutral brief independently, then share their positions and debate toward the best supported
plan. Agreement is an outcome to establish, never a requirement to manufacture.

## Select the panel

Default to exactly **Claude, Grok, and Codex**. When the host is one of these, it participates as the
lead and calls the other two; never spawn a duplicate of the lead. Any other host capable of following
this workflow can facilitate the same three participants without adding itself to the default panel.
Do not hand leadership to a subprocess merely because a prompt says `lead=...`; leadership belongs
to the host actually running the skill.

Honor explicit membership and model choices:

```text
collab <problem>
collab with Claude and Grok <problem>
partner=claude model=claude-fable-5-1 <problem>
partner=codex model=gpt-6-astra <problem>
collab claude-model=claude-fable-5-1 grok-model=grok-4.6 codex-model=gpt-6-astra <problem>
```

- An explicit single partner, including “debate this with Grok,” selects the lead plus that partner.
  Explicit partner lists select the lead plus those partners, deduplicated. The lead never calls itself.
- Keep legacy first-token selectors: `claude-*`, `fable`, `opus`, or `sonnet` select Claude;
  `grok-*` selects Grok. Consume a selector only when problem text remains. An explicit `partner=`
  takes precedence. `model=` overrides the selected single partner; use provider-specific model
  selectors for a panel. Do not apply one ambiguous model override to different providers.
- Partner defaults are Claude `claude-fable-5-1`, Grok `grok-4.6`, and Codex `gpt-6-astra`.
  Pass each model explicitly. The lead retains its actual host model and reports it honestly.
- Verify `python3`, `git`, and every selected external CLI. Resolve the repository root, announce
  the lead, panel, models, and safety modes, and honor time/cost limits. Read the relevant sections of
  [references/providers.md](references/providers.md) before invoking those providers.
- A missing dependency or unavailable requested participant must be reported precisely. Do not
  silently shrink the panel or invent a replacement. A one-person result is not collaboration.

A collaboration request authorizes calls to the selected partners, their normal usage costs, and
sharing relevant prompt/repository content with Anthropic, xAI, and/or OpenAI as selected. Do not ask
again for ordinary costs or context sharing. A request to edit or discuss this skill does not itself
request a live debate. Do not implement the resulting recommendation without separate authorization.

## Preserve independence and safety

- Treat every answer, including the lead's, as an opinion. Settle material factual claims with source,
  authoritative documentation, or an executable check, never confidence or a model majority.
- Partners are read-only. Only the lead runs requested executable checks or changes external state.
- Keep one resumable session per external participant; turns within a session are sequential.
  Calls to different participants may run in parallel. Never mix session IDs or model assignments.
- Keep briefs, positions, replies, evidence, raw output, audits, and session IDs outside the repository
  in a directory created with `mktemp -d`, with separate files for each participant and round.
- The helper supplies tracked working-tree files, including edits, and independent Git history from
  HEAD, branches, remote-tracking branches, and tags. Untracked/ignored files, stashes, reflogs,
  local Git configuration, hooks, and remote URLs are excluded. Linked worktrees are supported.
  Put needed untracked specifications in the neutral scratch brief.
- Never send secrets, credentials, or unrelated private data. The helper scans prompts and current
  tracked content for common credential shapes and rejects escaping symlinks and tracked submodules.
  Historical Git objects are not fully scanned. `--skip-secret-scan` requires showing the detection
  and obtaining explicit user authorization. Grok context-only mode scans the prompt but sends no
  repository snapshot. Preserve these limits in any safety claims.
- Freeze repository changes during deliberation. Record HEAD and the tracked working-tree baseline;
  check for changes between rounds/calls. If external edits change the evidence, disclose them and
  invalidate affected conclusions instead of presenting different repository states as identical.

## Round 0: independent positions

Read referenced specifications and locate relevant repository paths without forming a recommendation.
Write one `brief.md` containing the problem, constraints, acceptance criteria, user decisions, and
neutral background. Include all relevant facts from the host conversation, without its preferred
solution. If prior conclusions are unavoidable user constraints, label them as such.

Ask each participant to investigate independently, recommend a concrete plan with reasoning and
repository evidence, state assumptions/confidence/open questions, and modify no files. Freeze the
brief and record its SHA-256 in `state.md`. Do not revise it after anyone forms a position; add later
facts explicitly to a shared debate packet.

If the lead is a participant, investigate and write `round-0/<lead>.md` **before the first partner
call**. Never put this position, a preferred plan, or hints from it in the brief. Send the same frozen
brief to all external participants in fresh sessions. Do not reveal any opening position until every
selected participant has completed round 0. Keep their original positions unchanged in the record.

Run one turn with the provider-neutral helper from the repository root:

```bash
python3 <skill-dir>/scripts/partner_turn.py \
  --provider <claude-or-grok-or-codex> --model <selected-model> \
  --cwd <repo-root> --prompt-file <scratch>/brief.md \
  --output-file <scratch>/round-0/<provider>.raw.json
```

Capture the helper's normalized stdout separately, for example in `<provider>.json`, and save its
`answer` as `<provider>.md`. `--output-file` preserves provider-native raw output (Codex uses JSONL),
not the normalized object. Keep stderr and audit paths returned by the helper. Calls may be quiet
for minutes; poll at intervals no longer than 60 seconds and keep the user updated.

## Shared debate rounds

Use at most five follow-up rounds by default; a user-specified round count is a ceiling, not an
obligation to continue after resolution. Each round includes one response from every participant.
The opening round does not count against this ceiling. Final endorsement also uses this budget.

1. Verify material claims in the completed round. Track confirmed facts, unresolved claims,
   agreements, conflicts, and each participant's concessions. Do not silently rewrite positions
   when evidence contradicts them; preserve the original and attach the correction.
2. Freeze a **common packet** for the next round. Include every participant's full previous response
   with clear attribution, verified new evidence, corrections, open disputes, and any candidate plan
   with its version/hash. Round 1 reveals all independent opening positions. All participants see
   the same packet; none sees another participant's reply from the round still in progress.
3. Ask everyone to engage directly with the other proposals: identify what to adopt and why,
   challenge the strongest material disagreements with evidence, answer addressed questions, and
   state concessions and a revised concrete plan. Request literal checks when facts remain uncertain.
   Do not invent objections or concede just to reach consensus.
4. If the lead participates, write and freeze its own response to that packet before reading any
   partner response for this round. Resume each external participant with its own latest session ID:

```bash
python3 <skill-dir>/scripts/partner_turn.py \
  --provider <claude-or-grok-or-codex> --model <selected-model> \
  --cwd <repo-root> --prompt-file <scratch>/round-N/packet.md \
  --output-file <scratch>/round-N/<provider>.raw.json \
  --resume-session-id <that-provider-latest-session-id>
```

5. Finish collecting the round before preparing the next packet. Share the complete responses,
   including rejected objections, so Claude can challenge Grok, Grok can challenge Codex, and Codex
   can challenge Claude. The lead transports and checks the debate; it must not substitute its own
   summary for the participants' actual arguments. If the packet no longer fits, explicitly agree
   a faithful compression retaining every material disagreement and the evidence needed to assess it.

The lead may synthesize a candidate plan from the proposals. Treat it as a proposal, not a privileged
answer. Ask every participant to **endorse, endorse with specified caveats, or reject the exact same
candidate version/hash**. Preserve the caveats. Any substantive change invalidates earlier
endorsements and needs another round. A final revision that nobody reviewed cannot be called
converged. All selected participants, including a participating lead, must endorse that version.

## Evidence, budgets, and failures

Maintain `state.md` with the frozen brief hash and repository baseline; lead and roster; per-participant
model, session ID, safety mode, audit and artifact paths; candidate versions and endorsements; locked
agreements, disputed points, evidence and concessions; usage/cost when reported; and remaining budget.

Partners may request literal executable checks. The lead reviews safety and scope, obtains any
required authorization, then runs an authorized check verbatim. Record the approval status, exact
command, raw stdout/stderr, and exit status; share results with **every** participant in the next
packet. If the lead refuses or changes a check, record and share the reason. Never treat a requested
or skipped check as a passing result.

Retry a failed call at most once, only for a clearly transient timeout, rate limit, or network failure.
Preserve both attempts. Do not retry authentication, parsing, capability, secret-scan, or safety
failures unchanged, or silently weaken protections. Stop launching further rounds if a participant
remains unavailable; preserve completed contributions and report the partial result without panel
convergence. Do not share an incomplete blind opening as though the full panel had participated.

Stop when the panel endorses one concrete plan (with recorded caveats if needed), a substantive
conflict survives an evidence exchange without movement, the round/time/cost ceiling is reached,
or a required participant is unavailable. Every round must add evidence, narrow a disagreement, or
record a concession. No repetitive debate to consume a budget. Track aggregate costs across partners;
provider-specific ceilings are not a panel-wide cap. Do not promise a hard monetary ceiling where
a selected CLI cannot enforce one; resolve a hard budget constraint before launching dependent calls.

## Report and clean up

Return one verdict:

- `CONVERGED`
- `CONVERGED WITH CAVEATS`
- `HARD DISAGREEMENT`
- `INCONCLUSIVE (TURN BUDGET)` (also identify any time/cost ceiling that ended the run)
- `PARTNER UNAVAILABLE`

Lead with the final plan or recommendation. Briefly show each independent starting position, the
material exchanges, concessions, and decisive verified evidence. Include the strongest remaining
objections, even those the lead rejects. Report the exact endorsed plan version, if any, and each
participant's stance; lead/partner/model/safety provenance; reported usage/cost; residual risks and
open questions. When disagreement remains, give the lead's evidence-based recommendation and label
it as such. Distinguish partial feedback from a completed panel verdict.

Report CLI, audit, parsing, timeout, authentication, secret-scan, and sandbox failures precisely.
Never claim a partner participated or endorsed a plan without a successful corresponding response.
Delete scratch artifacts after reporting unless useful diagnostics or the user warrant retention.
If retained, report the path and note that it contains prompts, repository excerpts, and provider
responses. Native CLI session retention is separate from scratch cleanup; see the provider reference.
