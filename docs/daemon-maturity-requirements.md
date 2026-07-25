# Requirements: Daemon Tickets And Maturity-Gated Dependencies

```yaml
project_code: daemon-maturity
base_branch: main
```

## Purpose

This is the canonical requirements source for the `daemon-maturity` project in
the Orchestra fork of `openai/symphony`. The project adds two dispatch-gate
primitives to the Elixir/OTP Symphony reference implementation: daemon tickets
and maturity-gated dependencies.

`ABC-231` creates this requirements document only. It does not create a design
document, fan-out plan, implementation tickets, scratch infrastructure, deploy
handoff, or implementation changes.

The follow-up design ticket should be able to design from this document without
making new product-scope judgments. Settled decisions from the source handoffs
are recorded here as requirements or constraints. Open verifications are
requirements for follow-up work, not optional research.

The three design handoffs cited below are internal Orchestra documents. Public
readers cannot open those Google Docs; this file is the public record of the
requirements those handoffs settled.

## Source Inputs Read

Primary sources:

- `ABC-231` Linear issue and Linear project
  `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`, read through
  Symphony Linear GraphQL on 2026-07-19 and rechecked on 2026-07-25. Internal
  Orchestra planning source.
- Linear project content for `daemon-maturity`, read through Symphony Linear
  GraphQL. It provided project metadata, the target repository, Google Doc
  links, the uploaded spec link, and the authorized upload fetch command.
  Internal Orchestra planning source.
- Uploaded spec `A-daemon-tickets.md`, downloaded through the Linear API with
  the Symphony worker token and rechecked on 2026-07-25 with:

  ```sh
  curl -fsSL -H "Authorization: ${LINEAR_API_TOKEN:-$LINEAR_API_KEY}" \
    "https://uploads.linear.app/df362500-0e80-4b5f-b7ea-88d5100656d7/86cd55b7-a87e-4d26-a18a-13c4ffd65b28/0a1485d4-e6ae-4c9e-a494-2575cee9c28c" \
    -o /tmp/abc-231-sources-current.BkTowz/A-daemon-tickets.uploaded.md
  ```

- Local project spec
  `/Users/jeremy/symphony-rollout/projects/A-daemon-tickets.md`, read on
  2026-07-19 and rechecked on 2026-07-25. It byte-compares identical to the
  uploaded spec. SHA-256 for both files:
  `35d41575022a0030af9b73909a325f88f7d2584c0afd054a87ec04714677b0eb`.
- Google Doc `Daemon Tickets - Design Handoff (v2)`, fetched through the
  Symphony reader service account from the local Symphony operator workspace
  with:

  ```sh
  node scripts/fetch-google-doc.mjs 1seRuyDY_SlVHy907aB4G7T-iVsIzfA0V-7vzj9Fedf8
  ```

- Google Doc `Maturity-Gated Dependencies - Design Handoff (v2)`, fetched
  through the Symphony reader service account from the local Symphony operator
  workspace with:

  ```sh
  node scripts/fetch-google-doc.mjs 1uz7ljPlB3ix6hLyO28g0E4fzSYikaP_KwCh1CEEZz8Q
  ```

- Google Doc `Minimal Ticket State Model - Design Handoff (v7)`, fetched
  through the Symphony reader service account from the local Symphony operator
  workspace with:

  ```sh
  node scripts/fetch-google-doc.mjs 12Z34LEXn37p3iOtTk5YfGGMdYPvcmFfUbDSjCVGVQiI
  ```

Local workflow and review sources:

- The Symphony operating workflow contract in the local Symphony operator
  checkout at `WORKFLOW.md`, read from the `Orchestra-Bio/orc-app` Symphony
  harness workspace. This is not `elixir/WORKFLOW.md` in this repository; that
  file remains the upstream Elixir example workflow.
- `.codex/skills/symphony-project-factory/SKILL.md`, read from the same local
  operator workspace. It is not part of this repository.
