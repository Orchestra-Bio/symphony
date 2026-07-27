# Design: Daemon Tickets And Maturity-Gated Dependencies

```yaml
project_code: daemon-maturity
ticket: ABC-232
base_branch: main
requirements_source: docs/symphony-plans/daemon-maturity-requirements.md
```

## Purpose

This is the canonical implementation design source for the `daemon-maturity`
project in the Orchestra fork of `openai/symphony`. It translates the accepted
requirements from `docs/symphony-plans/daemon-maturity-requirements.md` into
architecture, state and workflow assumptions, sequencing constraints,
verification work, and validation boundaries.

This document does not create fan-out payloads, implementation tickets, scratch
infrastructure, deploy handoffs, or implementation changes. The follow-up plan
ticket should be able to fan out work from this design without making new
product-scope judgments.

Scope test: if a decision changes Elixir code or the config schema in this fork,
it is designed here. If it does not, it is an external dependency; this document
records the contract this project consumes, the owner that implements it, and
how the orchestrator degrades when the contract is broken. Config schema is fork
code and in scope. Deployment config values, Linear team state/label instances,
agent-writing conventions, plan DAG shape, and operator `WORKFLOW.md` behavior
are external dependencies. `DMAT-013` owns creating the configured Linear team
states and labels; this fork owns consuming configured names and preserving safe
degraded behavior when they are absent.

## Source Inputs

Source keys in this document extend the requirement source keys from
`docs/symphony-plans/daemon-maturity-requirements.md`. Public readers who cannot
access internal Linear or Google Drive sources should treat the requirements
document as the dereferenceable public record of those sources.

- `D1`: `docs/symphony-plans/daemon-maturity-requirements.md`, created by
  `ABC-231`, merged to `main` in PR #1, and amended by this PR.
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
  `docs/symphony-plans/daemon-maturity-requirements.md`, `elixir/AGENTS.md`,
  `elixir/lib/symphony_elixir/linear/client.ex`,
  `elixir/lib/symphony_elixir/orchestrator.ex`,
  `elixir/lib/symphony_elixir/config/schema.ex`,
  `elixir/lib/symphony_elixir/linear/issue.ex`,
  `elixir/lib/symphony_elixir/linear/adapter.ex`,
  `elixir/lib/symphony_elixir/agent_runner.ex`, status dashboard code, and
  existing tests in `elixir/test/symphony_elixir/*`.
- `D9`: GitHub PR #2 human review and handoff comments from 2026-07-25. These
  supersede earlier handoff text for daemon wake prods, daemon dispatch state,
  comment anchoring, one-shot wait breadth, and recurring-work concurrency.
- `D10`: GitHub PR #3 human review, decision comments D-A/D-B/D-C, and approval
  review from 2026-07-25. These supersede earlier handoff and requirements text
  for fan-out promotion state, late `DIVERGENCES.md` timing, real-use evidence,
  and the `maturity_gate_state_scope` switch-risk reducer.
- `D11`: Linear issue `ABC-282` / `DMAT-002` verification work from
  2026-07-25, including the confirmed `retry_candidate_issue?/2` call sites.
- `D12`: Linear issues `ABC-292` / `DMAT-012`, `ABC-295` / `DMAT-013`, and
  `ABC-296` / `DMAT-014` from 2026-07-25. These establish team-scoped dispatch,
  team configuration, and plural `daemon_dispatch_states` as current project
  requirements.
- `D13`: GitHub PR #10 human review, follow-up, and decision comments from
  2026-07-26. These are the decision source for narrowing comment refs to
  `id`/`updatedAt`, defaulting `maturity_labels` to `[]`, and replacing the
  nonexistent `make -C elixir specs.check` instruction with `mix specs.check`.

Source precedence remains `D6 > D4 > D3` unless a later human decision source
explicitly supersedes the handoff text for this project. The old
tracker-metadata `next_wake_at` and `last_evaluated_at` scheme must not be
implemented. Wake durability is labels plus titled workpad comments, not
attachment JSON, tracker metadata, or in-memory timers. [D1, D4, D6, D9, D10,
D12]

## Settled Design Decisions

- Daemon tickets add a clock-aware dispatch path:
  `eligible = f(snapshot, now)`. Normal ticket dispatch remains snapshot-based
  except for the maturity gate. [D1:R1, D1:R2, D4, D6]
- Comments never cause daemon wake eligibility. A sleeping daemon wakes only by
  timer; urgent wake is a state write to the first configured daemon dispatch
  state. Comments left while sleeping are input for the next scheduled
  evaluation. [D1:R2, D9, D12]
