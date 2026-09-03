---
name: codebase-sweep
description: Iteratively simplify, review, and optionally performance-audit a whole codebase, branch delta, or scoped subsystem. Maps behaviour into manageable chunks, fixes verified findings, and repeats each chunk for up to three rounds until no new findings at or above the action threshold remain. Use for deliberate sweep-and-fix work, not ordinary task completion or a read-only PR review.
---

# Codebase Sweep

Run a bounded, evidence-driven sweep over an existing codebase. Map the requested surface once, work
through cohesive chunks, and revisit each changed chunk with fresh passes until it converges or reaches
the round limit.

This skill edits files as its normal mode. Do not stage, commit, push, deploy, post comments, or mutate
external systems unless the user explicitly requests that action. Preserve unrelated user work.

Treat `$ARGUMENTS` as scope, pass selection, thresholds, and constraints.

Recognised argument intent:

```text
--scope <path/unit>       Limit primary edit scope to paths, packages, features, or subsystems.
--base <ref>              Sweep the merge-base delta from ref to the candidate, following its affected surface.
--changed-only            Sweep staged, unstaged, and relevant untracked work rather than the whole repository.
--passes <list>           Comma-separated simplification,performance,review. Default: simplification,review.
--profile <path>          Override the default repository profile at .codebase-sweep/scale-profile.md.
--severity <level>        Minimum action threshold: critical, high, medium, low. Default: medium.
--max-risk <level>        Highest fix risk to apply autonomously: low, medium, high. Default: medium.
--max-rounds <n>          Per-chunk round ceiling. Default: 3.
--measure                 Use an existing local performance harness when useful and safe.
--report-only             Verify and report findings without editing.
--no-subagents            Perform distinct passes inline.
```

If arguments conflict, prefer the narrower scope, higher action threshold, lower fix risk, and lower
round count. Do not silently disable a pass the user explicitly requested.

## Required references

Read [findings-and-ledger.md](references/findings-and-ledger.md) for every run.

Read only the pass references selected for the run:

- [simplification-pass.md](references/simplification-pass.md) for simplification;
- [performance-pass.md](references/performance-pass.md) for performance;
- [review-pass.md](references/review-pass.md) for correctness and production review.

Performance fixes always receive the focused correctness check defined in the performance reference,
even when `review` was not selected. Simplification fixes always receive behaviour-preservation and
targeted validation checks.

When performance is selected and no usable profile exists, the profile interview, confirmation, and
repository write are a preflight checkpoint before chunk passes begin. Pause the sweep at that
checkpoint, then resume the planned sweep automatically after storing the confirmed profile; do not
treat profile creation as the completed task.

## Completion standard

Do not call the sweep clean while any of these remain true:

- a planned chunk has not received every selected pass;
- performance was selected but its profile interview or confirmed repository profile is incomplete;
- a verified finding at or above the action threshold is still open;
- a changed chunk has not received a later complete round over the resulting code;
- the known affected surface is internally inconsistent;
- a fix addressed an example but not its known defect class;
- validation required by an edit is missing, stale, or failing because of the sweep;
- the aggregate diff has not received a cross-chunk sanity check.

Blocked findings and a round ceiling are valid terminal outcomes, but they are not a clean result.

## 1. Pin the target and instructions

Before reviewing or editing:

1. Resolve the repository root, current `HEAD`, requested base/candidate refs, and merge base where
   applicable. Fail closed on an invalid ref.
2. Snapshot staged, unstaged, and relevant untracked work. Existing work belongs to the user; do not
   require it to be committed and do not overwrite or reformat it incidentally.
3. Establish the primary edit boundary:
   - whole repository when no narrower target was supplied;
   - explicit paths for `--scope`;
   - changed primary files for `--base` or `--changed-only`.
4. Establish the wider review boundary: callers, consumers, sibling paths, shared rules, tests,
   configuration, persisted data, generated artefacts, and external contracts affected by the primary
   surface. The target identifies where to start, not where reasoning must stop.
5. Find and read applicable `AGENTS.md`, `CLAUDE.md`, and path-scoped rules or references they require.
   Follow the repository's stated authority order. Otherwise prefer the user's task, then the closest
   applicable path instruction, then broader repository instructions.
6. Identify generated, vendored, built, minified, lock, and do-not-edit areas. Change their source and
   regenerate when required; do not hand-edit generated output.
7. Identify authoritative requirements: named issue or specification, public contracts, repository
   documentation, tests that credibly express behaviour, and code-level invariants. Existing code is
   evidence of behaviour, not automatic proof of intended behaviour.
8. Identify repository-owned validation commands. Run a broad baseline once when it will distinguish
   pre-existing failures from sweep regressions; do not repeat expensive validation ceremonially.

If user changes overlap the required edit boundary and cannot be preserved or attributed safely, stop
that chunk and ask rather than guessing.

## 2. Build the code map and chunks

Map the requested surface before launching passes. Identify entry points, public contracts, domain and
data flows, persistence boundaries, risky operations, callers and consumers, sibling implementations,
tests and fixtures, and validation targets.

Divide primary files into cohesive chunks. Prefer one vertical behaviour, package, feature, command
group, pipeline, persistence area, or tightly scoped cross-cutting concern. A chunk should have one
meaningful set of contracts and invariants and be independently understandable and target-testable.

