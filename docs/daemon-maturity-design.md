# Design: Daemon Tickets And Maturity-Gated Dependencies

```yaml
project_code: daemon-maturity
ticket: ABC-232
base_branch: main
requirements_source: docs/daemon-maturity-requirements.md
```

## Purpose

This is the canonical implementation design source for the `daemon-maturity`
project in the Orchestra fork of `openai/symphony`. It translates the accepted
requirements from `docs/daemon-maturity-requirements.md` into architecture,
state and workflow assumptions, sequencing constraints, verification work, and
validation boundaries.

This document does not create fan-out payloads, implementation tickets, scratch
infrastructure, deploy handoffs, or implementation changes. The follow-up plan
ticket should be able to fan out work from this design without making new
product-scope judgments.

## Source Inputs

Source keys in this document extend the requirement source keys from
`docs/daemon-maturity-requirements.md`. Public readers who cannot access
internal Linear or Google Drive sources should treat the requirements document
as the dereferenceable public record of those sources.

- `D1`: `docs/daemon-maturity-requirements.md`, created by `ABC-231` and merged
  to `main` in PR #1.
- `D2`: Linear issue `ABC-232` and Linear project metadata for
  `daemon-maturity`, read through Symphony Linear GraphQL on 2026-07-25.
- `D3`: Uploaded and local specs `A-daemon-tickets.md`, byte-identical,
  SHA-256
  `35d41575022a0030af9b73909a325f88f7d2584c0afd054a87ec04714677b0eb`.
- `D4`: Google Doc `Daemon Tickets - Design Handoff (v2)`, fetched through the
  Symphony reader service account, SHA-256
  `b52f85b72709075449c44db207e96a0e758c27fd4be6a8c5bdfced9cd4040d2f`.
- `D5`: Google Doc `Maturity-Gated Dependencies - Design Handoff (v2)`,
  fetched through the Symphony reader service account, SHA-256
  `7a4d9bcdf19e4fbb452db3b8a228aef1464eba61c8f84326f7c1aa510385ea45`.
- `D6`: Google Doc `Minimal Ticket State Model - Design Handoff (v7)`, fetched
  through the Symphony reader service account, SHA-256
  `ae2a97e943f43a7ece9e050da81a9a2e7ff70dc50384997fbda7afb71a2fe91e`.
- `D7`: Local Symphony operator workflow contract and skills read for this
  ticket: `WORKFLOW.md`, `.codex/skills/symphony-project-factory/SKILL.md`,
  and `.codex/skills/karpathy-guidelines/SKILL.md`.
- `D8`: Current target fork context on `main`, including `SPEC.md`,
  `docs/daemon-maturity-requirements.md`, `elixir/AGENTS.md`,
  `elixir/lib/symphony_elixir/linear/client.ex`,
  `elixir/lib/symphony_elixir/orchestrator.ex`,
  `elixir/lib/symphony_elixir/config/schema.ex`,
  `elixir/lib/symphony_elixir/linear/issue.ex`,
  `elixir/lib/symphony_elixir/agent_runner.ex`, status dashboard code, and
  existing tests in `elixir/test/symphony_elixir/*`.

Source precedence remains `D6 > D4 > D3` wherever those sources conflict. In
particular, the old tracker-metadata `next_wake_at` and `last_evaluated_at`
scheme must not be implemented. Wake durability is labels plus sentinel-headed
comments. [D1, D4, D6]

## Settled Design Decisions

- Daemon tickets add a clock-aware dispatch path:
  `eligible = f(snapshot, now)`. Normal ticket dispatch remains snapshot-based
  except for the maturity gate. [D1:R1, D1:R2, D4, D6]
- Resting daemon states are configured through `tracker.daemon_states` alongside
  `tracker.active_states` and `tracker.terminal_states`. For the minimal state
  model, the resting daemon states are `Happy` and `Unhappy`. [D1:R1, D6]