- `.codex/skills/karpathy-guidelines/SKILL.md`, read from the same local
  operator workspace. It is not part of this repository.
- GitHub PR #1 human review and decision comments on 2026-07-25. These comments
  are the human-decision source for landing this document in the fork, shrinking
  phase-1 stack override scope, `max_stack_depth`, and class-based concurrency
  budgets.

Repo context:

- `Orchestra-Bio/symphony` target fork, cloned at `main` commit
  `45a53b8588a9650c2f424cb31a6495af1bc86727` on 2026-07-19 and PR branch
  `6615078c334b769818c0e31915dba73fa45ac963` on 2026-07-25.
- Target fork `README.md`, existing `docs/*`, and scoped `elixir/AGENTS.md`
  inspected for repository context.

Source inputs unavailable to the Symphony worker: none. Some sources above are
internal-only provenance; public readers should treat this file as the
dereferenceable requirements record when they cannot access the underlying
handoffs.

## Source Key

- `S1`: Linear issue `ABC-231`.
- `S2`: Linear project content for `daemon-maturity`.
- `S3`: Uploaded/local spec `A-daemon-tickets.md`.
- `S4`: `Daemon Tickets - Design Handoff (v2)`.
- `S5`: `Maturity-Gated Dependencies - Design Handoff (v2)`.
- `S6`: `Minimal Ticket State Model - Design Handoff (v7)`.
- `S7`: Local Symphony operator workflow contract in
  `Orchestra-Bio/orc-app`, not this repository.
- `S8`: Local Symphony project-factory skill in the operator workspace, not
  this repository.
- `S9`: Local Karpathy guidelines skill in the operator workspace, not this
  repository.
- `S10`: Target fork repo context at
  `45a53b8588a9650c2f424cb31a6495af1bc86727`.
- `S11`: GitHub PR #1 human review and decision comments from 2026-07-25.

## Goal

Add two dispatch-gate primitives to the Orchestra fork of `openai/symphony`:
daemon tickets and maturity-gated dependencies. Both extend dispatch
eligibility beyond upstream's snapshot-only gate while keeping the fork
spec-first, reviewable, and compatible with later upstream adoption discussions.
[S2, S3, S4, S5]

Daemon tickets add the clock: dispatch eligibility becomes `f(snapshot, now)`.
They sleep, wake on timer or prod, evaluate the world idempotently, land in
Happy or Unhappy verdict states, and prod something when Unhappy. [S3, S4, S6]

Maturity-gated dependencies add upstream maturity: blocked depth-2-and-deeper
DAG tickets can dispatch when their direct blockers carry a configured maturity
label, while terminal blockers remain the upstream-compatible case. [S3, S5]

## Baseline Context And Assumptions

- Target repository: `Orchestra-Bio/symphony`, not `orc-app`. [S1, S2, S3]
- Implementation surface: the Elixir/OTP Symphony reference implementation in
  the fork. [S3, S4, S5, S10]
- Selected base branch: `main`. [S1, S2, S7]
- The project-level integration branch is
  `symphony/daemon-maturity/integration`, but this requirements PR remains based
  on `main`. [S1, S2, S7]
- Project metadata labels for workflow routing are Linear label `pink` and
  GitHub PR labels `pink` and `symphony`; those labels are process metadata, not
  product requirements. [S1, S2]
- Human lead for unresolved product decisions: Jeremy Carroll. [S1, S2]
- The handoff documents are settled decisions unless a listed verification
  fails. Design work should not relitigate them. [S1, S3, S4, S5, S6]

## Non-Goals

- Do not implement the orc-app replanning daemon or ceremony daemons. Those
  belong to a later project. [S1, S2, S3, S6]
- Do not create an upstream PR or adoption pitch until adoption discussions are
  real. [S1, S2, S3, S4]
- Do not implement claim-by-assignee or multi-instance dispatch. [S1, S2, S3,
  S4]
- Do not create fan-out payloads, implementation tickets, scratch
  infrastructure, deploy handoffs, or implementation changes from this
  requirements ticket. [S1, S7, S8, S9]