- Resting daemon states are configured through `tracker.daemon_states`.
  Separate `tracker.daemon_dispatch_states` entries are listed in
  `tracker.active_states` and are daemon-only. This deliberately adds at least
  one active state beyond the seven-state minimal model. [D1:R1, D1:R7, D6, D9,
  D12]
- Daemon-owned means `state in daemon_states` or
  `state in daemon_dispatch_states`. There is no `daemon_label`; state carries
  daemon identity across lease, recovery, and concurrency accounting. [D9, D12]
- A daemon sleep is durable only through tracker-visible data: a `wake:*`
  cadence label and the server-written `updatedAt` of titled workpad comments.
  The daemon's own workpad carries the real verdict; the orchestrator's own
  workpad carries exhaustion parks. [D1:R4, D1:R5, D4, D6, D9]
- The daemon lease write is the orchestrator flipping the ticket to the first
  configured daemon dispatch state before dispatch. The wake clock is not
  advanced through `next_wake_at`; it is re-derived from comment metadata and
  cadence on the next resting poll. [D1:R7, D4, D6, D9, D12]
- A daemon may wait on normal blocking tickets, but daemon tickets are never
  real blockers for other work. Daemon-state blockers in the maturity gate are
  ignored with a warning because they never become terminal or mature. [D1:R6,
  D1:R15, D4, D5, D6]
- Maturity-gated dependency dispatch is a stateless, direct-edge gate over
  Linear native blocker relations. The gate must replace the current
  terminal-only blocker helper in candidate selection, retry re-selection, and
  dispatch-time revalidation because the current revalidation path routes
  through `retry_candidate_issue?/2`. The orchestrator must not read GitHub for
  the maturity decision. [D1:R10, D1:R12, D5, D9, D11]
- `maturity_gate_state_scope`, defaulting to `["todo"]`, is the rollout scope
  for the blocker-gate replacement. It preserves the current hardcoded `Todo`
  state scope on switch so engine replacement and later gate widening are
  separately diagnosable. [D1:R10, D1:R11, D10, D12]
- Phase 1 does not implement per-ticket stack override semantics.
  `stack:eager|after-review|after-land` labels are reserved for a later
  enhancement and must not widen dispatch eligibility before the maturity gate
  is satisfied. [D1:R13]
- Blocker maturity regression after a dependent has dispatched leaves one
  advisory comment and never kills the worker. If the dependent has not
  dispatched, it simply becomes ineligible again. [D1:R14, D5, D9]
- R19 is satisfied by existing per-state concurrency limits: daemon evaluations
  use a dedicated dispatch state capped by `agent.max_concurrent_agents_by_state`.
  There is no class-budget engine work, no recurring-work floor, and no urgent
  escape hatch. [D1:R19, D9]

## Current Implementation Anchors

The current fork already has the main seams needed for this work:

| Surface                                                 | Current fact                                                                                | Design consequence                                                                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `SymphonyElixir.Config.Schema.Tracker`                  | Config has `active_states` and `terminal_states`.                                           | Add `daemon_states`, `daemon_dispatch_states`, `daemon_default_wake`, and `maturity_labels` through the same typed config path.        |
| `SymphonyElixir.Config.Schema.Agent`                    | Config has `max_concurrent_agents` and `max_concurrent_agents_by_state`.                    | Use existing per-state limits for R19; do not add `max_concurrent_agents_by_class` or floors.                                          |
| `SymphonyElixir.Linear.Client.fetch_candidate_issues/0` | Fetches active-state issues, labels, and direct blockers from `inverseRelations`.           | Extend blocker refs to include blocker labels; add a daemon sleep-candidate fetch path with comment metadata for wake evaluation.      |
| `SymphonyElixir.Linear.Issue`                           | Normalized issue has labels and `blocked_by` with id, identifier, and state.                | Extend blocker refs with labels; add normalized comment refs without exposing raw Linear payloads broadly.                             |
| `SymphonyElixir.Linear.Adapter.create_comment/2`        | Wraps a `commentCreate` mutation.                                                           | Orchestrator-authored exhaustion comments can use the existing create path when no orchestrator workpad exists.                        |
| `SymphonyElixir.Linear.Adapter`                         | Has no `commentUpdate` mutation today.                                                      | Edit-in-place workpads require a new mutation before daemon verdict and exhaustion comment binding can land.                           |
| `SymphonyElixir.Orchestrator.maybe_dispatch/1`          | Tick order is reconcile, validate, fetch candidates, sort, dispatch.                        | Insert daemon wake leasing after validation and before final dispatch selection. Keep reconciliation first.                            |
| `should_dispatch_issue?/4`                              | Blocks `Todo` issues when any blocker is non-terminal.                                      | Replace the hardcoded terminal-only helper with the shared maturity gate.                                                              |
| `retry_candidate_issue?/2`                              | Reuses the same terminal-only blocker helper on abnormal-exit retry lookup.                 | Use the same maturity gate as candidate selection so mature non-terminal blockers behave consistently after retry.                     |
| `revalidate_issue_for_dispatch/3`                       | Refetches the issue immediately before every dispatch and calls `retry_candidate_issue?/2`. | The shared maturity gate is evaluated during dispatch-time revalidation too; do not add a second separate maturity check there.        |
| `Orchestrator.State.blocked`                            | Tracks agent-reported blocked outcomes and has its own reconcile loop.                      | Do not reuse `blocked` terminology for maturity-gate return values; the gate returns `{:gated, blockers}` and leaves this state alone. |
| `dispatch_issue/4`                                      | Revalidates the issue by id immediately before dispatch.                                    | Revalidate daemon dispatch state and maturity-blocker labels before dispatch.                                                          |
| `handle_agent_down/5` and retry helpers                 | Failure retry delay is in-memory and capped only by delay.                                  | Add a daemon-specific retry-exhaustion boundary before parking to Unhappy; do not use retry timers as sleep state.                     |
| OTP supervision around orchestrator and workers         | Current code couples workers to orchestrator runtime under `:one_for_all`.                  | Treat durable leases as wake-eligibility exclusion, not distributed worker locking; verify SSH-spawned remote workers respect this.    |
| `Orchestrator.snapshot/2` and `StatusDashboard`         | Reports running/retry/blocking activity and current issue states.                           | Keep status reporting per-state; daemon budget visibility comes from daemon dispatch state occupancy.                                  |

## State Classes And Identity

### Config

Add typed tracker config:

```yaml
tracker:
  active_states:
    - Active
    - Evaluating
  terminal_states:
    - Done
    - Cancelled
  daemon_states:
    - Happy
    - Unhappy
  daemon_dispatch_states:
    - Evaluating
  daemon_default_wake: 1h
  maturity_labels: []
  maturity_gate_state_scope:
    - todo

agent:
  max_concurrent_agents: 10
  max_concurrent_agents_by_state:
    evaluating: 5
```

Names are trimmed and compared lowercase, matching existing active and terminal
state behavior. Every `daemon_dispatch_states` element must normalize to one
configured active state, the set must be non-empty when `daemon_states` is
non-empty, and it must be disjoint from daemon and terminal states.
`daemon_states` must be disjoint from active and terminal states after
normalization. The first configured `daemon_dispatch_states` element is the
lease write target. All configured elements are recognized for daemon identity,
crash recovery, and exclusion from implementation-class dispatch, which makes a
state rename window expressible as `[NewName, OldName]`: write to `NewName` and
still recognize tickets already sitting in `OldName`. `maturity_labels`
defaults to `[]`, which reproduces upstream terminal-only blocker behavior;
`["mature"]` is the standard explicit enablement value, not the default.
`maturity_gate_state_scope`, default `["todo"]`, is compared with the same
trimmed lowercase state-name normalization as other tracker state lists. It
limits where the blocker-gate replacement runs and intentionally keeps the
initial switch at the current hardcoded `Todo` scope. Widening the scope is a
deployment configuration change, not new code. [D1:R1, D1:R4, D1:R10, D1:R11,
D9, D10, D12, D13]

Creating the named Linear states and labels is not fork code. The implementation
must validate and consume names as strings, and tests must be able to exercise
the pure wake and maturity logic from synthetic snapshots. The target Linear
team must have the configured states and labels before real use or switchover;
`DMAT-013` owns that operator work. [D1:R12, D12]

The daemon dispatch-state set is a deliberate deviation from the seven-state
minimal model. Each element is still a work-class state, not a pipeline state:
it is daemon-only and must be a Linear `Started`-type state so the existing
active-state machinery can dispatch and reconcile it. The exact deployed state
names are operator configuration outside this repository; the schema fields are
the fork contract. [D6, D9, D12]

### State Taxonomy

