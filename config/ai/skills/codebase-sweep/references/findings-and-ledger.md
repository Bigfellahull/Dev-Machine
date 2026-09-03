# Findings and Ledger

Maintain one run ledger across chunks and rounds. It prevents settled findings from being re-argued,
shows coverage, and makes bounded non-convergence explicit. Keep it in the active task context; do not
write bookkeeping into the repository or modify `.git/info/exclude` unless the user explicitly asks
for durable resume state.

## Coverage ledger

Record:

```text
Run:
- baseline and candidate
- primary edit boundary
- selected passes
- action threshold / max fix risk / max rounds
- performance profile and baseline, when applicable

Chunks:
| id | name | primary files | supporting surface | passes | rounds | status | validation |

Cross-chunk units:
| id | invariant or repeated pattern | owners | status |
```

Chunk status is one of:

```text
planned
in-progress
clean
complete-with-blockers
max-rounds-reached
skipped
blocked
```

## Severity and fix risk

Severity reflects impact or materiality, never fix difficulty:

```text
Critical  Data loss, exploitable trust-boundary failure, broken core production flow, unsafe
          migration, or comparably catastrophic impact.
High      Major contract, correctness, integrity, compatibility, security, or production risk.
Medium    Real edge-case defect, incomplete non-core behaviour, meaningful test weakness, material
          maintainability burden, or evidenced scale risk likely to cause near-term problems.
Low       Concrete minor issue with limited impact.
```

The default action and convergence threshold is Medium. Critical and High correctness findings block
acceptance. Medium findings remain actionable in this sweep but do not justify silently exceeding the
fix-risk cap.

Rate fix risk separately:

```text
Low     Local and behaviour-preserving beyond the defect; existing coverage exercises the path.
Medium  Reshapes a path or moves ownership; needs targeted regression evidence.
High    Touches public contracts, auth, parsing, ingestion, provenance, migrations, schema, indexes,
        transactions, concurrency, persisted data, or external compatibility.
```

## Candidate verification and stable findings

Pass output is a hypothesis. Do not assign a stable finding ID until the driver independently verifies
the path, requirement or invariant, evidence, impact, occurrence scope, and correction boundary.
Discard false positives, speculative concerns, style preferences, and below-threshold candidates;
they are not findings and need not pollute the ledger.

Use stable IDs containing the chunk and pass, such as `C03-S1`, `C03-R2`, and `C03-P1`.

For every verified finding record:

```text
Finding: <stable id>
Chunk / pass:
Severity:
Fix risk:
Status: open | fixed | excluded | blocked | out-of-scope
Requirement or invariant:
Evidence:
Execution path or triggering scenario:
Primary location:
Other known affected locations:
Occurrence scope: isolated | repeated | example with uncertain full extent
Root cause:
Impact:
Why existing tests or validation missed it:
Minimum complete fix scope:
Required regression coverage:
Resolution and validation:
```

The complete fix scope corrects the known defect class, not merely the line reported by a pass.

## Terminal statuses

Use `fixed` only when the complete known in-scope correction is implemented and current validation
supports it.

Use `excluded` only for a verified, recorded concern deliberately not changed because the behaviour is
intentional, externally owned, generated from another source, below an explicitly changed threshold,
or outside the selected pass. State evidence and do not use “not worth it,” “probably fine,” “too
hard,” or uncertainty as reasons.

Use `blocked` when the correction requires a material product, architecture, security, migration,
schema, deployment, capacity, or external-contract decision; exceeds the fix-risk cap; cannot be
separated safely from user work; or lacks required validation infrastructure. State the decision or
authority needed.

Use `out-of-scope` when the defect is outside the primary edit boundary and is not required for a
complete in-scope correction. Preserve enough evidence for a later targeted run.

Settled exclusions, blockers, and out-of-scope findings appear in the brief supplied to later rounds.
Do not re-raise them unless new evidence materially changes their scope or severity.

## Round summary

After every round record:

```text
Chunk / round:
New verified findings by pass and severity:
Fixed / excluded / blocked / out-of-scope:
Files changed:
Validation run or reused:
Clean round: yes | no
Next action:
```

A round with fixes is not clean even when every known finding is terminal; the resulting code needs a
later complete round when budget remains.

## Final accounting

Before reporting completion, confirm:

- every primary file belongs to one planned chunk;
- every selected pass ran for every applicable chunk;
- every verified finding is terminal;
- every fixing round is followed by a clean round, or the chunk is explicitly max-rounds-reached;
- cross-chunk patterns and aggregate-diff findings are terminal;
- validation evidence matches the final code.

Report blockers and max-rounds-reached chunks in full. Do not compress the most consequential
remaining work into counts while listing minor fixes in detail.