- Do not implement phase-1 per-ticket stack override semantics. The `stack:*`
  vocabulary is deferred to a later enhancement and remains an open question.
  [S5, S11]

## Accepted Constraints

- Source precedence is `S6 > S4 > S3` wherever those sources conflict. In
  particular, S3's `next_wake_at` / `last_evaluated_at` tracker-metadata lease
  scheme is superseded and must not be implemented. [S4, S6, S11]
- Fork `main` is a published artifact and must sync from upstream through true
  merges, never through rebasing. [S3, S4]
- A derived rebased branch may be force-pushed as a read-only artifact, but its
  tree must stay equal to fork `main`; CI must fail loudly on drift. [S3, S4]
- `DIVERGENCES.md` is the adoption interface. It should stay flat and
  spec-level: one paragraph per divergence describing what changed, why, and
  what a compatible implementer must do. [S3, S4, S5]
- Cookbook examples, repo-neutral conventions, sentinel patterns, multi-repo
  workspace guidance, and other non-spec conventions belong outside
  `DIVERGENCES.md`. [S3, S4]
- Linear is a passive datastore and human UI. Bot or workflow bridges, agents,
  and the orchestrator own state transitions and comments. [S6]
- Daemon and maturity behavior must be re-derived from tracker state on poll.
  [S4, S5, S6]
- The maturity gate adds no orchestrator tracker writes; it is a read-only,
  snapshot-derived gate. [S5]
- Normal-ticket dispatch remains upstream-compatible except where explicitly
  widened by the maturity gate. [S4, S5, S6]

## Requirements

### R1. Daemon State Class

Add a configured daemon state class alongside active and terminal states. Under
the minimal state model, the daemon resting states are Happy and Unhappy. A
daemon-state ticket is not dispatched through the normal active-ticket path
until it wakes and is flipped to Active. [S3, S4, S6]

### R2. Daemon Wake Eligibility

A daemon wakes when either its timer is due or it receives a prod. The timer is
computed from the latest verdict comment time, the `wake:*` cadence label, and
jitter. A prod is any comment newer than the latest verdict comment. Wake reason
is advisory only; evaluation must re-read the world at evaluation time. [S3,
S4, S6]

### R3. Daemon Restart Tolerance And Jitter

After an orchestrator restart, a daemon may re-evaluate up to one cadence
interval early or late; this is acceptable and non-catastrophic. The invariant
that must hold is that no daemon is left with neither a computable future wake
time nor an Active state. Wake precision is polling granularity plus or minus
one minute of jitter, with per-sleep jitter drawn from
`{-60, -30, 0, 30, 60}` seconds and startup staggering for overdue daemons. [S4,
S6, S11]

### R4. Daemon Linear Binding

Daemon cadence is represented by a `wake:*` label. Required supported labels are
`wake:15m`, `wake:1h`, `wake:4h`, and `wake:1d`; absent, unknown, or
unparseable cadence labels use the workflow default and must never mean
wake-now. Last evaluation is the `createdAt` of the latest exact
sentinel-headed daemon verdict comment, not comment authorship. [S3, S4, S6]

### R5. Daemon Evaluation Contract

Daemon evaluation must be idempotent and at least once. Multiple prods while
asleep coalesce into one evaluation that reads all pending input. The agent exit
contract must write a sentinel-headed verdict comment and place the daemon in
Happy or Unhappy with a future wake time implied by the verdict time and
cadence. [S3, S4, S6]

### R6. Blocked Daemons

A daemon may carry normal blocking relations and is not wake-eligible while any
blocker is incomplete. This supports plan-created daemons that remain dormant
until frontier work completes. The reverse is forbidden: a daemon must never be
a real blocker for another ticket. [S3, S4, S5, S6]

### R7. Daemon Lease At Dispatch