| State class           | Role                               | Dispatch behavior                                            |
| --------------------- | ---------------------------------- | ------------------------------------------------------------ |
| Backlog or inactive   | ordinary waiting work              | not fetched unless listed in `active_states`                 |
| implementation active | normal work                        | `active_states` minus `daemon_dispatch_states`               |
| daemon dispatch state | daemon evaluation lease target     | active, daemon-only, capped by per-state concurrency         |
| daemon resting states | Happy/Unhappy daemon sleep states  | fetched by daemon sleep-candidate logic, not normal dispatch |
| terminal states       | Done/Cancelled or configured equal | never dispatched                                             |

Daemon-owned is purely state-derived:

- `state in daemon_states`: sleeping daemon;
- `state in daemon_dispatch_states`: leased or crash-recovered daemon;
- anything else: not daemon-owned.

Implementation-class dispatch must use `active_states \ daemon_dispatch_states`,
not `active_states` wholesale. Otherwise a daemon in a dispatch state could be
treated as ordinary work. [D9, D12]

Warn when state-derived class and daemon evidence disagree:

- a ticket in a configured daemon dispatch state with no `wake:*` label and no
  titled daemon workpad is dispatched as a daemon but logged as a likely
  operator error;
- a daemon-looking ticket in an ordinary active state is dispatched as normal
  work and will not re-arm its sleep. This is the dangerous asymmetric failure.
  Operators forcing a daemon wake must flip it to the first configured daemon
  dispatch state, not to the ordinary implementation active state. [D9, D12]

### Recurring-Work Budget

No new class-budget config is added. R19 is met by putting daemon evaluations in
configured daemon dispatch states and capping each state through the existing
`agent.max_concurrent_agents_by_state`. These are ceilings only; there are no
reserved floors for recurring work. Status reporting remains per-state running
counts. [D1:R19, D9, D12]

## Daemon Wake Design

### Durable Wake Fields

Daemon wake evaluation uses only fields that can be read again after restart:

- issue id, identifier, state, labels, blockers, created time, and updated time;
- exact `wake:*` label, if present;
- comment metadata for the daemon's own titled workpad comment and the
  orchestrator's titled workpad comment: id and `updatedAt`;
- comment body only when an unrecognized comment id appears and the writer title
  must be determined;
- direct blockers and their states.

Supported cadence labels are exactly `wake:15m`, `wake:1h`, `wake:4h`, and
`wake:1d`. Labels are lowercased and trimmed before matching. If no supported
cadence label is present, if an unsupported `wake:*` label is present, or if
multiple supported cadence labels conflict, use `daemon_default_wake` and log a
warning. These cases must never mean wake-now. [D1:R4, D4, D6]

### Titled Workpad Comments

Daemons adopt the existing titled one-per-writer comment convention already used
by Symphony and Cadence: one comment per writer per target ticket, with writer
identity in the leading heading line, for example `## Codex Workpad`. Linear
does not expose a separate comment title, and author identity is insufficient
because multiple agents can share one bot account. [D9]

For daemon tickets, the daemon's own workpad carries verdict, reason, evidence,
and a rolling log of the last N evaluations. This merges the daemon verdict into
the self-workpad slot instead of inventing a second sentinel comment. The
orchestrator has its own writer identity and its own workpad for exhaustion
parks. The wake anchor is the later `updatedAt` of the daemon workpad and the
orchestrator workpad, when present. [D1:R4, D1:R5, D1:R8, D9]

Only the comment id and server-written `updatedAt` are steady-state wake inputs.
Human-readable timestamps in the body may be useful audit trail, but they are
not dispatch inputs. `issue.updatedAt` must never be used as a fallback anchor:
label edits, state flips, and unrelated comments can bump it and would silently
extend sleeps. [D9]

Assumed external invariant: each writer maintains at most one titled comment per
target ticket and edits it in place. The writer-side upsert protocol belongs to
the operator workflow and agent skills, not this fork. The fork consumes the
contract and degrades defensively:

- multiple comments matching this daemon's title are an anomaly; warn and use
  the latest `updatedAt`;
- a missing daemon workpad uses the issue `created_at` plus default cadence with
  a warning, never wake-now;
- cleanup of orphaned duplicate comments is out of scope for the orchestrator.

`Comment.updatedAt` existence and edit behavior is already verified on project
workpads. What remains for implementation is adding read support for comment
metadata, a narrow body-fetch path for newly seen comment ids, and a
`commentUpdate` mutation for edit-in-place workpads. [D8, D9]

### Wake Function