Use file count only as a warning signal: 3-12 primary source files is often workable, but cohesion and
context size decide the split. Split a chunk when it spans unrelated behaviour, several independent
datasets, or cannot be validated meaningfully.

For coverage and ownership:

- assign every primary file to exactly one chunk;
- record supporting files that may be read by several chunks;
- give shared files one edit owner;
- fold tests and fixtures into the chunk that owns the behaviour;
- order shared foundations before their consumers;
- create a named cross-chunk unit when a repeated rule cannot be corrected safely within one owner.

Record the planned chunks and confirm that the primary manifests cover the requested scope without
gaps or accidental duplication.

## 3. Establish chunk context

Before the first round for a chunk, record:

```text
Chunk: <id and name>
Primary edit scope: <paths>
Supporting review scope: <callers, consumers, siblings, contracts>
Requirements and invariants: <sources>
Applicable instructions: <paths>
Risk areas: <security, data, migration, parser, concurrency, external contract, scale>
Validation target: <commands or reason unavailable>
Round budget: <used>/<maximum>
```

Read enough of the actual execution path to understand behaviour before accepting findings or edits.

## 4. Run bounded paired rounds

For each chunk, run up to `--max-rounds` complete rounds. The default is three. Within a round, use
this order so the final correctness pass sees all earlier edits:

1. **Simplification**, when selected. Audit, independently verify candidates, apply permitted
   behaviour-preserving changes, then run validation invalidated by those changes.
2. **Performance**, when selected and the chunk touches a scale-profile dataset. Verify scale evidence,
   apply permitted fixes, prove the effect, and perform the focused correctness and Do No Harm check.
3. **Review**, when selected. Review the resulting code for contract compliance, correctness, blast
   radius, tests, security, data integrity, compatibility, and other relevant production risks.
4. Consolidate the round ledger, independently verify every new candidate, and give every verified
   finding a terminal or actionable status.
5. Apply fixes only within the action and risk thresholds. Fix the minimum complete defect class, not
   only the reported occurrence. Run targeted regression and validation evidence invalidated by edits.

When independent agents are available and warranted, use a small number of fresh, orthogonal pass
agents. Give them the pinned target, chunk manifest, requirements, relevant instructions, and settled
finding brief, but not the fixer's reasoning transcript. Pass agents report candidates and do not edit,
invoke this skill, or spawn duplicate generic reviewers. The driver retraces and verifies every
candidate before reporting or fixing it. Without agents, perform the passes inline and keep them
explicitly separate.

Do not rotate through partial review emphases as a substitute for a complete pass. Scale depth to the
chunk's risks, but every review round covers all applicable concerns.

## 5. Decide convergence

A complete round is clean only when:

- it produces no new verified finding at or above the action threshold;
- it makes no code change;
- all earlier findings are terminal and settled findings were not re-raised;
- validation evidence is current for the resulting code.

After any fixing round, run another complete round if budget remains. Stop at the first clean round;
two consecutive clean rounds and a separate confirming iteration are not required.

Known exclusions and blockers do not trigger repeated rounds. A chunk containing blockers is
`complete-with-blockers`, not clean. If the last allowed round finds or fixes an actionable issue,
mark the chunk `max-rounds-reached`; do not claim convergence merely because the budget ended.

Continue to the next independent chunk after a blocker or round ceiling unless it invalidates shared
assumptions or makes later work meaningless. In that case, stop and ask for the required decision.

## 6. Validate proportionately

Use current credible evidence. After an edit, rerun only checks that the edit could invalidate:

1. reproduction or regression test for the corrected defect;
2. targeted tests for the chunk and affected callers or consumers;
3. build, typecheck, lint, formatting, generation, or static analysis relevant to changed files;
4. broader integration, end-to-end, race, migration, or runtime checks when the risk requires them.

Never weaken a valid test to obtain a pass. A regression test must exercise the production path and
would have failed against the defective behaviour. Distinguish sweep regressions from precise
pre-existing or environmental failures. Never report a command as passing unless it ran and passed.

## 7. Cross-chunk and final gate

After planned chunks:

1. Resolve all named cross-chunk units with the same bounded-round process.
2. Inspect the complete aggregate diff against the starting snapshot, including staged, unstaged, and
   relevant untracked files. Confirm no unrelated user edit was introduced or overwritten.
3. Perform one fresh cross-chunk consistency and completeness review over changed contracts, callers,
   sibling paths, shared invariants, generated artefacts, and validation coverage.
4. Route a new material finding back to its owning chunk or a cross-chunk unit; respect the same round
   and risk bounds.
5. Run the broadest practical final validation once after the last relevant edit.

## Final response

Lead with `Clean`, `Complete with Issues`, or `Blocked`. Report:

- pinned baseline, candidate, primary scope, and wider behavioural coverage;
- selected passes, profile when applicable, action threshold, risk cap, and round limit;
- chunks clean, complete-with-blockers, max-rounds-reached, skipped, or blocked;
- fixes by stable finding ID and the defect class corrected;
- exclusions, blockers, and out-of-scope findings with reasons;
- exact validation run or reused and its result;
- performance evidence and profile gaps when applicable;
- remaining uncertainty and the next concrete decision or action.

Do not say the sweep is clean when any chunk is unreviewed, validation is stale, a blocker remains, or
the last round changed code without a later clean round.