When a poll decides to wake a daemon, the orchestrator's precondition of
dispatch is the flip to Active. An Active daemon is not wake-eligible; if the
evaluation crashes, normal active-ticket dispatch re-dispatches it and the
idempotent evaluator re-derives the verdict. [S3, S4, S6]

### R8. Daemon Failure Handling

Daemon evaluation failures use normal worker retry and backoff. On retry
exhaustion, the orchestrator must park the daemon back to Unhappy and post an
orchestrator-authored sentinel verdict comment marked unevaluated. This resets
the wake clock to the next interval and prevents hot loops or stranded Active
daemons. [S3, S4, S6]

### R9. Project Completion Sentinel Demo

The flagship daemon demo is a project-completion sentinel: a daemon ticket whose
evaluation queries every ticket in its Linear project via `linear_graphql`,
including terminal tickets. Project completion is true when all daemons are
Happy and all non-daemon tickets are Done or Cancelled. This is a cookbook
pattern, not orchestrator-level project semantics. [S1, S2, S3, S4]

### R10. Maturity-Gated Dependency Gate

Use Linear native blocks and blocked-by relations as the edge source of truth.
A blocked ticket is dispatch-eligible when every direct blocker is terminal or
carries one configured maturity label. The default maturity label set is
`["mature"]`. An empty maturity-label configuration reproduces upstream
terminal-only behavior. Daemon-state blockers are the exception handled by R15.
[S3, S5]

### R11. Depth-2-And-Deeper DAG Dispatch

Frontier tickets with no incomplete blockers continue to dispatch as normal PRs
over `main`. Depth-2-and-deeper tickets may dispatch as stacked work when their
direct blockers reach maturity. The orchestrator gate is edge-local,
depth-agnostic, and composes to deeper DAGs without walking transitive blocker
chains. `max_stack_depth`, default `3`, is a plan-side constraint: the plan that
emits the DAG is responsible for not drawing dependency chains deeper than the
cap because the cap protects human review capacity. A chain beyond the cap is a
plan bug, and the orchestrator must not compensate for it or police it in the
engine. [S3, S5, S11]

### R12. Maturity Signal External Dependency

This project owns the Elixir maturity gate. The plan-side project owns branch
mechanics and the workflow instruction that a blocker's coding agent sets the
maturity label on first human review and removes it to signal regression. Until
this project's Elixir gate ships, the plan-side project runs in degraded serial
mode: dependents wait for terminal blockers, which is correct but slower. The
orchestrator must not read GitHub state for the maturity decision; GitHub events
must be mirrored into Linear labels or comments by agents or bridges. [S5, S6,
S11]

### R13. Phase-1 Maturity Scope

Phase 1 uses the configured maturity-label gate from R10. Per-ticket stack
overrides, including the AI-review versus human-review distinction and any
future `stack:*` vocabulary, are deferred to a later enhancement and must not be
implemented implicitly. Unknown or experimental stack labels must not widen
eligibility before the maturity gate says the ticket is ready. [S5, S11]

### R14. Maturity Regression Behavior

If a blocker loses its maturity label after a dependent has dispatched, the
orchestrator must not kill the dependent's worker. It should prod the dependent
with a comment once per observed transition and let the dependent's agent
decide whether to pause, rework, or continue. If the dependent has not
dispatched, it simply stops being eligible. [S3, S5]

### R15. Daemon Blockers In Maturity Gate

Daemon-state blockers are ignored by the maturity gate with a warning because a
daemon never completes or matures. A dependency edge from a daemon is a plan bug;
daemons express dissatisfaction by prodding normal tickets instead. [S4, S5,
S6]

### R16. Divergences And Documentation

Create `DIVERGENCES.md` early, before the first implementation divergence needs
to land. For this project, the initial divergence list must cover daemon states
and wake semantics, the orchestrator dispatch flip and exhaustion park,
maturity-gated dependency dispatch, and class-based concurrency budgets. The
divergence list should grow only when a requirement or implementation ticket
establishes the behavior; do not pre-document team-scoped dispatch, hook
environment metadata, one-orchestrator-per-team, or `branch_name` behavior from
this requirements ticket alone. Cookbook material must cover the project
sentinel pattern, repo neutrality, and multi-repo workspaces when those
conventions are actually introduced. [S3, S4, S5, S11]