- A daemon sleep is durable only through tracker-visible data:
  a daemon marker, a `wake:*` cadence label, and exact sentinel-headed verdict
  comments. Attachment JSON and in-memory timers are out of scope for sleeps.
  [D1:R4, D4, D6]
- The daemon lease write is the orchestrator flipping the ticket to the
  configured Active state before dispatch. The wake clock is not advanced
  through `next_wake_at`; it is re-derived from the latest verdict comment and
  cadence on the next resting poll. [D1:R7, D4, D6]
- A daemon may wait on normal blocking tickets, but daemon tickets are never
  real blockers for other work. Daemon-state blockers in the maturity gate are
  ignored with a warning because they never become terminal or mature. [D1:R6,
  D1:R15, D4, D5, D6]
- Maturity-gated dependency dispatch is a stateless, direct-edge gate over
  Linear native blocker relations. The orchestrator must not read GitHub for the
  maturity decision. [D1:R10, D1:R12, D5]
- Phase 1 does not implement per-ticket stack override semantics.
  `stack:eager|after-review|after-land` labels are reserved for a later
  enhancement and must not widen dispatch eligibility before the maturity gate
  is satisfied. [D1:R13]
- Blocker maturity regression after a dependent has dispatched prods the
  dependent once per observed transition and never kills the worker. If the
  dependent has not dispatched, it simply becomes ineligible again. [D1:R14, D5]
- Class-based concurrency budgets are engine behavior, not cookbook guidance.
  They are configured as absolute counts, with missing non-implementation class
  ceilings defaulting to `floor(max_concurrent_agents / 2)`, floors defaulting
  to `0`, and no urgent escape hatch in phase 1. [D1:R19]

## Current Implementation Anchors

The current fork already has the main seams needed for this work:

| Surface                                                 | Current fact                                                                      | Design consequence                                                                                                               |
| ------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `SymphonyElixir.Config.Schema.Tracker`                  | Config has `active_states` and `terminal_states`.                                 | Add `daemon_states`, maturity labels, daemon marker, and wake defaults through the same typed config path.                       |
| `SymphonyElixir.Config.Schema.Agent`                    | Config has `max_concurrent_agents` and per-state limits.                          | Keep per-state limits as legacy guards; add class budgets for R19 because daemon evaluations run in Active state after lease.    |
| `SymphonyElixir.Linear.Client.fetch_candidate_issues/0` | Fetches active-state issues, labels, and direct blockers from `inverseRelations`. | Extend blocker refs to include blocker labels; add a daemon-state fetch path with comments for wake evaluation.                  |
| `SymphonyElixir.Linear.Issue`                           | Normalized issue has labels and `blocked_by` with id, identifier, and state.      | Extend blocker refs with labels; add enough comment data for daemon wake snapshots without exposing raw Linear payloads broadly. |
| `SymphonyElixir.Orchestrator.maybe_dispatch/1`          | Tick order is reconcile, validate, fetch candidates, sort, dispatch.              | Insert daemon wake leasing after validation and before final dispatch selection. Keep reconciliation first.                      |
| `should_dispatch_issue?/4`                              | Blocks `Todo` issues when any blocker is non-terminal.                            | Replace the hardcoded terminal-only helper with the maturity gate for direct blockers.                                           |
| `dispatch_issue/4`                                      | Revalidates the issue by id immediately before dispatch.                          | Revalidate leased daemon Active state and maturity-blocker labels before dispatch.                                               |
| `handle_agent_down/5` and retry helpers                 | Failure retry delay is in-memory and capped only by delay.                        | Add a daemon-specific retry-exhaustion boundary before parking to Unhappy; do not use retry timers as sleep state.               |
| `Orchestrator.snapshot/2` and `StatusDashboard`         | Reports running/retry/blocking activity but not class occupancy.                  | Add dispatch class occupancy and budget data for R19.                                                                            |

## State Classes And Identity

### Config

Add typed tracker config:

```yaml
tracker:
  active_states:
    - Active
  terminal_states:
    - Done
    - Cancelled
  daemon_states:
    - Happy
    - Unhappy
  daemon_dispatch_state: Active
  daemon_label: daemon
  daemon_default_wake: 1h
  maturity_labels:
    - mature
```

