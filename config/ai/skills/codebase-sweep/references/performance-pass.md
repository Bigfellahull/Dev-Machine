# Performance Pass

Use this pass only when performance was selected. It audits behaviour whose cost grows with a dataset
the scale profile says is material. It is not a general optimization or micro-benchmarking pass.

## Profile discovery

Resolve the performance profile before mapping performance chunks:

1. If the user supplied `--profile <path>`, use that file. If it is missing, unreadable, or not usable,
   pause and ask the user to correct the path or choose canonical profile creation. Do not silently
   ignore an explicit path.
2. Otherwise use `<repository-root>/.codebase-sweep/scale-profile.md`.
3. Do not fall back to `.perf-loop/scale-profile.md`; that was the retired loop's location.

A profile marked draft, unconfirmed, or materially incomplete is not usable. Inspect it, derive what
the repository can answer, and interview the user only for the missing or stale facts before updating
it with confirmation.

## Bootstrap a missing canonical profile

When performance was selected, no explicit profile path was supplied, and
`.codebase-sweep/scale-profile.md` does not exist, pause performance work and create it through this
checkpoint. Pause all chunk passes while resolving it. This pause is part of the active sweep, not its
final result.

### 1. Investigate before asking

Inspect the repository first so the user confirms domain facts rather than performing code discovery
for the agent. Derive and cite where possible:

- persisted datasets from schemas, models, migrations, indexes, search layouts, and storage clients;
- structural growth drivers and parent-child fan-out;
- tenant, user, regional, or deployment partitioning;
- request, render, message, import, maintenance, and background entry points;
- likely hot paths and trigger frequency from callers and application flow;
- retention, pagination, batch, queue, cache, and payload bounds;
- existing capacity notes, production documentation, seeders, generators, benchmarks, probes, and
  accepted performance baselines;
- correctness and isolation invariants a performance change must preserve.

Do not present code-derived estimates as confirmed production facts.

### 2. Interview the user thoroughly

Present the discovered inventory and ask focused questions in small, coherent batches. Follow up on
ambiguity, contradictions, ranges that cross tiers, and unexplained fan-out. Do not ask questions the
repository already answers credibly.

Establish at least:

1. **Baseline envelope:** the current and target horizon, per-tenant and total volumes, tenant count,
   dedicated versus shared storage, and any unusually large customer or deployment shape.
2. **Dataset scale:** current and target row or object counts, growth drivers and rates, retention,
   which datasets are genuinely bounded, and which estimates are uncertain.
3. **Fan-out and bursts:** child rows per parent, users or recipients per event, peak imports, bulk
   jobs, queue bursts, concurrent requests, and background arrival rates.
4. **Hot paths and budgets:** who triggers each important path, how often, latency or throughput
   targets, acceptable operator-only slowness, and restart or backlog-drain expectations.
5. **Invariants and scope:** tenant or user isolation, visibility, audit, provenance, idempotency,
   ordering, compatibility, and other behaviour that speed must not weaken; explicitly excluded areas.

Continue until every dataset reached by the selected performance scope has a confirmed tier, a
confirmed bound, or an explicit `unknown` profile gap. If an unknown prevents meaningful severity or
cost derivation for a chunk, keep that chunk blocked and state the exact missing fact; do not guess.

### 3. Confirm and store the profile

Draft the complete profile from repository evidence and the user's answers, clearly distinguishing
confirmed facts, estimates, and unknowns. Present the proposed baseline, tier table, fan-out, hot
paths, budgets, invariants, scope, and gaps for confirmation.

After the user confirms or corrects it:

1. create `<repository-root>/.codebase-sweep/` if needed;
2. write `<repository-root>/.codebase-sweep/scale-profile.md`;
3. keep it as a normal repository artefact intended for version control; do not add it to ignore
   files or `.git/info/exclude`;
4. record important evidence sources and label estimates or unknowns in the file;
5. reload the stored file as the active profile.

If the user declines to confirm or store a profile, block the performance pass and explain why.

### 4. Resume the same sweep

Once the confirmed profile is stored, continue the already planned codebase sweep automatically from
performance mapping and chunk selection. Preserve the pinned code target, settled findings, selected
passes, thresholds, and round budgets. Do not stop after announcing that the profile was created and
do not require the user to invoke the sweep again.

## Usable profile contents

A usable profile states:

- baseline volumes and tenant or user shape;
- datasets, tiers, rows at baseline, growth drivers, and relevant retention;
- parent-child fan-out;
- hot paths and trigger frequency;
- budgets when known;
- bounded or excluded datasets and the reason.

Tier vocabulary:

```text
huge      10^6+ and growing; per-row work on request paths is a defect.
large     10^5-10^6; normally filtered, indexed, bounded, paged, and projected.
moderate  10^3-10^4; full loads may be suspicious; N+1 and bad predicates still matter.
fixed     bounded by configuration or administration, normally below 10^3; whole-set work is fine.
unknown   not classified; investigate or record a profile gap, never assume huge.
```

Skip a chunk whose datasets are all fixed tier. Record the reason.

## Evidence and severity

Every performance finding needs one evidence kind:

```text
derived   The code plus profile proves the bound, round trips, materialization, or growth.
query     The generated statement, predicate, schema, indexes, and plan establish the cost.
measured  A repository-owned harness or probe on a disposable local environment establishes it.
```

Also require a cost statement:

```text
At <profile baseline>, <path> performs <N rows, round trips, bytes, or duration-driving operations>
per <trigger>, invoked by <actor and frequency>.
```

If the cost statement cannot be written, investigate further or omit the candidate.

Derive severity from tier and trigger rather than intuition:

| Work proportional to | Request/render/message path | Background job/batch | Admin/import/install |
|---|---|---|---|
| huge | Critical | High | Medium |
| large | High | Medium | Low |
| moderate | Medium | Low | Low |
| fixed | exclude | exclude | exclude |

Raise severity when there is a round trip per row, work occurs while holding a transaction or scarce
resource, the trigger runs for every request or message, or the result is unbounded. Lower it for an
off-by-default feature or a documented single-operator slow path. Explain adjustments.

## Audit areas

Inspect scale-relevant chunks for:

- materialization before filtering, sorting, paging, projection, or aggregation;
- whole-entity or whole-aggregate loads for existence, counts, or a few columns;
- N+1 database, cache, search, repository, or network round trips;
- predicates, joins, and sorts unsupported by real indexes, including non-sargable expressions and
  conversions;
- deep offset paging, unstable ordering, client-controlled page sizes without server bounds, counts
  on every page, and authorization after paging;
- save-per-row work, unbounded batches, long transactions, missing checkpoints, and maintenance or
  migration work proportional to huge datasets;
- unbounded or high-cardinality caches, missing expiry or invalidation, stampedes, buffering, and
  large per-row allocations;
- unbounded responses, exports, messages, client-side filtering, and polling proportional to dataset
  size rather than change rate;
- search hit collection, per-hit hydration, rebuild work, queue scans, throughput below arrival rate,
  missing back-pressure, and unsafe parallelism;
- authorization or visibility evaluated per row, per-row permission round trips, or filtering after
  retrieval and paging;
- startup, install, health, dashboard, retention, cleanup, or scheduled work that scans large data.

Do not report allocation golf, loop-form preferences, theoretical concurrency, speculative caches,
or index suggestions that do not inspect actual predicates and current indexes.

## Fix risk and Do No Harm

Projection, hoisting invariant work, or bounding an already-paged path may be Low risk. Query
reshaping, batching, cursoring, or a correctly designed cache is usually Medium. Schema, index,
migration, contract, ordering, pagination, transaction, search layout, denormalization,
authorization, and parallelism changes are High unless evidence establishes otherwise.

Never improve speed by weakening correctness, isolation, authorization, validation, provenance,
audit, checksums, idempotency, error handling, transaction safety, accessibility, limits, timeouts, or
cancellation. Never introduce dirty reads, interpolated SQL, unsafe cache keys, unbounded parallelism,
or skipped writes. If the required fix violates these boundaries or exceeds the risk cap, block it.

## Prove correctness, then effect

After each performance edit:

1. verify unchanged results, ordering, visibility, error behaviour, and external contracts;
2. add or run regression coverage for reshaped queries, page or batch boundaries, and visibility;
3. confirm tenant and user filters still apply;
4. run relevant tests and static checks;
5. prove the performance effect by the cheapest sufficient method: derived before/after counts, query
   and plan evidence, or measurement.

Do not report “should be faster.” State the demonstrated before and after effect and any remaining
profile gap.