The pure wake function is:

```text
daemon_next_wake(issue, now, config) ->
  :not_daemon
  {:sleep, next_wake_at}
  :due
  {:gated, blockers}
  {:invalid, warning, next_wake_at}
```

Inputs are the current snapshot and `now`. The function does not read process
memory, does not mutate Linear, and does not inspect GitHub.

Wake order:

1. If the issue is not daemon-owned, return `:not_daemon`.
2. If the issue is in `daemon_dispatch_states`, do not wake it; normal active
   dispatch owns it.
3. If any direct normal blocker is not terminal, return `{:gated, blockers}`.
   Maturity labels do not unblock daemon sleeps; daemon sleeps wait for normal
   blockers to complete.
4. Resolve cadence from `wake:*` labels or `daemon_default_wake`.
5. Resolve the anchor from titled daemon/orchestrator workpad comment
   `updatedAt`, or from issue `created_at` with a warning when no comment exists.
6. Compute timer due time from the anchor plus cadence plus jitter.
7. If `timer_due_at <= now`, return `:due`.
8. Otherwise return `{:sleep, timer_due_at}`.

There is no wake reason and no comment-prodding branch. The daemon evaluator
must always re-read the world at evaluation time. Comments accumulated while the
daemon sleeps coalesce naturally because the next scheduled evaluation reads the
current ticket state. [D1:R2, D1:R5, D9]

### Jitter

Per-sleep jitter is one of `[-60, -30, 0, 30, 60]` seconds. Because no separate
jitter field is stored, jitter must be deterministic from durable sleep inputs:
the daemon issue id, the anchor comment id when present, the cadence, and the
anchor timestamp. This gives stable restart behavior while distributing wakes
across daemon tickets. Tests should inject the jitter function so fake-clock
tests can assert exact due times. [D1:R3, D4, D6]

On orchestrator startup, overdue daemon dispatches may be staggered by an
in-memory random delay of a few ticks. Startup staggering is only a load-shed
optimization. Losing it on restart is acceptable because durable wake
eligibility is still derived from tracker state. [D1:R3]

### Check-Back-Later Extension Point

Phase 1 is daemon-only, but the wake shape must not design out later one-shot
timed waits for non-daemon tickets. Preserve these extension points:

- express comment and label reads as a sleep-candidate predicate, not only
  `state in daemon_states`;
- compute a `next_wake_at` timestamp from inputs rather than threading cadence
  labels through the call path;
- keep lease target and exit contract as data: daemons lease to the daemon
  dispatch state and owe a verdict, while a future one-shot waiter would lease
  to ordinary active work and disarm without a daemon verdict;
- never use `issue.updatedAt` as a fallback anchor.

A later one-shot wait feature should keep the label-gated selection shape, but
not because `Inactive` breadth makes the query expensive: PR #2 review retracted
that breadth argument after verification showed a state-and-label poll remains a
single bounded Linear query. The useful bound is per-ticket comment volume,
which is controlled by writers rather than elapsed wait time. Timed waits are a
fallback for cases with no real event source, not a substitute for a bridge
where an event exists. [D9]

### Lease At Dispatch

When a resting daemon returns `:due`, the orchestrator leases it with one tracker
write:

1. Update the issue state to the first configured
   `daemon_dispatch_states` element.
2. Re-fetch the issue by id.
3. Dispatch it through the normal active dispatch path.

If the state write fails, no claim is recorded and the daemon remains eligible
for a later poll. If the state write succeeds and the orchestrator crashes
before dispatch, restart recovery sees a ticket in a configured daemon dispatch
state and dispatches it as daemon work. If the agent crashes while evaluating,
normal active retry re-dispatches the daemon and the idempotent evaluator
re-derives the verdict. [D1:R7, D4, D6, D9, D12]

The lease write always writes the first configured dispatch state, but recovery
recognizes every configured dispatch state. The lease write does not write
`next_wake_at`, `last_evaluated_at`, attachment
JSON, or any in-memory sleep timer. The next sleep is established only when the
agent or exhaustion path edits a titled workpad comment and moves the ticket to
Happy or Unhappy. Daemon dispatch states are wake-eligibility exclusions, not
distributed worker locks. [D1:R4, D1:R7, D1:R8, D9, D12]

### Agent Exit Contract

A daemon evaluator exits successfully only after it:

1. edits its own titled workpad comment with verdict, reason, evidence, and a
   bounded rolling log;