Names are trimmed and compared lowercase, matching existing active and terminal
state behavior. `daemon_dispatch_state` must normalize to one configured active
state. `daemon_states` must be disjoint from active and terminal states after
normalization. `maturity_labels: []` reproduces upstream terminal-only blocker
behavior. [D1:R1, D1:R4, D1:R10]

The `daemon_label` is a durable identity marker, not a state class. It solves an
Active recovery gap: once a daemon is leased to Active, the resting state no
longer identifies it as a daemon. Active daemon recovery, class budgeting, and
the daemon exit contract therefore need a tracker-visible daemon identity that
survives the state flip. A daemon issue is recognized as daemon-owned when
either its state is in `daemon_states` or it carries the configured
`daemon_label`. [D3, D4, D6]

### Dispatch Classes

Dispatch classes for R19 are derived per candidate:

- `daemon`: a daemon issue leased from a resting daemon state or an Active issue
  that carries `daemon_label`.
- `implementation`: a non-daemon issue in `active_states`.
- `terminal` and non-active waiting states: not dispatch classes because they
  are not dispatch candidates.

The dispatch class must be copied into running and retry metadata. Counting by
current Linear state is insufficient because a daemon evaluation is Active while
running. [D1:R7, D1:R19]

## Daemon Wake Design

### Durable Wake Fields

Daemon wake evaluation uses only fields that can be read again after restart:

- issue id, identifier, state, labels, blockers, created time, and updated time;
- exact `daemon_label`;
- exact `wake:*` label, if present;
- Linear comments on daemon issues, including id, body, and `createdAt`;
- direct blockers and their states.

Supported cadence labels are exactly `wake:15m`, `wake:1h`, `wake:4h`, and
`wake:1d`. Labels are lowercased and trimmed before matching. If no supported
cadence label is present, if an unsupported `wake:*` label is present, or if
multiple supported cadence labels conflict, use `daemon_default_wake` and log a
warning. These cases must never mean wake-now. [D1:R4, D4, D6]

The exact sentinel header is:

```md
## Symphony Daemon Verdict
```

A verdict comment is any comment whose body, after leading whitespace is
trimmed, starts with that exact line. The latest verdict comment by `createdAt`
is the last-evaluated anchor. The author is ignored because many actors may
share one bot identity. [D1:R4, D4, D6]

Verdict comments should include human-readable fields below the header:

```md
## Symphony Daemon Verdict

verdict: happy|unhappy|unevaluated
reason: <short reason>
```

Only the sentinel and `createdAt` are dispatch inputs. The rest of the body is
audit trail for humans and agents. Orchestrator-authored exhaustion comments
must use `verdict: unevaluated` and park the issue in Unhappy. [D1:R5, D1:R8]

Daemon creation should include an initial sentinel verdict comment so the first
wake has a durable anchor. If a resting daemon lacks a verdict comment, the
fallback anchor is the issue `created_at` plus the default cadence, with a
warning. This preserves the invariant that missing wake state means default
interval, never wake-now. [D1:R3, D1:R4, D6]

### Wake Function

The pure wake function is:

```text
daemon_wake_verdict(issue, now, config) ->
  :not_daemon
  {:sleep, next_wake_at}
  {:wake, reason}
  {:blocked, blockers}
  {:invalid, warning}
```

Inputs are the current snapshot and `now`. The function does not read process
memory, does not mutate Linear, and does not inspect GitHub.

Wake order:

1. If the issue is not daemon-owned, return `:not_daemon`.
2. If the issue is in Active state, do not wake it; normal active dispatch owns
   it.
3. If any direct normal blocker is not terminal, return `{:blocked, blockers}`.
   Maturity labels do not unblock daemon sleeps; daemon sleeps wait for normal
   blockers to complete.
