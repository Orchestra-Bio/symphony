# Requirements: Daemon Tickets And Maturity-Gated Dependencies

```yaml
project_code: daemon-maturity
project_color: pink
seed_issue: ABC-231
base_branch: main
integration_branch: symphony/daemon-maturity/integration
human_lead: Jeremy Carroll <jeremy@orchestra.bio>
human_lead_github: jeremycarroll
linear_issue_labels:
  - pink
github_pr_labels:
  - pink
  - symphony
```

## Purpose

This is the canonical requirements source for the `daemon-maturity` project in
the Orchestra fork of `openai/symphony`. `ABC-231` creates this document only.
It does not create a design document, fan-out plan, implementation tickets,
scratch infrastructure, deploy handoff, or implementation changes.

The follow-up design ticket should use this document to produce a design without
making new product-scope judgments. Settled decisions from the handoff documents
are recorded here as requirements or constraints. Open verifications are
requirements for follow-up work, not optional research.

## Source Inputs Read

Primary sources:

- `ABC-231` Linear issue and Linear project
  `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`, read through
  Symphony Linear GraphQL on 2026-07-19.
- Linear project content for `daemon-maturity`, read through Symphony Linear
  GraphQL on 2026-07-19. It provided project metadata, the target repository,
  Google Doc links, the uploaded spec link, and the authorized upload fetch
  command.
- Uploaded spec `A-daemon-tickets.md`, downloaded through the Linear API on
  2026-07-19 with:

  ```sh
  curl -fsSL -H "Authorization: $LINEAR_API_KEY" \
    "https://uploads.linear.app/df362500-0e80-4b5f-b7ea-88d5100656d7/86cd55b7-a87e-4d26-a18a-13c4ffd65b28/0a1485d4-e6ae-4c9e-a494-2575cee9c28c" \
    -o /tmp/abc-231-sources/A-daemon-tickets.uploaded.md
  ```

- Local project spec
  `/Users/jeremy/symphony-rollout/projects/A-daemon-tickets.md`, read on
  2026-07-19. It byte-compares identical to the uploaded spec. SHA-256 for both
  files: `35d41575022a0030af9b73909a325f88f7d2584c0afd054a87ec04714677b0eb`.
- Google Doc `Daemon Tickets - Design Handoff (v2)`, fetched on 2026-07-19
  through the Symphony reader service account with:

  ```sh
  node scripts/fetch-google-doc.mjs 1seRuyDY_SlVHy907aB4G7T-iVsIzfA0V-7vzj9Fedf8
  ```

- Google Doc `Maturity-Gated Dependencies - Design Handoff (v2)`, fetched on
  2026-07-19 through the Symphony reader service account with:

  ```sh
  node scripts/fetch-google-doc.mjs 1uz7ljPlB3ix6hLyO28g0E4fzSYikaP_KwCh1CEEZz8Q
  ```

- Google Doc `Minimal Ticket State Model - Design Handoff (v7)`, fetched on
  2026-07-19 through the Symphony reader service account with:

  ```sh
  node scripts/fetch-google-doc.mjs 12Z34LEXn37p3iOtTk5YfGGMdYPvcmFfUbDSjCVGVQiI
  ```

Local workflow sources:

- `WORKFLOW.md`, read from the local Symphony workspace on 2026-07-19.
- `.codex/skills/symphony-project-factory/SKILL.md`, read from the local
  Symphony workspace on 2026-07-19.
- `.codex/skills/karpathy-guidelines/SKILL.md`, read from the local Symphony
  workspace on 2026-07-19.

Repo placement context:

- `Orchestra-Bio/symphony` target fork, cloned at `main` commit
  `45a53b8588a9650c2f424cb31a6495af1bc86727` on 2026-07-19.
- Target fork `README.md`, existing `docs/*`, and scoped `elixir/AGENTS.md`
  inspected on 2026-07-19.

Source inputs unavailable: none.

## Source Key

- `S1`: Linear issue `ABC-231`.
- `S2`: Linear project content for `daemon-maturity`.
- `S3`: Uploaded/local spec `A-daemon-tickets.md`.
- `S4`: `Daemon Tickets - Design Handoff (v2)`.
- `S5`: `Maturity-Gated Dependencies - Design Handoff (v2)`.
- `S6`: `Minimal Ticket State Model - Design Handoff (v7)`.
- `S7`: Local `WORKFLOW.md`.
- `S8`: Local `.codex/skills/symphony-project-factory/SKILL.md`.
- `S9`: Local `.codex/skills/karpathy-guidelines/SKILL.md`.
- `S10`: Target fork repo context at
  `45a53b8588a9650c2f424cb31a6495af1bc86727`.

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
- Configured project integration branch:
  `symphony/daemon-maturity/integration`. [S1, S2, S7]
- Project metadata labels: Linear label `pink`; GitHub PR labels `pink` and
  `symphony`. [S1, S2]
- Human lead: Jeremy Carroll. [S1, S2]
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

## Accepted Constraints

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
  Durable daemon sleep state must not depend on in-memory timers. [S4, S5, S6]
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

### R3. Daemon Durability And Jitter