2. verifies by read-back that it edited the expected titled comment;
3. sets the ticket state to Happy or Unhappy;
4. leaves cadence labels in a valid state;
5. leaves any ordinary advisory comments needed for other tickets.

The evaluator must be idempotent and at least once. It should tolerate duplicate
evaluation, stale inputs, and informational comments by re-reading Linear state
before deciding the verdict. The writer-side edit-in-place protocol is an
external dependency owned by the operator workflow and agent skills; this fork
only relies on the resulting comment convention. [D1:R5, D9]

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

1. cancel the retry entry and release the normal active claim;
2. upsert the orchestrator's titled workpad comment with `verdict: unevaluated`;
3. move the issue to Unhappy;
4. leave cadence labels in place;
5. do not immediately re-dispatch the daemon.

The unevaluated verdict resets the wake clock to the next cadence interval and
prevents hot loops. If the original agent later writes a real verdict after an
orchestrator park, the real verdict supersedes the park and its state wins; the
residual interleaving can cause at most one extra wake, which the restart
tolerance accepts. Do not add locking or compare-and-swap behavior around Linear
comments. [D1:R8, D8, D9]

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

Replace the current terminal-only blocker helper with a pure direct-edge gate:

```text
maturity_gate(issue, config) ->
  :eligible
  {:gated, blockers}
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

The gate applies only when the candidate issue's normalized state is in
`maturity_gate_state_scope`. Outside that scope, the replacement preserves the
current non-`Todo` behavior by not applying blocker gating. The default
`["todo"]` makes the state scope of the replacement match the existing helper;
operators can widen the scope only after the engine switch is confirmed. [D1:R10,
D1:R11, D10, D12]

The same gate implementation must be used by all current call sites:

- `should_dispatch_issue?/4`, used during poll candidate selection;
- `retry_candidate_issue?/2`, used by abnormal-exit retry lookup paths;
- `revalidate_issue_for_dispatch/3`, which runs on every dispatch and calls
  `retry_candidate_issue?/2` after refetching the issue.

Without this sharing, a dependent stacked on a mature non-terminal blocker could
dispatch from the poll path and then become stranded after abnormal exit because
retry re-selection fell back to terminal-only blockers. Because dispatch-time
revalidation already routes through the shared helper, replacing the helper
covers that final pre-launch check too; adding a second maturity check there
would duplicate the same decision and create drift risk. [D9, D11]

The gate applies to candidate issues with blockers and to the configured state
scope, not to hardcoded code paths. Under the fork's current active-state shape,
the default `["todo"]` preserves the existing helper's state scope. A ticket
already running is untouched because dispatch selection skips running and
claimed ids. When its session ends, it is simply not re-selected while the gate
applies and the blocker remains unsatisfied. Under the minimal state model, the
same change collapses to the expected single-active-state gate, and a later
scope widening can be diagnosed separately from the engine switch. [D1:R10,
D1:R11, D6, D9, D10]

`Orchestrator.State.blocked` remains the agent-reported blocked-outcome map and
is untouched by this project. Maturity gating must use `{:gated, blockers}` or
equivalent naming to avoid colliding with that existing state. [D9]

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

This is a "prod" only in the informational sense: a comment for the running
agent to read. It is never a wake source. If the orchestrator restarts and
misses a regression transition, the dependent agent is still responsible for
handling base changes and review feedback through normal workflow. [D1:R14, D5,
D9]

If the dependent has not dispatched, no prod is needed. The next dispatch
evaluation simply sees the blocker as immature and skips the dependent.

## Plan-Side Obligations

The plan ticket consumes this design but owns graph and workflow conventions
outside the Elixir gate:

- `max_stack_depth` defaults to `3` and is a plan-side cap. The orchestrator gate
  is edge-local and must not walk transitive blockers or police depth.
- The plan must emit one Linear blocking relation per graph edge.
- Multi-blocker tickets need explicit join-base instructions in their task
  descriptions or fan-out plan entries.
- A blocker's agent, workflow bridge, or other external owner must set the
  configured maturity label when the blocker reaches the project-defined
  maturity point and remove it when maturity regresses.
- Until those external writers exist, the Elixir gate runs safely in degraded
  serial mode: dependents wait for terminal blockers.

This project consumes these contracts and degrades safely when they are broken:
missing labels mean serial dispatch, unknown stack labels do not widen
eligibility, over-depth graphs are plan bugs, and daemon blockers are warned and
ignored. [D1:R11, D1:R12, D1:R13, D1:R15, D9]

## Documentation And Repository Strategy

Project planning artifacts live under `docs/symphony-plans/` so Orchestra-owned
requirements and design documents are distinct from upstream-owned `docs/`
content. PR #3 decision D-B moves `DIVERGENCES.md` content late for this
project, beside cookbook and real-use evidence, while the independent
`SPEC.md` guardrail protects fork divergence records. Required paragraphs
include implemented behavior for:

- daemon states, timer-only wake semantics, and titled workpad anchors;
- the daemon-only dispatch state and per-state daemon budget;
- the daemon lease state flip and exhaustion park;
- maturity-gated dependency dispatch;
- the hardcoded `Todo` blocker-gate replacement and
  `maturity_gate_state_scope` rollout;
- team-scoped dispatch through `tracker.team_key` once `DMAT-012` lands.

Cookbook material must not be placed in `DIVERGENCES.md`. Cookbook entries
should cover:

- the project-completion sentinel daemon pattern;
- daemon workpad verdict conventions;
- repo-neutral and multi-repo workspace conventions;
- plan-side maturity-label and stack-label conventions when those conventions
  are introduced.

The one-orchestrator-per-team deployment invariant should be documented when
daemon behavior lands, because two orchestrators on one team would be an
operational defect. It should not be pre-documented by this design-only ticket.

The fork's `main` branch remains merge-maintained through true upstream merges.
The derived rebased branch and tree-equality CI are deferred until a real
upstream adoption conversation exists; they are not project dependencies for
daemon or maturity implementation. [D1:R16, D1:R17, D10, D12]

## Verification Boundaries

These items are open verification work, not settled implementation behavior:

| Verification                                                                                                                                                 | Owner/follow-up                                   | Blocks                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Current `SPEC.md` facts: state defaults, tick sequence, retry formula, restart semantics, hook contract, issue `branch_name`, and upstream TODOs.            | Verification ticket under Jeremy Carroll.         | Any implementation that relies on upstream compatibility claims.                                         |
| Linear daemon wake fetch mechanics: comment metadata shape, narrow body fetch for new comment ids, `commentUpdate`, `wake:*` label visibility, and blockers. | Daemon wake verification follow-up.               | Daemon wake eligibility and Linear binding implementation.                                               |
| Linear maturity mechanics: relation direction, nested blocker labels, label-change visibility in refreshed snapshots.                                        | Maturity gate verification follow-up.             | `maturity_labels`, daemon-blocker warnings, and regression prods.                                        |
| Linear team state and label configuration for the minimal state model, daemon dispatch states, daemon resting states, maturity labels, and wake labels.      | `DMAT-013` operator configuration follow-up.      | Real use and deployment switchover; implementation tests use configured strings and synthetic snapshots. |
| Existing retry exhaustion behavior.                                                                                                                          | Daemon failure-handling implementation follow-up. | Parking failed daemon evaluations back to Unhappy.                                                       |
| SSH-spawned remote worker termination under `:one_for_all`.                                                                                                  | Runtime verification follow-up.                   | Reliance on single-orchestrator/single-writer recovery semantics.                                        |

`Comment.updatedAt` existence and edit behavior is already verified by existing
project workpads; do not re-open it as an open verification. If any required
verification fails, the implementation ticket must record the failure and either
adjust this design with a source-backed decision or stop for human input.
[D1:R17, D1:R18, D9]

## Sequencing Constraints

The plan ticket should preserve these constraints without treating them as a
prebuilt fan-out payload:

- Run upstream/Linear verification before implementation tickets depend on
  those facts.
- Add config and pure state-class helpers before daemon wake or maturity gates
  need them.
- Add daemon dispatch-state validation and per-state budget examples before
  daemon evaluations can occupy dispatch slots for long periods.
- Add comment metadata reads, narrow body fetches, and `commentUpdate` support
  before daemon Linear binding or exhaustion parking.
- Implement daemon wake as pure timer functions with fake-clock tests before
  adding the Linear state flip.
- Implement the lease flip and daemon-dispatch-state crash recovery before the
  project sentinel demo.
- Implement daemon Linear binding before daemon failure parking, because the
  parking path writes the same titled-workpad format.
- Implement blocker-label fetch and the shared maturity gate for all current
  call sites before regression prod behavior.
- Keep `SPEC.md` untouched for fork divergences; write `DIVERGENCES.md` late,
  beside cookbook and real-use evidence, after behavior has settled.
- Add cookbook material when the corresponding convention exists; do not
  pre-document conventions that have not landed.

## Validation Strategy

Required implementation validation:

- Config tests for `daemon_states`, `daemon_dispatch_states`,
  `daemon_default_wake`, `maturity_labels`, and
  `maturity_gate_state_scope`; no `daemon_label` or class budget config exists.
- Per-state budget tests proving daemon evaluations are capped by
  `max_concurrent_agents_by_state` for each configured daemon dispatch state
  and cannot occupy the whole dispatch pool while implementation work is
  eligible.
- Pure fake-clock daemon wake tests for timer due, timer sleep, no comment
  fallback, conflicting wake labels, deterministic jitter, blocked daemons,
  duplicate titled comments, and startup overdue staggering.
- Tests proving comments do not wake daemons and `issue.updatedAt` is never used
  as a sleep anchor.
- Linear client tests for comment metadata normalization, narrow body-fetch
  writer identification, `commentUpdate`, blocker label normalization, and
  direct relation direction.
- Lease and restart recovery tests:
  - state flip succeeds to the first configured `daemon_dispatch_states` element
    and dispatches daemon work;
  - crash after state flip but before dispatch re-dispatches the daemon;
  - crash during evaluation reuses normal active retry;
  - retry exhaustion parks to Unhappy and writes an unevaluated orchestrator
    workpad entry;
  - a later real verdict supersedes an exhaustion park.
- Maturity gate tests with synthetic depth-2 and depth-3 graphs:
  terminal blockers, mature blockers, immature blockers, daemon-state blockers,
  empty `maturity_labels`, default `maturity_gate_state_scope: ["todo"]`,
  explicit scope widening, all gate call sites, and eligible -> regressed ->
  eligible transitions.
- Stack-label parser tests proving phase-1 labels do not widen eligibility.
- Regression prod tests proving the dependent worker is not killed, duplicate
  comments are not emitted every tick, and the comment is not treated as a wake
  source.
- Status snapshot/dashboard tests proving per-state running counts make daemon
  dispatch occupancy visible.
- Markdown/doc checks for `DIVERGENCES.md` and cookbook files as they are added.

Project-level evidence must include observable Linear proof for the sentinel
daemon and depth-2 maturity dispatch. Unit tests alone are insufficient for
those demos. [D1:R18]

## Requirement Coverage

| Requirement                     | Design coverage                                                                                            |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| R1 daemon state class           | `tracker.daemon_states`, `tracker.daemon_dispatch_states`, and state-derived identity.                     |
| R2 daemon wake eligibility      | Pure timer wake function; comments never wake, urgent wake is a state write.                               |
| R3 restart tolerance and jitter | Deterministic durable jitter plus startup staggering.                                                      |
| R4 Linear wake binding          | `wake:*` parsing and titled workpad `updatedAt` anchor.                                                    |
| R5 evaluation contract          | Workpad edit-in-place contract and idempotent evaluation requirement.                                      |
| R6 blocked daemons              | Terminal-only normal blocker gate for daemon sleeps.                                                       |
| R7 lease at dispatch            | State flip to the first `daemon_dispatch_states` element and crash recovery across the configured set.     |
| R8 failure handling             | Finite daemon retry exhaustion and unevaluated orchestrator workpad park.                                  |
| R9 project sentinel demo        | Cookbook and validation boundary for real Linear sentinel evidence.                                        |
| R10 maturity gate               | Direct-edge `maturity_labels` gate over blocker state and labels, scoped by `maturity_gate_state_scope`.   |
| R11 depth-2-and-deeper dispatch | Edge-local, depth-agnostic gate plus plan-side depth cap, scoped rollout, and tests.                       |
| R12 external dependencies       | No GitHub reads; labels/comments must mirror maturity into Linear; `DMAT-013` owns team state/label setup. |
| R13 phase-1 maturity scope      | Stack labels reserved and parsed safely without widening eligibility.                                      |
| R14 regression behavior         | One advisory comment per observed maturity regression; worker continues.                                   |
| R15 daemon blockers             | Daemon-state blockers ignored with warnings in maturity gate.                                              |
| R16 divergences and docs        | `docs/symphony-plans/`, late `DIVERGENCES.md`, team-scoped dispatch, and cookbook boundaries.              |
| R17 verification-first          | Verification boundary table and sequencing constraints.                                                    |
| R18 reviewable evidence         | Validation strategy names command/evidence expectations.                                                   |
| R19 recurring-work budget       | Configured daemon dispatch states capped by existing per-state concurrency.                                |

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