4. Resolve cadence from `wake:*` labels or `daemon_default_wake`.
5. Find the latest sentinel verdict comment by `createdAt`.
6. Compute timer due time from the anchor plus cadence plus jitter.
7. If any non-verdict comment has `createdAt` newer than the latest verdict,
   return `{:wake, :prod}`.
8. If `timer_due_at <= now`, return `{:wake, :timer}`.
9. Otherwise return `{:sleep, timer_due_at}`.

Wake reason is advisory. The daemon evaluator must always re-read the world at
evaluation time. Multiple prods coalesce because the wake function only needs to
know that at least one comment is newer than the latest verdict. [D1:R2, D1:R5]

### Jitter

Per-sleep jitter is one of `[-60, -30, 0, 30, 60]` seconds. Because no separate
jitter field is stored, jitter must be deterministic from durable sleep inputs:
the daemon issue id, the latest verdict comment id when present, the cadence,
and the anchor timestamp. This gives stable restart behavior while distributing
wakes across daemon tickets. Tests should inject the jitter function so fake
clock tests can assert exact due times. [D1:R3, D4, D6]

On orchestrator startup, overdue daemon dispatches may be staggered by an
in-memory random delay of a few ticks. Startup staggering is only a load-shed
optimization. Losing it on restart is acceptable because durable wake
eligibility is still derived from tracker state. [D1:R3]

### Lease At Dispatch

When a resting daemon returns `{:wake, reason}`, the orchestrator leases it with
one tracker write:

1. Update the issue state to `daemon_dispatch_state`.
2. Re-fetch the issue by id.
3. Dispatch it through the normal active dispatch path with
   `dispatch_class: daemon`.

If the state write fails, no claim is recorded and the daemon remains eligible
for a later poll. If the state write succeeds and the orchestrator crashes
before dispatch, restart recovery sees an Active daemon with `daemon_label` and
dispatches it as normal active work. If the agent crashes while evaluating,
normal active retry re-dispatches the daemon and the idempotent evaluator
re-derives the verdict. [D1:R7, D4, D6]

The lease write does not write `next_wake_at`, `last_evaluated_at`, attachment
JSON, or any in-memory sleep timer. The next sleep is established only when the
agent or exhaustion path writes a new sentinel verdict comment and moves the
ticket to Happy or Unhappy. [D1:R4, D1:R7, D1:R8]

### Agent Exit Contract

A daemon evaluator exits successfully only after it:

1. writes a sentinel-headed verdict comment;
2. sets the ticket state to Happy or Unhappy;
3. leaves the daemon marker and cadence labels in a valid state;
4. records any prod target in the verdict or a separate ordinary comment.

The evaluator must be idempotent and at least once. It should tolerate
duplicate evaluation, duplicate prods, and stale wake reasons by re-reading
Linear state before deciding the verdict. [D1:R5]

### Failure Handling

Daemon evaluation uses the normal worker failure retry path until a configured
daemon retry limit is exhausted. Add daemon-specific config:

```yaml
agent:
  daemon_max_retry_attempts: 3
```

The default daemon retry limit is `3`. The implementation follow-up must verify
how this composes with the current retry path, but the design requires a finite
daemon exhaustion boundary because current retry backoff is delay-capped, not
attempt-capped. On daemon retry exhaustion:

1. cancel the retry entry and release the normal Active claim;
2. post an orchestrator-authored sentinel verdict comment with
   `verdict: unevaluated`;
3. move the issue to Unhappy;
4. leave the daemon marker and cadence labels in place;
5. do not immediately re-dispatch the daemon.

The unevaluated verdict resets the wake clock to the next cadence interval and
prevents hot loops. [D1:R8, D8]

## Maturity-Gated Dependency Design

### Blocker Snapshot Shape

Extend blocker refs from:

```elixir
%{id: id, identifier: identifier, state: state}
```

to:

```elixir
%{
  id: id,
  identifier: identifier,
  state: state,
  labels: labels
}
```