### R17. Verification-First Implementation

The first implementation tickets must verify the open upstream and Linear facts
before relying on them. These verifications are requirements because the
handoffs explicitly depend on tracker and upstream-spec behavior that may have
drifted. [S1, S3, S4, S5, S6]

### R18. Reviewable Evidence

Every implementation checkpoint must leave proof that maps directly to the
accepted requirement it claims: command or environment, target ref, artifact
location, result, known limitations, and next handoff. Local unit tests are not
enough for the project-completion sentinel or tree-equality branch strategy;
those need observable workflow or CI evidence. [S1, S7]

### R19. Class-Based Concurrency Budgets

`max_concurrent_agents` must be budgeted by configured state class. Each
non-implementation class carries an optional ceiling, defaulting to 50% of the
cap rounded down, and an optional floor. Implementation-class work may
consume any slot not held by a class floor. Ceilings are evaluated per tick from
the snapshot alongside the existing priority, `created_at`, and identifier sort,
which continues to order work within a class. The status surface must report
occupancy per class. [S11]

This is engine behavior, not cookbook guidance. It needs a `DIVERGENCES.md`
paragraph. Tests should use deterministic synthetic candidate lists plus a class
map and cap to assert the expected dispatch set. [S11]

## Verification Backlog And Open Questions

### Answered Planning Input

- **Maturity gate evaluation location.** The 2026-07-25 human review identifies
  the candidate fetch in `Linear.Client.fetch_candidate_issues/0`, dispatch
  ordering in `Orchestrator.sort_issues_for_dispatch/1`, config validation, and
  the GraphQL-function injection pattern as the code areas to harvest from the
  related `jeremycarroll/symphony` `codex/deprioritize-ci-polling` branch. Treat
  this as answered planning input for where the gate belongs; implementation
  still needs ordinary current-branch code reading before edits. Owner: design
  follow-up under Jeremy Carroll. Follow-up: carry these file/function targets
  into the design ticket and verify exact current names against `main`. [S11]

### Remaining Verifications

- **Current upstream `SPEC.md` facts.** Verify state-set defaults, tick sequence,
  retry formula, restart semantics, hook contract, issue `branch_name`, and
  upstream TODOs. Owner: `daemon-maturity` design/fan-out follow-up under Jeremy
  Carroll. Follow-up: create a verification ticket before implementation
  tickets that depend on upstream spec facts. [S3, S4]
- **Daemon wake comment and label fetch mechanics.** Verify comment fetch cost,
  `createdAt` ordering, `wake:*` label visibility, and blocking-relation
  visibility in the normalized issue model. Owner: daemon wake verification
  follow-up under Jeremy Carroll. Follow-up: verify the Linear fetch path before
  implementing wake eligibility or Linear binding. [S3, S4, S6]
- **Maturity gate relation direction and label visibility.** Verify blocks
  versus blocked-by direction, labels on blocked or non-candidate tickets, and
  label-change visibility in snapshot deltas. This verification is scoped to
  direct blockers; the plan-side depth cap does not widen it to transitive depth
  visibility. Owner: maturity gate verification follow-up under Jeremy Carroll.
  Follow-up: verify relation and label mechanics before implementing
  `maturity_labels` or regression prod behavior. [S3, S5, S11]
- **Tree-equality CI between fork `main` and the derived rebased branch.** Verify
  that the CI job fails loudly on drift. Owner: repo strategy and CI follow-up
  under Jeremy Carroll. Follow-up: create the rebased branch contract and CI
  check before relying on the adoption branch. [S3, S4]

### Open Product Questions

- **Stack override enhancement.** Decide whether phase-2 per-ticket stack
  overrides should exist, what vocabulary they use, and whether "ready for
  review" means AI review, human review, or another maturity signal. Owner:
  human lead Jeremy Carroll. Follow-up: later enhancement ticket; not phase-1
  scope. [S5, S11]