Daemon sleep durability lives in the tracker, not in memory. The system must not
use in-memory retry timers for daemon sleeps. Wake precision is polling
granularity plus or minus one minute of jitter, with per-sleep jitter drawn from
`{-60, -30, 0, 30, 60}` seconds and startup staggering for overdue daemons. [S3,
S4, S6]

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
terminal-only behavior. [S3, S5]

### R11. Depth-2-And-Deeper DAG Dispatch

Frontier tickets with no incomplete blockers continue to dispatch as normal PRs
over `main`. Depth-2-and-deeper tickets may dispatch as stacked work when their
direct blockers reach maturity. The rule is edge-local and composes to deeper
DAGs without extra depth-specific logic. [S3, S5]

### R12. Maturity Signal Ownership

The blocker ticket's own coding agent owns adding the maturity label when that
ticket passes first human review, and removing the label to signal regression.
The orchestrator must not read GitHub state for the maturity decision; GitHub
events must be mirrored into Linear labels or comments by agents or bridges.
[S5, S6]

### R13. Per-Ticket Stack Overrides

Parse `stack:*` labels on the dependent ticket. Required labels are
`stack:eager`, `stack:after-review`, and `stack:after-land`.
`stack:after-review` is the default maturity-label behavior. `stack:after-land`
requires terminal blockers. `stack:eager` dispatches as soon as blocker branch
bases exist. Unknown or conflicting stack labels must fall back to the workflow
default and must never become eager. [S3, S5]

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

`DIVERGENCES.md` must record the spec-level changes for daemon states and wake
semantics, the orchestrator dispatch flip and exhaustion park, maturity-gated
dependencies, team-scoped dispatch, hook environment metadata, the
one-orchestrator-per-team invariant, and any final branch-name divergence if
needed. Cookbook material must cover the project sentinel pattern, repo
neutrality, and multi-repo workspaces. [S3, S4, S5]

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

## Open Verifications

| Open verification                                                                                                                                                                      | Why it matters                                                                                                                   | Owner and follow-up                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Current upstream `SPEC.md` facts: state-set defaults, tick sequence, retry formula, restart semantics, hook contract, issue `branch_name`, and upstream TODOs.                         | Daemon and maturity changes must extend current upstream behavior rather than an outdated handoff snapshot.                      | Owner: `daemon-maturity` design/fan-out follow-up under Jeremy Carroll. Follow-up: create a verification ticket before implementation tickets that depend on upstream spec facts.               |
| Daemon wake comment and label fetch mechanics: comment fetch cost, `createdAt` ordering, `wake:*` label visibility, and blocking-relation visibility in the normalized issue model.    | The daemon wake rule depends on comments, labels, and blockers being available cheaply and reliably at poll time.                | Owner: daemon wake verification follow-up under Jeremy Carroll. Follow-up: verify the Linear fetch path before implementing wake eligibility or Linear binding.                                 |
| Maturity gate relation direction and label visibility: blocks versus blocked-by direction, labels on blocked or non-candidate tickets, and label-change visibility in snapshot deltas. | The maturity gate must evaluate the correct blocker edges and detect maturity regression without adding GitHub reads.            | Owner: maturity gate verification follow-up under Jeremy Carroll. Follow-up: verify relation and label mechanics before implementing `maturity_labels`, `stack:*`, or regression prod behavior. |
| Tree-equality CI between fork `main` and the derived rebased branch.                                                                                                                   | The repo strategy depends on fork `main` being merge-maintained while the rebased branch remains a tree-equal adoption artifact. | Owner: repo strategy and CI follow-up under Jeremy Carroll. Follow-up: create the rebased branch contract and CI check before relying on the adoption branch.                                   |

## Project Done Predicate

The `daemon-maturity` project is done only when all of the following are true:

- A project-completion sentinel daemon runs against a real Linear project and
  observably sleeps, wakes, evaluates, and prods when Unhappy. [S3, S4]
- Daemon wake-contract tests pass with synthetic snapshots, a fake clock, seeded
  jitter, and blocked-daemon coverage. [S3, S4, S6]
- Lease and restart-recovery tests pass: kill during sleep re-evaluates on
  schedule after restart, and kill during evaluation re-dispatches the Active
  daemon so the verdict is re-derived. [S3, S4, S6]
- Failure handling proves retry exhaustion parks the daemon back to Unhappy,
  writes an unevaluated sentinel verdict, and avoids hot looping. [S3, S4, S6]
- A depth-2 chain dispatches early when its blocker gains the maturity label,
  and the dependent survives blocker maturity regression without killing the
  worker. [S3, S5]
- Depth-3 synthetic coverage shows edge-local maturity composition. [S3, S5]
- `DIVERGENCES.md` and required cookbook entries are complete. [S3, S4, S5]
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
  and record the selected base branch and validation evidence.

## ABC-231 Done Predicate

This requirements-capture ticket is done when:

- This document is committed in the target fork.
- Markdown formatting has been checked for this document.
- The Linear workpad records source-read evidence, unavailable sources, selected
  document path, assumptions, unresolved questions, and validation evidence.
- No implementation tickets, fan-out payloads, scratch infrastructure, deploy
  handoffs, or implementation changes have been created from this ticket.