The Linear query already reads direct blockers through `inverseRelations` whose
`type` is `blocks`. The implementation must add blocker label nodes to that
nested `issue` selection and keep labels normalized lowercase. The open Linear
verification still has to prove this nested label visibility for blocked and
non-candidate tickets before implementation relies on it. [D1:R10, D1:R17, D8]

### Gate Function

Replace the current terminal-only `Todo` blocker helper with a pure direct-edge
gate:

```text
maturity_gate(issue, config) ->
  :eligible
  {:blocked, blockers}
  {:eligible_with_warnings, warnings}
```

A direct blocker is satisfied when any of these is true:

- its state is in `terminal_states`;
- its state is in `daemon_states`, in which case the edge is ignored and a
  warning is emitted because daemon blockers are plan bugs;
- `maturity_labels` is non-empty and the blocker has at least one configured
  maturity label.

If `maturity_labels` is empty, only terminal blockers satisfy the gate, except
for ignored daemon-state blockers. The gate is evaluated from the current
snapshot every tick and during dispatch revalidation. It adds no GitHub reads
and no tracker writes. [D1:R10, D1:R12, D1:R15]

The gate should apply to candidate issues with blockers, not to a hardcoded
`Todo` state name. Under the minimal state model, blocked normal tickets sit in
Active and are held by this gate until their direct blockers are terminal or
mature. [D1:R10, D1:R11, D6]

### Stack Labels

`stack:eager`, `stack:after-review`, and `stack:after-land` are reserved labels
on the dependent ticket. The parser should be pure and deterministic:

- no stack label -> workflow default;
- exactly one known stack label -> parsed mode;
- unknown or conflicting `stack:*` labels -> workflow default with a warning;
- unknown or conflicting labels never resolve to eager.

Phase 1 must not let the parsed stack mode change dispatch eligibility. All
phase-1 dependents still require the maturity gate from the previous section.
This keeps `stack:*` vocabulary from widening eligibility before the later
product decision captured in the requirements. [D1:R13]

When a later enhancement enables stack overrides, the same parser can feed the
edge-local gate:

- `stack:eager`: eligible once blocker branches or joins exist, without waiting
  for maturity;
- `stack:after-review`: eligible when blockers are terminal or mature;
- `stack:after-land`: eligible only when blockers are terminal.

That future behavior belongs to a separate enhancement ticket and is not a
phase-1 implementation boundary. [D1:R13]

### Regression Prod

Regression detection compares the previous and refreshed blocker snapshots for
running or claimed dependents. If a direct blocker that previously satisfied
the maturity label condition no longer satisfies it and is still non-terminal:

1. if the dependent is running or otherwise claimed by the orchestrator, create
   one advisory comment on the dependent issue;
2. keep the worker running;
3. update the stored running snapshot so the same transition is not commented
   every tick;
4. if comment creation fails, log the failure and keep the worker running.

The prod is best-effort and in-memory transition memory is acceptable. If the
orchestrator restarts and misses a regression transition, the dependent agent
is still responsible for handling base changes and review feedback through
normal workflow. [D1:R14, D5]

If the dependent has not dispatched, no prod is needed. The next dispatch
evaluation simply sees the blocker as immature and skips the dependent.

## Class-Based Concurrency Budgets

R19 is resolved as absolute class budgets:

```yaml
agent:
  max_concurrent_agents: 10
  max_concurrent_agents_by_class:
    daemon:
      ceiling: 5
      floor: 0
```

For each non-implementation class:

- `ceiling` is optional and defaults to `floor(max_concurrent_agents / 2)`;
- `floor` is optional and defaults to `0`;
- values are absolute counts, not percentages;
- validation rejects negative counts, blank class names, floors above
  `max_concurrent_agents`, and ceilings below floors.

Implementation work has no explicit ceiling. It can use any global slot not
reserved by a non-implementation class floor. There is no urgent escape hatch in
phase 1. If an actual urgent-recurring use case appears, it should be designed
as a later product change. [D1:R19]

Dispatch selection remains sorted by existing priority, creation time, and
identifier. The budget check is applied as each sorted candidate is considered:

1. compute running occupancy by `dispatch_class`;
2. compute global free slots;
3. for a daemon candidate, require global free slots and daemon occupancy below
   daemon ceiling;
4. for an implementation candidate, require global free slots beyond any
   currently unfilled non-implementation floors;
5. keep existing worker-host and legacy per-state limits as additional guards
   until a later cleanup removes per-state limits.

The status snapshot and terminal dashboard must report class occupancy and
budget limits. At minimum, expose `class_occupancy` in `Orchestrator.snapshot/2`
and render a compact line in the terminal dashboard. [D1:R19, D8]

## Documentation And Repository Strategy

`DIVERGENCES.md` must exist before the first implementation divergence lands.
For this project, implementation work should add paragraphs only as behavior
lands. The initial required paragraphs are:

- daemon states and wake semantics;
- the daemon lease state flip and exhaustion park;
- maturity-gated dependency dispatch;
- class-based concurrency budgets.

Cookbook material must not be placed in `DIVERGENCES.md`. Cookbook entries
should cover:

- the project-completion sentinel daemon pattern;
- daemon verdict comment conventions;
- repo-neutral and multi-repo workspace conventions;
- plan-side maturity-label and stack-label conventions when those conventions
  are introduced.

The fork's `main` branch remains merge-maintained. The derived rebased branch is
a read-only artifact and must be tree-equal to `main` with CI evidence before
the project relies on it. [D1:R16, D1:R17]

## Verification Boundaries

These items are open verification work, not settled implementation behavior:

| Verification                                                                                                                                                               | Owner/follow-up                                   | Blocks                                                              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| Current `SPEC.md` facts: state defaults, tick sequence, retry formula, restart semantics, hook contract, issue `branch_name`, and upstream TODOs.                          | Verification ticket under Jeremy Carroll.         | Any implementation that relies on upstream compatibility claims.    |
| Linear daemon wake fetch mechanics: comment cost, comment ordering, comment pagination, `wake:*` label visibility, daemon marker label visibility, and blocker visibility. | Daemon wake verification follow-up.               | Daemon wake eligibility and Linear binding implementation.          |
| Linear maturity mechanics: relation direction, nested blocker labels, label-change visibility in refreshed snapshots.                                                      | Maturity gate verification follow-up.             | `maturity_labels`, daemon-blocker warnings, and regression prods.   |
| Tree-equality CI between fork `main` and the derived rebased branch.                                                                                                       | Repo strategy and CI follow-up.                   | Any adoption-branch claims.                                         |
| Linear custom state setup for the minimal state model.                                                                                                                     | State model migration follow-up.                  | Workflow migration to `Active`, `Inactive`, `Happy`, and `Unhappy`. |
| Existing retry exhaustion behavior.                                                                                                                                        | Daemon failure-handling implementation follow-up. | Parking failed daemon evaluations back to Unhappy.                  |

If any required verification fails, the implementation ticket must record the
failure and either adjust this design with a source-backed decision or stop for
human input. [D1:R17, D1:R18]

## Sequencing Constraints

The plan ticket should preserve these constraints without treating them as a
prebuilt fan-out payload:

- Run upstream/Linear verification before implementation tickets depend on
  those facts.
- Add config and pure state-class helpers before daemon wake or maturity gates
  need them.
- Add class-budget selection before daemon evaluations can occupy shared
  dispatch slots for long periods.
- Implement daemon wake as pure functions with fake-clock tests before adding
  the Linear state flip.
- Implement the lease flip and Active crash recovery before the project
  sentinel demo.
- Implement daemon Linear binding before daemon failure parking, because the
  parking path writes the same sentinel verdict format.
- Implement blocker-label fetch and the maturity gate before regression prod
  behavior.
- Create `DIVERGENCES.md` before the first behavior divergence PR lands.
- Add cookbook material when the corresponding convention exists; do not
  pre-document conventions that have not landed.

## Validation Strategy

Required implementation validation:

- Config tests for `daemon_states`, `daemon_dispatch_state`, `daemon_label`,
  `daemon_default_wake`, `maturity_labels`, and class budgets.
- Pure fake-clock daemon wake tests for timer wake, prod wake, no verdict
  fallback, conflicting wake labels, deterministic jitter, blocked daemons, and
  startup overdue staggering.
- Lease and restart recovery tests:
  - state flip succeeds and dispatches daemon as class `daemon`;
  - crash after state flip but before dispatch re-dispatches the Active daemon;
  - crash during evaluation reuses normal Active retry;
  - retry exhaustion parks to Unhappy and writes an unevaluated verdict.
- Linear client tests for comment normalization, verdict sentinel detection,
  blocker label normalization, and direct relation direction.
- Maturity gate tests with synthetic depth-2 and depth-3 graphs:
  terminal blockers, mature blockers, immature blockers, daemon-state blockers,
  empty `maturity_labels`, and eligible -> regressed -> eligible transitions.
- Stack-label parser tests proving phase-1 labels do not widen eligibility.
- Regression prod tests proving the dependent worker is not killed and duplicate
  comments are not emitted every tick.
- Class-budget tests using deterministic synthetic candidates and running
  entries to prove daemon ceilings, floors, implementation slot reservation, and
  no urgent escape hatch.
- Status snapshot/dashboard tests proving class occupancy is visible.
- Markdown/doc checks for `DIVERGENCES.md` and cookbook files as they are added.

Project-level evidence must include observable Linear proof for the sentinel
daemon and depth-2 maturity dispatch. Unit tests alone are insufficient for
those demos. [D1:R18]

## Requirement Coverage

| Requirement                     | Design coverage                                                          |
| ------------------------------- | ------------------------------------------------------------------------ |
| R1 daemon state class           | `tracker.daemon_states`, daemon marker label, and dispatch class design. |
| R2 daemon wake eligibility      | Pure wake function with timer and prod reasons.                          |
| R3 restart tolerance and jitter | Deterministic durable jitter plus startup staggering.                    |
| R4 Linear wake binding          | `wake:*` parsing and sentinel verdict comment anchor.                    |
| R5 evaluation contract          | Agent exit contract and idempotent evaluation requirement.               |
| R6 blocked daemons              | Terminal-only normal blocker gate for daemon sleeps.                     |
| R7 lease at dispatch            | State flip to `daemon_dispatch_state` and Active recovery.               |
| R8 failure handling             | Finite daemon retry exhaustion and unevaluated verdict park.             |
| R9 project sentinel demo        | Cookbook and validation boundary for real Linear sentinel evidence.      |
| R10 maturity gate               | Direct-edge `maturity_labels` gate over blocker state and labels.        |
| R11 depth-2-and-deeper dispatch | Edge-local, depth-agnostic gate plus depth-2/depth-3 tests.              |
| R12 external maturity signal    | No GitHub reads; labels/comments must mirror maturity into Linear.       |
| R13 phase-1 maturity scope      | Stack labels reserved and parsed safely without widening eligibility.    |
| R14 regression behavior         | One advisory prod per observed maturity regression; worker continues.    |
| R15 daemon blockers             | Daemon-state blockers ignored with warnings in maturity gate.            |
| R16 divergences and docs        | `DIVERGENCES.md` and cookbook boundaries.                                |
| R17 verification-first          | Verification boundary table and sequencing constraints.                  |
| R18 reviewable evidence         | Validation strategy names command/evidence expectations.                 |
| R19 class budgets               | Absolute class-budget design, no urgent escape hatch, status reporting.  |

## ABC-232 Done Predicate

This design ticket is done when:

- this document is committed in the target fork;
- Markdown formatting passes for this document;
- requirement coverage above is complete or explicitly deferred with owner and
  follow-up;
- the Linear workpad records source-read evidence, assumptions, selected design
  path, unresolved questions, and validation evidence;
- no fan-out plan, implementation ticket, scratch infrastructure, deploy
  handoff, or implementation change is created from this ticket.