- **R19 percent or absolute budgets.** Decide whether class budgets are
  configured as percentages of `max_concurrent_agents` or absolute counts. If
  absolute, validation must reject class floors whose sum exceeds the cap.
  Owner: human lead Jeremy Carroll. Follow-up: resolve in the design ticket
  before implementation. [S11]
- **R19 urgent escape hatch.** Decide whether urgent recurring work can exceed a
  class ceiling. Recommendation from the human review is not to add the escape
  hatch unless a real case appears. Owner: human lead Jeremy Carroll. Follow-up:
  resolve in the design ticket before implementation. [S11]
- **R19 sequencing.** Decide whether class-based budgets ship with daemon work
  or earlier. If GitHub-to-Linear bridges remove CI-polling occupancy first, the
  permanent motivation is daemon recurrence rather than CI polling. Owner: human
  lead Jeremy Carroll. Follow-up: resolve ordering in project planning; R19
  remains in project scope. [S11]

## Project Done Predicate

The `daemon-maturity` project is done only when all of the following are true:

- A project-completion sentinel daemon runs against a real Linear project and
  observably sleeps, wakes, evaluates, and prods when Unhappy. [S3, S4]
- Daemon wake-contract tests pass with synthetic snapshots, a fake clock, seeded
  jitter, and blocked-daemon coverage. [S3, S4, S6]
- Daemon Linear-binding tests prove absent, unknown, or unparseable `wake:*`
  cadence labels never mean wake-now. [S3, S4, S6, S11]
- Lease and restart-recovery tests pass: kill during sleep re-evaluates within
  the accepted restart tolerance, and kill during evaluation re-dispatches the
  Active daemon so the verdict is re-derived. [S4, S6, S11]
- Failure handling proves retry exhaustion parks the daemon back to Unhappy,
  writes an unevaluated sentinel verdict, and avoids hot looping. [S3, S4, S6]
- A depth-2 chain dispatches early when its blocker gains the maturity label,
  and the dependent survives blocker maturity regression without killing the
  worker. [S3, S5]
- Depth-3 synthetic coverage shows edge-local maturity composition within the
  orchestrator gate, without transitive depth checks. [S3, S5, S11]
- Phase-1 maturity-gate tests prove unknown or experimental stack labels do not
  make a dependent eligible before the maturity gate is satisfied. [S5, S11]
- Class-based concurrency budget tests prove recurring classes cannot occupy
  the whole dispatch pool while implementation work is eligible. [S11]
- `DIVERGENCES.md` exists before the first implementation divergence lands and
  contains the divergence paragraphs required by completed implementation work.
  [S3, S4, S5, S11]
- The derived rebased branch has CI evidence showing tree equality with fork
  `main`. [S3, S4]

## Evidence Required For Follow-Up Work

- Requirements and design artifacts must cite the source IDs in this document
  or explicitly mark a human decision or open verification.
- Verification tickets must record exact commands, target refs, observed data,
  and pass/fail results for the open verifications above.
- Implementation tickets must include targeted Elixir tests for the changed gate
  behavior and failure/restart semantics they touch.
- Demo or workflow tickets must include Linear project evidence for the sentinel
  daemon and depth-2 maturity dispatch. If real Linear evidence is blocked,
  record the blocker and the exact handoff needed.
- PRs must be opened against `main`, carry GitHub labels `pink` and `symphony`,
  and record the selected base branch and validation evidence. [S1, S2, S7]

## ABC-231 Done Predicate

This requirements-capture ticket is done when:

- This document is committed in the target fork.
- Markdown formatting has been checked for this document.
- The Linear workpad records source-read evidence, unavailable sources, selected
  document path, assumptions, unresolved questions, and validation evidence.
- No implementation tickets, fan-out payloads, scratch infrastructure, deploy
  handoffs, or implementation changes have been created from this ticket.
