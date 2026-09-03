# Simplification Pass

Use this pass to reduce avoidable conceptual machinery while preserving intended and observable
behaviour. It is an implementation pass, not a redesign exercise and not line-count golf.

## Hard boundary

Preserve requirements, public contracts, outputs, side effects, error and data semantics,
compatibility, security, accessibility, ordering, persistence, and externally observable behaviour.
Do not simplify away validation, authorization, provenance, checksum verification, parser fidelity,
idempotency, transaction safety, cancellation, resource cleanup, auditability, or tests for risky
behaviour.

When intended behaviour is ambiguous, do not choose the smaller behaviour. Record the decision needed
and leave the contract unchanged.

## Simplification ladder

After understanding the flow, stop at the first rung that fully satisfies the behaviour:

1. remove code or behaviour that does not need to exist;
2. reuse an existing repository helper, type, pattern, or authoritative layer;
3. prefer the language standard library;
4. prefer a native platform or framework capability;
5. reuse an already-installed dependency rather than adding another one;
6. prefer direct, readable code over a new abstraction;
7. otherwise keep only the minimum new code required.

The ladder reduces concepts and ownership boundaries, not merely files or lines.

## Inspect for

- dead code and unused dependencies, with every configured, generated, reflective, and external use
  checked before deletion;
- duplicated rules or guards that should have one authoritative owner;
- unnecessary nesting, branching, state, transformations, wrappers, factories, interfaces, and
  indirection;
- speculative configuration, extension points, compatibility paths, concurrency, caching, or
  abstractions without a current requirement;
- business logic at the wrong boundary;
- hand-rolled behaviour already owned by the repository, standard library, database, or framework;
- broad or swallowed errors, confusing control or data flow, and unclear ownership;
- comments that restate code rather than explain a non-obvious reason, invariant, or constraint;
- over-mocked or duplicated test setup that can be simplified without weakening behavioural evidence.

Prefer deletion, consolidation at the authoritative boundary, explicit control flow, clear names, and
repository conventions. Concrete types are usually simpler than premature interfaces; an existing
real seam, multiple implementation, transaction owner, policy boundary, or test boundary may justify
an abstraction.

## Reject false simplicity

Reject a change that:

- makes code denser, cleverer, or harder to debug;
- combines unrelated concerns;
- moves logic to the wrong layer merely to shrink a diff;
- replaces a useful boundary with implicit coupling;
- weakens errors, validation, tests, compatibility, data integrity, or security;
- introduces a dependency, cache, global state, concurrency, or configuration to remove a small local
  amount of code.

## Candidate standard

Report a candidate only when the simpler form is concrete and behaviour preservation can be verified.
State the current machinery, the authoritative replacement or deletion, usage evidence, behavioural
boundary, affected locations, materiality, and fix risk.

Simplification findings are usually Medium or Low materiality. Classify a concern as High only when
the complexity creates a concrete near-term correctness, integrity, or change-safety risk. Reclassify
an actual defect under the review pass rather than inflating a cleanup finding.

After a change, inspect the resulting diff and confirm it is easier to understand rather than merely
shorter. Run the production-path tests and checks invalidated by the change before the next pass.
