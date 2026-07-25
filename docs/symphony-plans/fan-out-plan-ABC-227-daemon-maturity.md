# Fan-Out Plan: Daemon Tickets And Maturity-Gated Dependencies

```yaml
project_code: daemon-maturity
project_color: pink
seed_issue: ABC-227
target_project: Daemon Tickets + Maturity-Gated Dependencies (symphony fork)
target_repo: https://github.com/Orchestra-Bio/symphony.git
base_branch: main
integration_branch: symphony/daemon-maturity/integration
human_lead: Jeremy Carroll
human_lead_github: jeremycarroll
linear_issue_labels:
  - pink
github_pr_labels:
  - pink
  - symphony
```

## Goal

Create reviewable verification and implementation ticket payloads for the
`daemon-maturity` project in the Orchestra fork of `openai/symphony`. The
project adds two dispatch-gate primitives to the Elixir/OTP implementation:

- daemon tickets that sleep in configured daemon states, wake by timer only,
  lease by flipping to a dedicated daemon dispatch state, evaluate
  idempotently, and record Happy/Unhappy verdicts in titled workpad comments;
- maturity-gated dependencies that let blocked tickets dispatch when every
  direct blocker is terminal or carries a configured maturity label, while
  preserving terminal-only behavior when `maturity_labels` is empty.

This plan does not implement daemon or maturity behavior and does not create
implementation tickets. It is the reviewable fan-out source and dry-run payload
shape for a later trigger/fan-out step.

## Source Inputs Read

Authoritative project sources:

- Linear issue `ABC-227`, including the 2026-07-25 Rework direction, state,
  labels, comments, PR attachments, project metadata, blocker relations, and
  workpad expectations.
- Linear project
  `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`, including
  metadata, target repository, required labels, Google Doc links, uploaded spec
  fetch command, and color helper output.
- `docs/symphony-plans/daemon-maturity-requirements.md` on `main` in
  `Orchestra-Bio/symphony` at `37aea82ec23d8786b5e415f3f0a191bbd28a0f5f`.
- `docs/symphony-plans/daemon-maturity-design.md` on `main` in
  `Orchestra-Bio/symphony` at `37aea82ec23d8786b5e415f3f0a191bbd28a0f5f`.
- Human decision comments on `Orchestra-Bio/symphony` PR #1 and PR #2,
  including `S11`, `S12`, and `D9` as cited by the merged requirements and
  design. These comments are the decision source wherever the 2026-07-19
  handoffs conflict.

Background sources read, superseded where they conflict with the merged
requirements/design:

- Uploaded spec `A-daemon-tickets.md`, fetched through Linear with:
  `curl -fsSL -H "Authorization: ${LINEAR_API_TOKEN:-$LINEAR_API_KEY}" <uploads.linear.app path>`.
- Local project spec
  `/Users/jeremy/symphony-rollout/projects/A-daemon-tickets.md`.
- Google Doc `Daemon Tickets - Design Handoff (v2)`, fetched with
  `node scripts/fetch-google-doc.mjs 1seRuyDY_SlVHy907aB4G7T-iVsIzfA0V-7vzj9Fedf8`.
- Google Doc `Maturity-Gated Dependencies - Design Handoff (v2)`, fetched with
  `node scripts/fetch-google-doc.mjs 1uz7ljPlB3ix6hLyO28g0E4fzSYikaP_KwCh1CEEZz8Q`.
- Google Doc `Minimal Ticket State Model - Design Handoff (v7)`, fetched with
  `node scripts/fetch-google-doc.mjs 12Z34LEXn37p3iOtTk5YfGGMdYPvcmFfUbDSjCVGVQiI`.
- `/Users/jeremy/symphony-rollout/handoff-supersessions.md`, read as a
  convenience index of superseded handoff content.

Generic workflow and planning sources:

- `WORKFLOW.md` from the local Symphony operator workspace.
- `.codex/skills/karpathy-guidelines/SKILL.md`.
- `.codex/skills/symphony-project-factory/SKILL.md`.
- `.codex/skills/symphony-google-docs/SKILL.md`.
- `.codex/skills/symphony-linear-api/SKILL.md`.
- `docs/symphony-plans/fan-out-plan-schema.md` from the operator workspace.
- `docs/symphony-plans/fan-out-criteria.md` from the operator workspace.
- Prior `orc-app` plan
  `docs/symphony-plans/fan-out-plan-ABC-227-daemon-maturity.md`, read only for
  payload field structure and verification-before-implementation ordering.

Target repository context inspected:

- `SPEC.md`
- `.github/pull_request_template.md`
- `.github/workflows/make-all.yml`
- `.github/workflows/pr-description-lint.yml`
- `elixir/AGENTS.md`
- `elixir/README.md`
- `elixir/WORKFLOW.md`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- `elixir/lib/symphony_elixir/linear/adapter.ex`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/tracker.ex`
- `elixir/lib/symphony_elixir/tracker/memory.ex`
- representative tests under `elixir/test/symphony_elixir/`

Unavailable sources: none.

## Baseline Context

- Planning artifact repository: `Orchestra-Bio/symphony`.
- Planning branch base: `main`.
- Planning baseline `HEAD`: `37aea82ec23d8786b5e415f3f0a191bbd28a0f5f`.
- Target implementation repository: `Orchestra-Bio/symphony`.
- Project integration branch
  `symphony/daemon-maturity/integration` exists at
  `28e21f61bc24631e8dc1668c102a5cefd67bb97f` and is tree-equal to `main` at
  planning time.
- No open PR existed in `Orchestra-Bio/symphony` for branch
  `symphony/daemon-maturity/ABC-227/plan-project` at planning time.
- Prior `orc-app` plan PRs #3787 and #3866 are closed and not reused.
- Required GitHub PR labels `pink` and `symphony` exist in
  `Orchestra-Bio/symphony`.

## Confirmed Scope Decisions

- Work targets the Orchestra fork of `openai/symphony`, not `orc-app`.
- The merged requirements/design in `docs/symphony-plans/` are authoritative;
  the 2026-07-19 handoffs and uploaded spec are background only where they
  conflict with `S11`, `S12`, or `D9`.
- `DIVERGENCES.md` is created early, before the first implementation divergence
  lands. Cookbook material remains outside `DIVERGENCES.md`.
- The tracker config surface for this phase is
  `daemon_states`, `daemon_dispatch_state`, `daemon_default_wake`, and
  `maturity_labels`. Do not add `daemon_label` or class-budget config.
- Recurring-work budget is satisfied by the existing
  `agent.max_concurrent_agents_by_state` cap on the daemon dispatch state.
  Ceilings only; no floors.
- A daemon wakes by timer only. Comments never cause daemon wake eligibility.
  Urgency is a state write to `daemon_dispatch_state`.
- The wake anchor is the later `updatedAt` of the daemon's own titled workpad
  comment and the orchestrator's own titled workpad comment. `Comment.updatedAt`
  exists and advances on edit; do not reopen that platform verification.
- The engine currently has `SymphonyElixir.Linear.Adapter.create_comment/2`, no
  `commentUpdate`, and no comment read path in the poll query.
- Daemon lease-at-dispatch is the orchestrator flipping the ticket to
  `daemon_dispatch_state`, not `Active`.
- Daemon retry exhaustion parks the daemon by editing the orchestrator's own
  titled comment with an unevaluated verdict; a later real daemon verdict
  supersedes the park.
- The maturity gate is scoped to direct Linear blocker relations. It does not
  walk transitive depth, and `max_stack_depth` remains a plan-side cap.
- The maturity gate result should be named `{:gated, blockers}` or equivalent.
  Do not reuse `blocked`, which already means agent-reported blocked state in
  `Orchestrator.State.blocked`.
- The hardcoded `Todo`-only terminal blocker helper must be replaced at both
  `should_dispatch_issue?/4` and `retry_candidate_issue?/2`, sharing one gate
  implementation.
- Blocker maturity regression creates one advisory comment per observed
  transition and never kills the worker.
- Daemon-state blockers in the maturity gate are ignored with a warning because
  a daemon never completes or matures.

## Out Of Phase 1

Do not fan out implementation work for:

- `stack:*` per-ticket overrides. This is deferred; the open question is
  whether the maturity point means AI review, human review, or another signal.
- Class-based concurrency budgets. The recurring-work budget is satisfied by
  `agent.max_concurrent_agents_by_state` on the daemon dispatch state.
- Engine-side `max_stack_depth` enforcement. Default depth `3` is a plan-side
  constraint; the gate stays depth-agnostic.
- Team-scoped dispatch, hook environment metadata, one-orchestrator-per-team,
  and `branch_name` behavior. These are not established by the phase-1
  requirements and should not be pre-documented.
- Check-back-later one-shot timed waits for non-daemon tickets. Phase 1 keeps
  extension points open without implementing the feature.
- Writer-side comment upsert protocol and orphan cleanup. Those are external
  workflow/agent conventions; this fork consumes the titled-comment contract
  and degrades safely when it is broken.

## Dependency Semantics

All generated task PRs should target `main` by default and carry GitHub labels
`pink` and `symphony`. Linear issues should carry label `pink` and should be
assigned to Jeremy Carroll when Linear identity resolution is available.

Fan-out dependencies below are sequencing guidance, not Linear blocker
relations, unless a human explicitly requests blocker links after reviewing
this plan. For this integration-branch project, a dependency is satisfied when
the upstream issue is project-integrated into
`symphony/daemon-maturity/integration` with validation evidence recorded.

The first fan-out batch is verification and docs runway:

- `DMAT-001`, `DMAT-002`, `DMAT-003`, and `DMAT-004` start in `Todo`.
- `DMAT-005` starts in `Backlog` but should move before any behavior-divergence
  implementation leaves `Backlog`, because it creates the early
  `DIVERGENCES.md` runway.
- Implementation and demo tickets start in `Backlog` and should not be moved to
  `Todo` until the required verification tickets are project-integrated or a
  human explicitly accepts a narrower risk.

No generated ticket should create additional Linear `blockedBy` or `blocks`
relations from this plan. The only dependency semantics carried forward are the
typed dependency entries in each ticket description.

## Global Guardrails

- Generated tickets must read this plan plus the merged requirements/design
  before editing target repository files.
- Generated tickets must work in `Orchestra-Bio/symphony`, not `orc-app`.
- Follow `elixir/AGENTS.md` for Elixir implementation work: public `def`
  functions in `lib/` need adjacent `@spec`; prefer targeted tests while
  iterating and `make -C elixir all` before handoff unless blocked.
- Do not edit `SPEC.md` for fork divergences unless a verification ticket
  proves a source conflict and a human accepts the change. Fork behavior belongs
  in `DIVERGENCES.md`.
- Do not pre-document conventions that have not landed. `DIVERGENCES.md` grows
  as behavior lands; cookbook docs grow as operator conventions exist.
- Record isolated validation on each clean task branch and composed validation
  after merging into `symphony/daemon-maturity/integration`.
- If a ticket introduces a project-scoped TODO, stub, adapter, disabled path,
  compatibility export, or temporary flag, it must record the temporary seam in
  its issue and PR body before handoff.

## Fan-Out Items

### DMAT-001 - Verify Daemon Comment, Label, And Relation Fetch

ticket_title: Verify daemon comment metadata, wake-label, and blocker fetch mechanics

initial_status: Todo

difficulty: hard

ownership: Symphony verification agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Verify the daemon wake rule's required Linear data path before any daemon
implementation relies on it. Confirm the normalized comment metadata shape for
`id`, `createdAt`, and `updatedAt`; the narrow body fetch needed to identify a
titled workpad comment when an unrecognized comment id appears; `wake:*` label
visibility; blocking-relation visibility for blocked daemon dormancy; and
schema availability for `commentUpdate`. Do not re-open the already-verified
platform fact that `Comment.updatedAt` exists and advances on edit.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/linear/adapter.ex`
- `elixir/test/symphony_elixir/extensions_test.exs`

owned_files:

- `docs/symphony-plans/daemon-maturity-daemon-linear-verification.md`

source_notes:

- Requirements R2, R4, R5, R6, R7, R8, and R17.
- Design sections for titled workpad comments, the wake function,
  lease-at-dispatch, failure handling, and verification boundaries.
- PR #2 decision `D9`: comments never wake daemons; comment bodies are fetched
  only on the narrow writer-identification path.

owned_external_resources:

- Optional disposable Linear issue(s) in a throwaway project, only if needed to
  prove real GraphQL field shape and mutation availability.

dependencies: none

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Inspect the current Linear GraphQL query and adapter code to record that the
  engine has `create_comment/2`, no `commentUpdate`, and no comment read path.
- Verify or fixture the smallest comment metadata selection containing
  `id`, `createdAt`, and `updatedAt`.
- Verify the narrow query for fetching a comment body by id when a new comment
  id must be matched to a titled workpad heading.
- Verify `wake:15m`, `wake:1h`, `wake:4h`, and `wake:1d` label visibility in
  normalized issue data.
- Verify blocker relation visibility needed for daemon sleeps to stay dormant
  until normal blockers complete.
- Verify `commentUpdate` mutation spelling and response shape through Linear
  schema introspection or a safe fixture; do not mutate production comments
  unless a human approves the target.

acceptance_checks:

- The verification doc records exact GraphQL selections, fixture or live target,
  observed response shape, query/mutation cost notes, and pass/fail result for
  each required field.
- The doc explicitly says `Comment.updatedAt` was treated as already verified
  and not retested.
- Any missing field, expensive query shape, or mutation unavailability is
  recorded as an `Input Needed` blocker before daemon implementation leaves
  `Backlog`.
- Targeted validation includes Markdown formatting for the verification doc.

split_criteria:

- raw-note-verification
- external-system-boundary
- validation-surface

exclusions:

- Do not implement daemon wake eligibility.
- Do not change orchestrator dispatch.
- Do not create daemon comments or update production comments without explicit
  human approval.

### DMAT-002 - Verify Current SPEC And Retry Boundary Facts

ticket_title: Verify current SPEC.md and retry-exhaustion facts

initial_status: Todo

difficulty: hard

ownership: Symphony verification agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Verify current upstream `SPEC.md` and Elixir implementation facts before
daemon or maturity implementation relies on them. This includes state-set
defaults, tick sequence, retry formula, restart semantics, hook contract, issue
`branch_name`, upstream TODOs, and how a finite daemon retry-exhaustion boundary
can compose with the existing delay-capped retry path.

source_files:

- `SPEC.md`
- `elixir/AGENTS.md`
- `elixir/README.md`
- `elixir/WORKFLOW.md`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/agent_runner.ex`
- `elixir/lib/symphony_elixir/workspace.ex`

owned_files:

- `docs/symphony-plans/daemon-maturity-upstream-spec-verification.md`

source_notes:

- Requirements R3, R7, R8, R17, and R18.
- Design `Current Implementation Anchors`, `Failure Handling`, and
  `Verification Boundaries`.
- PR #2 `D9`: current retry path is delay-capped, not attempt-capped; a finite
  daemon exhaustion boundary is required before parking.

dependencies: none

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Compare the requirements/design's upstream-model claims with current
  `SPEC.md` and Elixir implementation.
- Verify active and terminal state defaults, lowercase comparison behavior,
  poll tick order, candidate fetch behavior, blocker gate location, retry and
  backoff behavior, restart recovery behavior, hook input contract,
  branch-name model, and tracker-write TODO status.
- Trace `schedule_issue_retry/4`, retry timer handling, and active retry
  re-selection to identify where daemon retry exhaustion can be counted without
  replacing the existing delay-capped retry path.
- Record each fact as `confirmed`, `drifted`, or `unclear`.

acceptance_checks:

- The verification doc has one row per relied-on upstream fact and explicitly
  states whether daemon/maturity planning may rely on it.
- The retry section states the intended finite boundary, current call sites,
  and any risks for hot-loop prevention or stale retry entries.
- Any drift that would change daemon or maturity design is recorded as a
  blocker rather than patched speculatively.
- Targeted validation includes Markdown formatting for the verification doc.

split_criteria:

- raw-note-verification
- historical-vs-current
- validation-surface

exclusions:

- Do not edit `SPEC.md`.
- Do not implement daemon or maturity behavior.
- Do not add retry-attempt config or parking behavior in this ticket.

### DMAT-003 - Add Fork/Rebased Tree-Equality CI

ticket_title: Add tree-equality CI for fork main and derived rebased branch

initial_status: Todo

difficulty: hard

ownership: Symphony workflow agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Add or verify CI that fails loudly when the merge-maintained fork `main`
tree and the derived rebased branch tree diverge. Document the branch operating
contract and any human-owned branch naming input that remains unresolved.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `.github/workflows/make-all.yml`
- `.github/workflows/pr-description-lint.yml`
- `.github/pull_request_template.md`
- `README.md`

owned_files:

- `.github/workflows/tree-equality.yml`
- `docs/symphony-plans/daemon-maturity-tree-equality-ci.md`

source_notes:

- Requirements R16, R17, and project done predicate.
- Design `Documentation And Repository Strategy` and `Verification Boundaries`.
- Daemon handoff repository strategy, superseded only where merged docs say so.

dependencies: none

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Confirm the exact derived rebased branch name or record a human-owned
  unresolved branch-name question. Do not invent the name.
- Add a read-only GitHub Actions workflow that compares fork `main` to the
  confirmed derived rebased branch and fails when tree diff is non-empty.
- Keep the workflow limited to comparison; do not add automatic rebasing,
  force-push, or upstream PR creation.
- Document how the branch is maintained and what a failing equality check means.

acceptance_checks:

- Workflow syntax is reviewable and references only confirmed branch names, or
  the ticket stops with an explicit branch-name blocker before adding CI.
- Local validation uses available static/workflow checks where possible. If
  live GitHub Actions evidence requires a pushed branch, the PR and workpad name
  that limitation.
- The docs file states that fork `main` uses true upstream merges and the
  derived rebased branch is a read-only artifact.

split_criteria:

- workflow-boundary
- validation-surface
- raw-note-verification

exclusions:

- Do not implement daemon or maturity behavior.
- Do not force-push, create, or rewrite the derived branch unless a human
  explicitly approves it.
- Do not open an upstream PR.

### DMAT-004 - Verify Maturity, Label, And State Mechanics

ticket_title: Verify maturity relation, label, and custom state mechanics

initial_status: Todo

difficulty: hard

ownership: Symphony verification agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Verify the Linear mechanics that maturity and daemon dispatch depend on:
native blocker relation direction, labels on direct blockers, label-change
visibility in refreshed snapshots, custom Linear state setup, and the daemon
dispatch state's required `Started`-type behavior. Relation verification is
scoped to direct blockers only; `max_stack_depth` is plan-side and must not
widen this ticket into transitive-depth visibility.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/test/symphony_elixir/workspace_and_config_test.exs`

owned_files:

- `docs/symphony-plans/daemon-maturity-linear-mechanics-verification.md`

source_notes:

- Requirements R1, R10, R11, R12, R14, R15, and R17.
- Design `State Classes And Identity`, `Blocker Snapshot Shape`,
  `Gate Function`, `Plan-Side Obligations`, and `Verification Boundaries`.
- PR #2 `D9`: daemon dispatch state is a deliberate eighth state and must be a
  `Started`-type state.

owned_external_resources:

- Optional disposable Linear issue chain with blocker relations, maturity
  labels, and custom states, only if needed to prove real GraphQL mechanics.

dependencies: none

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Verify Linear `blocks` versus `blockedBy` direction for the query shape the
  fork uses.
- Verify that direct blocker labels are visible for blocked and non-candidate
  tickets.
- Verify whether label removals can be detected from current refreshed
  snapshots for one-time regression advisory comments.
- Verify custom state category requirements for `Happy`, `Unhappy`, and the
  daemon dispatch state, including that the dispatch state can be configured as
  a `Started`-type state.
- Record whether current team state setup exists, or list exact missing state
  setup without inventing fallback names.

acceptance_checks:

- The verification doc states whether each maturity and state setup requirement
  is satisfied, drifted, or blocked.
- The doc explicitly states that only direct blocker visibility was verified
  and that transitive depth remains out of engine scope.
- Any schema, label, state-category, or visibility gap that changes the design
  is recorded as an `Input Needed` blocker before implementation tickets move
  out of `Backlog`.
- Targeted validation includes Markdown formatting for the verification doc.

split_criteria:

- raw-note-verification
- external-system-boundary
- validation-surface

exclusions:

- Do not implement `maturity_labels`.
- Do not add stack override parsing.
- Do not migrate Linear team states.
- Do not change the existing blocker gate.

### DMAT-005 - Create Divergence And Documentation Runway

ticket_title: Create early DIVERGENCES.md runway for daemon maturity

initial_status: Backlog

difficulty: easy

ownership: Symphony documentation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Create the early documentation runway required before behavior
divergences land. This ticket creates `DIVERGENCES.md` with a compact
project-owned structure and either placeholder headings or initial paragraphs
only for behavior already established by merged requirements/design. It does
not document out-of-phase behavior or cookbook conventions before they exist.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `SPEC.md`
- `README.md`

owned_files:

- `DIVERGENCES.md`
- `docs/symphony-plans/daemon-maturity-documentation-runway.md`

source_notes:

- Requirements R16 and R18.
- Design `Documentation And Repository Strategy`.
- PR #1 and PR #2 decisions limiting what should and should not be
  pre-documented.

dependencies:

- item: DMAT-002
  type: integration
  requires: upstream SPEC verification is project-integrated or explicitly
  blocked with a human-owned decision
  reason: divergence text should compare against confirmed upstream behavior,
  not stale assumptions.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Create root `DIVERGENCES.md` before implementation tickets introduce behavior
  divergences.
- Include only daemon/maturity divergence areas established by the merged
  requirements/design: daemon states and timer-only wake semantics, the daemon
  dispatch state and per-state budget, the daemon lease flip and exhaustion
  park, maturity-gated dependency dispatch, and the hardcoded `Todo` blocker
  gate replacement.
- Keep team-scoped dispatch, hook environment metadata,
  one-orchestrator-per-team, and `branch_name` behavior out of the doc until a
  requirement or implementation ticket establishes them.
- Add a small runway note explaining where future cookbook docs should live.

acceptance_checks:

- `DIVERGENCES.md` exists before behavior-divergence implementation starts.
- The file contains no implementation TODOs, no unverified claims, no class
  budget config, no `daemon_label`, and no out-of-phase items.
- Targeted validation includes Markdown formatting for owned docs.

split_criteria:

- audience-conflict
- historical-vs-current
- workflow-boundary

exclusions:

- Do not implement daemon or maturity behavior.
- Do not edit `SPEC.md`.
- Do not create cookbook docs for conventions that have not landed.

### DMAT-006 - Add Config And Normalized Model Runway

ticket_title: Add daemon and maturity config plus normalized data runway

initial_status: Backlog

difficulty: hard

ownership: Symphony implementation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Add the shared configuration and normalized data-model fields that
daemon wake and maturity helpers will consume. This ticket establishes typed
contracts only; it does not change dispatch eligibility, tracker writes, or
Linear fetch breadth.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/test/support/test_support.exs`
- `elixir/test/symphony_elixir/workspace_and_config_test.exs`

owned_files:

- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/test/symphony_elixir/daemon_maturity_config_test.exs`
- `elixir/test/symphony_elixir/daemon_maturity_issue_test.exs`

source_notes:

- Requirements R1, R4, R10, and R19.
- Design sections for config, state taxonomy, recurring-work budget, and
  blocker snapshot shape.
- This item owns the four tracker config fields named in the requirements:
  `daemon_states`, `daemon_dispatch_state`, `daemon_default_wake`, and
  `maturity_labels`.

dependencies:

- item: DMAT-001
  type: integration
  requires: daemon Linear fetch verification is project-integrated or blocked
  with an accepted fallback
  reason: model fields should match data Linear can provide.
- item: DMAT-002
  type: integration
  requires: SPEC/retry verification is project-integrated or human-accepted
  drift is recorded
  reason: config additions must stay compatible with the upstream config
  contract.
- item: DMAT-004
  type: integration
  requires: maturity and custom-state mechanics verification is
  project-integrated or blocked with accepted fallback
  reason: daemon dispatch-state and blocker-label fields should match verified
  Linear mechanics.
- item: DMAT-005
  type: integration
  requires: early `DIVERGENCES.md` runway is project-integrated
  reason: config behavior is a fork divergence and should not land before the
  divergence record exists.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Add typed config fields for `tracker.daemon_states`,
  `tracker.daemon_dispatch_state`, `tracker.daemon_default_wake`, and
  `tracker.maturity_labels` using existing schema patterns.
- Add helper accessors through `SymphonyElixir.Config` instead of ad-hoc env
  reads.
- Validate disjointness between daemon states, daemon dispatch state, active
  states, and terminal states according to the design.
- Preserve existing defaults when new config is absent; daemon/maturity
  behavior must be inert unless configured data makes it applicable.
- Extend `SymphonyElixir.Linear.Issue` or supporting structs for normalized
  blocker labels and comment metadata consumed by later helpers.
- Use existing `agent.max_concurrent_agents_by_state` for daemon budget
  examples; do not add class-budget config.

acceptance_checks:

- Tests prove workflows that omit daemon/maturity fields retain existing
  behavior.
- Tests prove daemon states, daemon dispatch state, maturity labels, and default
  wake values are normalized and validated.
- Tests prove no `daemon_label` or class-budget config is accepted.
- Targeted validation includes new tests and `make -C elixir specs.check`.

split_criteria:

- typed-seam-contract
- integration-validation-dependency
- validation-surface

exclusions:

- Do not edit `elixir/lib/symphony_elixir/linear/client.ex`; fetch shape is
  owned by `DMAT-008`.
- Do not edit `elixir/lib/symphony_elixir/orchestrator.ex`; dispatch wiring is
  owned by `DMAT-009` and `DMAT-010`.
- Do not implement wake calculations or maturity gate decisions.
- Do not add `daemon_label`, `daemon_max_concurrent_agents_by_class`, or any
  class-budget fields.

### DMAT-007 - Implement Timer-Only Daemon Wake Engine

ticket_title: Implement timer-only daemon wake engine with fake-clock tests

initial_status: Backlog

difficulty: hard

ownership: Symphony implementation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Implement a pure helper that decides daemon wake eligibility from a
normalized issue snapshot, explicit time input, and daemon config. The helper
owns timer calculation, wake-label parsing, titled workpad anchors,
deterministic jitter, and blocked-daemon dormancy. It does not perform Linear
reads, inspect GitHub, mutate tracker state, or treat comments as wakes.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/test/symphony_elixir/daemon_maturity_issue_test.exs`

owned_files:

- `elixir/lib/symphony_elixir/daemon_wake.ex`
- `elixir/test/symphony_elixir/daemon_wake_test.exs`

source_notes:

- Requirements R2, R3, R4, R5, R6, and R7.
- Design `Wake Function`, `Jitter`, and `Check-Back-Later Extension Point`.
- PR #2 `D9`: delete comment-prodding from the wake rule.

dependencies:

- item: DMAT-001
  type: integration
  requires: daemon Linear fetch verification is project-integrated
  reason: the pure API should consume the verified comment metadata shape.
- item: DMAT-006
  type: integration
  requires: config and normalized model runway is project-integrated
  reason: the wake engine should consume shared contracts rather than define
  duplicate fields.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Add `SymphonyElixir.DaemonWake` or an equivalent small module with a pure API
  accepting issue data, daemon config, `now`, and injectable jitter.
- Support `wake:15m`, `wake:1h`, `wake:4h`, and `wake:1d`; absent, unknown, or
  conflicting wake labels use `daemon_default_wake` and never wake-now.
- Resolve the wake anchor from the later `updatedAt` of daemon and orchestrator
  titled workpad comments, or issue `created_at` with warning when no comment
  exists.
- Apply deterministic per-sleep jitter from `{-60, -30, 0, 30, 60}` seconds
  based on durable inputs.
- Return `{:gated, blockers}` or an equivalent non-wake result for daemons with
  incomplete normal blockers.
- Preserve extension points for future one-shot timed waits without
  implementing them.

acceptance_checks:

- Unit tests cover timer due, timer sleep, missing comment fallback, conflicting
  wake labels, deterministic jitter, duplicate titled comments, blocked
  daemons, startup overdue staggering hooks, and no wake from comments.
- Tests prove `issue.updatedAt` is never used as a sleep anchor.
- No Linear API, tracker write, or orchestrator dispatch changes are made in
  this ticket.
- Targeted validation includes
  `make -C elixir test TEST=test/symphony_elixir/daemon_wake_test.exs`.

split_criteria:

- typed-seam-contract
- validation-surface
- integration-validation-dependency

exclusions:

- Do not fetch comments from Linear.
- Do not flip issues to the daemon dispatch state.
- Do not implement failure parking.
- Do not implement maturity-gated dependencies.

### DMAT-008 - Add Linear Comment Read And Update Binding

ticket_title: Add Linear comment read and commentUpdate support for daemon workpads

initial_status: Backlog

difficulty: hard

ownership: Symphony implementation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Extend the Linear client, tracker boundary, and normalization layer so
daemon sleep candidates can supply comment metadata and titled-workpad identity
to the wake engine, and so daemon/orchestrator workpads can be edited in place.
This ticket owns Linear query and mutation plumbing only.

source_files:

- `docs/symphony-plans/daemon-maturity-daemon-linear-verification.md`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/adapter.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/tracker.ex`
- `elixir/lib/symphony_elixir/tracker/memory.ex`
- `elixir/test/symphony_elixir/extensions_test.exs`

owned_files:

- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/adapter.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/tracker.ex`
- `elixir/lib/symphony_elixir/tracker/memory.ex`
- `elixir/test/symphony_elixir/linear_client_daemon_comments_test.exs`
- `elixir/test/symphony_elixir/linear_adapter_comment_update_test.exs`

source_notes:

- Requirements R4, R5, R8, and R17.
- Design sections for titled workpad comments, durable wake fields, agent exit
  contract, and failure handling.
- PR #2 `D9`: the engine has never read comments; `commentUpdate` is a new
  requirement.

dependencies:

- item: DMAT-001
  type: integration
  requires: daemon Linear fetch verification is project-integrated
  reason: query and mutation shapes should match verified Linear API behavior.
- item: DMAT-006
  type: integration
  requires: config and normalized model runway is project-integrated
  reason: Linear normalization should populate shared fields.
- item: DMAT-007
  type: integration
  requires: timer-only wake engine API is project-integrated
  reason: binding tests should exercise the downstream shape consumed by the
  wake engine.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Add bounded comment metadata reads for daemon sleep candidates: `id`,
  `createdAt`, and `updatedAt`.
- Add a narrow body-fetch path for newly seen comment ids so a leading heading
  line can be matched to the writer title.
- Add `commentUpdate` support beside existing `create_comment/2`, with memory
  tracker behavior suitable for tests.
- Populate normalized issue/comment fields expected by `DMAT-007`.
- Keep steady-state polling from fetching large comment bodies.

acceptance_checks:

- Fixture tests prove comment metadata, narrow body fetch, and blocker/wake
  labels reach normalized issue data in the expected shape.
- Adapter tests prove `commentUpdate` success and failure handling without
  regressing existing `commentCreate` behavior.
- Existing candidate fetch and tracker boundary tests continue to pass.
- Targeted validation includes the new Linear client/adapter tests and
  `make -C elixir specs.check`.

split_criteria:

- external-system-boundary
- typed-seam-contract
- validation-surface

exclusions:

- Do not change `SymphonyElixir.Orchestrator`.
- Do not treat comments as wake triggers.
- Do not implement maturity gate behavior.
- Do not implement writer-side comment upsert policy beyond the tracker
  operations this fork must provide.

### DMAT-009 - Wire Daemon Lifecycle And Failure Park

ticket_title: Wire daemon dispatch state, lease, and failure-exhaustion park

initial_status: Backlog

difficulty: hard

ownership: Symphony implementation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Own the central daemon lifecycle wiring in the orchestrator: sleep
candidate evaluation, lease-at-dispatch flip to `daemon_dispatch_state`,
daemon-dispatch-state crash recovery, per-state daemon dispatch cap
visibility, finite retry exhaustion, and orchestrator-authored unevaluated
workpad parks. This ticket does not implement maturity-gate dispatch.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `docs/symphony-plans/daemon-maturity-upstream-spec-verification.md`
- `docs/symphony-plans/daemon-maturity-linear-mechanics-verification.md`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/tracker.ex`
- `elixir/lib/symphony_elixir/linear/adapter.ex`
- `elixir/lib/symphony_elixir/daemon_wake.ex`
- `elixir/docs/logging.md`

owned_files:

- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- `elixir/test/symphony_elixir/orchestrator_daemon_lifecycle_test.exs`
- `elixir/test/symphony_elixir/orchestrator_daemon_retry_test.exs`

source_notes:

- Requirements R1, R2, R5, R7, R8, R18, and R19.
- Design sections for state classes and identity, lease-at-dispatch, agent exit
  contract, failure handling, and sequencing constraints.
- `agent.daemon_max_retry_attempts` default `3` is designed for failure
  handling; tracker config remains limited to the four fields in R1/R4/R10.

dependencies:

- item: DMAT-002
  type: integration
  requires: SPEC and retry-boundary verification is project-integrated
  reason: daemon parking must compose with current retry path rather than
  replace it blindly.
- item: DMAT-004
  type: integration
  requires: custom state mechanics verification is project-integrated
  reason: daemon lease depends on dispatch-state setup and category behavior.
- item: DMAT-006
  type: integration
  requires: config/model runway is project-integrated
  reason: daemon lifecycle uses shared config and issue fields.
- item: DMAT-007
  type: integration
  requires: timer-only wake engine is project-integrated
  reason: orchestrator should delegate wake calculation to tested pure logic.
- item: DMAT-008
  type: integration
  requires: comment read/update binding is project-integrated
  reason: exhaustion parking edits the orchestrator's titled workpad comment.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Fetch daemon sleep candidates and evaluate them with the pure timer-only wake
  helper.
- Before dispatching a due daemon, write the lease by moving it to
  `daemon_dispatch_state`, then re-fetch and dispatch through active-state
  machinery.
- Ensure implementation-class dispatch excludes `daemon_dispatch_state` while
  daemon dispatch still counts against that state's
  `max_concurrent_agents_by_state` cap.
- Add finite daemon retry exhaustion and park exhausted daemon evaluations by
  editing the orchestrator's own titled workpad comment with
  `verdict: unevaluated`, then moving the issue to Unhappy.
- Ensure a later real daemon verdict supersedes an exhaustion park.
- Preserve normal active-ticket dispatch, existing retry/reconciliation
  behavior, and per-state status reporting for non-daemon tickets.

acceptance_checks:

- Tests cover sleeping daemon skipped, due daemon leased to dispatch state,
  crash after state flip re-dispatches, crash during evaluation uses active
  retry, finite retry exhaustion parks to Unhappy, and real verdict supersedes
  park.
- Tests prove comments do not wake daemons and daemon dispatch occupancy is
  visible through per-state running counts.
- Tests prove normal tickets without daemon config behave as before.
- Targeted validation includes daemon lifecycle/retry tests and
  `make -C elixir specs.check`; run `make -C elixir all` before handoff unless
  blocked by environment.

split_criteria:

- shared-orchestrator-file
- async-pipeline-boundary
- validation-surface
- integration-validation-dependency

exclusions:

- Do not implement maturity-gated dependencies.
- Do not add `daemon_label`.
- Do not add class-budget config.
- Do not implement ceremony or replanning daemon behavior.

### DMAT-010 - Implement Maturity Gate And Regression Advisory

ticket_title: Implement direct-blocker maturity gate and regression advisory

initial_status: Backlog

difficulty: hard

ownership: Symphony implementation agent; human reviewer Jeremy Carroll; target
repository `Orchestra-Bio/symphony`.

scope: Implement the direct-edge maturity gate and wire it into both current
blocker call sites. The gate replaces the hardcoded `Todo`-only terminal helper
with shared `maturity_labels` logic, uses `{:gated, blockers}` naming, ignores
daemon-state blockers with a warning, and emits one advisory comment per
observed maturity regression without killing the dependent worker.

source_files:

- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `docs/symphony-plans/daemon-maturity-linear-mechanics-verification.md`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/lib/symphony_elixir/config.ex`
- `elixir/docs/logging.md`

owned_files:

- `elixir/lib/symphony_elixir/maturity_gate.ex`
- `elixir/lib/symphony_elixir/orchestrator.ex`
- `elixir/lib/symphony_elixir/linear/client.ex`
- `elixir/lib/symphony_elixir/linear/issue.ex`
- `elixir/test/symphony_elixir/maturity_gate_test.exs`
- `elixir/test/symphony_elixir/orchestrator_maturity_gate_test.exs`

source_notes:

- Requirements R10, R11, R12, R13, R14, R15, R16, and R18.
- Design `Blocker Snapshot Shape`, `Gate Function`, `Stack Labels`,
  `Regression Prod`, and `Plan-Side Obligations`.
- PR #2 `M-1`, `M-3`, and `M-4`: two call sites, Todo-gate divergence, and
  `{:gated, blockers}` result naming.

dependencies:

- item: DMAT-004
  type: integration
  requires: maturity relation and label mechanics verification is
  project-integrated
  reason: the gate must rely only on verified direct-blocker data.
- item: DMAT-006
  type: integration
  requires: config/model runway is project-integrated
  reason: the gate consumes shared `maturity_labels`, `daemon_states`, and
  blocker-label fields.
- item: DMAT-005
  type: integration
  requires: early `DIVERGENCES.md` runway is project-integrated
  reason: replacing the Todo-only gate is a fork divergence.
- item: DMAT-009
  type: integration
  requires: daemon lifecycle wiring is project-integrated or a human-approved
  sequencing plan records shared orchestrator edits
  reason: both tickets edit `orchestrator.ex`; sequencing avoids competing
  central-file changes.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Extend blocker refs with normalized blocker labels from the verified Linear
  query shape.
- Add `SymphonyElixir.MaturityGate` or an equivalent pure module.
- Treat a direct blocker as satisfied when it is terminal or has a configured
  maturity label. Empty `maturity_labels` reproduces terminal-only behavior.
- Ignore daemon-state blockers with a warning/diagnostic result because daemon
  blocker edges are plan bugs.
- Replace the current terminal-only helper at both `should_dispatch_issue?/4`
  and `retry_candidate_issue?/2`, sharing the same implementation.
- Use `{:gated, blockers}` or equivalent naming; leave
  `Orchestrator.State.blocked` untouched.
- Add maturity regression advisory comments once per observed transition for
  running/claimed dependents and never kill the worker.
- Parse unknown or experimental `stack:*` labels only enough to warn and prove
  they do not widen phase-1 eligibility.

acceptance_checks:

- Unit tests prove empty maturity config keeps upstream terminal-only behavior.
- Unit tests prove direct mature blockers open depth-2 dispatch and compose in
  depth-3 synthetic graphs without transitive depth checks.
- Tests cover immature blockers, daemon-state blockers, both gate call sites,
  `{:gated, blockers}` naming, and eligible -> regressed -> eligible
  transitions.
- Regression advisory tests prove duplicate comments are not emitted every tick
  and the worker is not killed.
- Targeted validation includes maturity gate/orchestrator tests and
  `make -C elixir specs.check`; run `make -C elixir all` before handoff unless
  blocked by environment.

split_criteria:

- shared-orchestrator-file
- typed-seam-contract
- validation-surface
- integration-validation-dependency

exclusions:

- Do not implement phase-1 `stack:*` override semantics.
- Do not read GitHub state for maturity.
- Do not enforce `max_stack_depth` in the engine.
- Do not implement Project B branch-base or join-branch behavior.

### DMAT-011 - Complete Cookbook And Real Linear Demo Evidence

ticket_title: Document cookbook conventions and demonstrate daemon maturity behavior

initial_status: Backlog

difficulty: hard

ownership: Symphony validation/documentation agent; human reviewer Jeremy
Carroll; target repository `Orchestra-Bio/symphony`.

scope: Complete the public cookbook material and collect project-level evidence
for the flagship project-completion sentinel daemon and maturity-gated
dependency behavior. The demo must use a real Linear project unless missing
state setup, permissions, or credentials are recorded as an explicit blocker.

source_files:

- `DIVERGENCES.md`
- `docs/symphony-plans/daemon-maturity-requirements.md`
- `docs/symphony-plans/daemon-maturity-design.md`
- `elixir/README.md`
- `elixir/WORKFLOW.md`

owned_files:

- `examples/cookbook/project-completion-sentinel.md`
- `examples/cookbook/daemon-workpad-verdicts.md`
- `examples/cookbook/repo-neutral-workspaces.md`
- `examples/cookbook/multi-repo-workspaces.md`
- `docs/symphony-smoke-daemon-maturity.md`

source_notes:

- Requirements R9, R16, and project done predicate.
- Design `Documentation And Repository Strategy`, `Validation Strategy`, and
  `Requirement Coverage`.
- The flagship sentinel demo queries every issue in a real Linear project with
  `linear_graphql`, including terminal issues.

owned_external_resources:

- Temporary or human-approved real Linear project/issues used for daemon
  sentinel and maturity smoke verification.

dependencies:

- item: DMAT-009
  type: integration
  requires: daemon lifecycle and failure park are project-integrated
  reason: the sentinel must exercise implemented daemon behavior.
- item: DMAT-010
  type: integration
  requires: maturity gate and regression advisory are project-integrated
  reason: the DAG demo must exercise implemented maturity behavior.
- item: DMAT-005
  type: integration
  requires: divergence runway is project-integrated
  reason: cookbook docs should link to the fork divergence record.

integration_pattern: none

initial_labels:

- Linear: `pink`
- GitHub PR: `pink`, `symphony`

required_actions:

- Add cookbook guidance for the project sentinel pattern, daemon titled-workpad
  verdicts, repo neutrality, and multi-repo workspaces.
- Identify or create a real Linear project suitable for a project-completion
  sentinel. If required states, labels, or permissions are missing, record a
  precise `Input Needed` handoff instead of substituting unit tests.
- Run a sentinel daemon that queries every ticket in the project via
  `linear_graphql`, including terminal tickets.
- Prove the project completion predicate: all daemons Happy and all
  non-daemons Done or Cancelled.
- Demonstrate an Unhappy/advisory path where the sentinel records the
  incomplete condition without relying on comment-triggered wake.
- Demonstrate a depth-2 maturity-gated chain where blocker maturity allows
  dependent dispatch before blocker terminal completion.
- Demonstrate maturity regression where removing the maturity label emits one
  advisory comment and does not kill the dependent.

acceptance_checks:

- `docs/symphony-smoke-daemon-maturity.md` records target ref, Linear project,
  issue identifiers, daemon cadence labels, verdict workpads, maturity labels,
  dispatch/advisory observations, result, limitations, and next handoff.
- Cookbook entries are repo-neutral and do not expose internal-only Google Doc
  links as required public reading.
- Unit/integration tests from prior items are not claimed as a substitute for
  real Linear proof. If real Linear demo access is missing, the ticket stops
  with structured missing-access evidence.
- Targeted validation includes Markdown formatting for owned docs and any
  relevant smoke commands used by the demo.

split_criteria:

- proof-of-work-boundary
- external-system-boundary
- validation-surface

exclusions:

- Do not implement replanning daemon or ceremony daemon behavior.
- Do not create permanent production Linear projects unless a human explicitly
  approves.
- Do not open an upstream PR or adoption pitch.

## Completion Gates

- `DMAT-001`, `DMAT-002`, `DMAT-003`, and `DMAT-004` are
  project-integrated or explicitly blocked with accepted human decisions before
  implementation tickets leave `Backlog`.
- `DMAT-005` is project-integrated before any behavior-divergence
  implementation PR lands.
- Daemon wake-contract tests pass with fake clock, deterministic jitter,
  timer-only wake semantics, titled workpad anchors, blocked-daemon coverage,
  and no `issue.updatedAt` fallback.
- Linear binding tests pass for comment metadata normalization, narrow body
  fetch, `commentUpdate`, wake-label visibility, and blocker visibility.
- Lease and restart-recovery tests pass: dispatch-state lease, crash after
  lease re-dispatch, crash during evaluation retry, finite retry exhaustion
  park, and later real verdict superseding park.
- Per-state concurrency tests prove daemon evaluations are capped by the daemon
  dispatch state through `agent.max_concurrent_agents_by_state`.
- Maturity gate tests cover direct blocker labels, empty config terminal-only
  behavior, depth 2, depth 3 composition, both gate call sites, daemon-blocker
  warnings, and regression advisory comments.
- Tree-equality CI between fork `main` and the confirmed derived rebased branch
  is present and either passing or blocked only by an explicit human-owned
  branch-name/setup question.
- `DIVERGENCES.md` and cookbook docs match implemented behavior and exclude
  out-of-phase items.
- A real Linear project sentinel demo records sleeping, timer wake, evaluation,
  Happy/Unhappy verdicts, advisory comments, and project-completion predicate
  evidence, or records the exact missing access/state setup blocker.
- A real or accepted equivalent maturity DAG demo records early dispatch on
  maturity and advisory-only regression behavior.
- No project-scoped temporary markers, stubs, adapters, disabled paths,
  compatibility exports, or temporary flags remain unless a human explicitly
  promotes them to durable architecture.

## Known Open Decisions

| Decision                                                               | Current plan behavior                                                                                                                                                      | Owner or follow-up        |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Exact derived rebased branch name for tree-equality CI                 | `DMAT-003` must confirm the branch name or stop with `Input Needed`; this plan does not invent one.                                                                        | Human lead or `DMAT-003`. |
| Real Linear project/team for the sentinel and maturity smoke demos     | `DMAT-011` may use a temporary project only when required states, labels, and permissions are available or human-approved; otherwise it records missing-access proof.      | Human lead or `DMAT-011`. |
| Phase-2 `stack:*` override semantics                                   | Not fanned out. Unknown or experimental stack labels must not widen phase-1 eligibility.                                                                                   | Later enhancement.        |
| Check-back-later one-shot timed waits for non-daemon tickets           | Not fanned out. Phase 1 preserves extension points without implementing one-shot wait behavior.                                                                            | Later enhancement.        |
| Writer-side comment convention and orphan cleanup                      | Not fanned out as fork engine work. The fork consumes titled comments and degrades safely; writer upsert protocol belongs to operator workflow/agent convention ownership. | Later workflow project.   |
| SSH-spawned remote worker termination under `:one_for_all` supervision | Left as a technical verification called out by the design; implementation that relies on it must verify or stop.                                                           | Follow-up verification.   |

No known open decision blocks committing this fan-out plan. The first open
decision may block `DMAT-003`, and the second may block `DMAT-011` if required
state setup or Linear permissions are unavailable.

## Dry-Run Ticket Payload Expectations

A no-write dry run from this plan should produce eleven new ticket payloads:

| Item                                                                             | Initial status | Linear labels | GitHub PR labels   |
| -------------------------------------------------------------------------------- | -------------- | ------------- | ------------------ |
| DMAT-001 Verify daemon comment metadata, wake-label, and blocker fetch mechanics | Todo           | `pink`        | `pink`, `symphony` |
| DMAT-002 Verify current SPEC.md and retry-exhaustion facts                       | Todo           | `pink`        | `pink`, `symphony` |
| DMAT-003 Add tree-equality CI for fork main and derived rebased branch           | Todo           | `pink`        | `pink`, `symphony` |
| DMAT-004 Verify maturity relation, label, and custom state mechanics             | Todo           | `pink`        | `pink`, `symphony` |
| DMAT-005 Create early DIVERGENCES.md runway for daemon maturity                  | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-006 Add daemon and maturity config plus normalized data runway              | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-007 Implement timer-only daemon wake engine with fake-clock tests           | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-008 Add Linear comment read and commentUpdate support for daemon workpads   | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-009 Wire daemon dispatch state, lease, and failure-exhaustion park          | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-010 Implement direct-blocker maturity gate and regression advisory          | Backlog        | `pink`        | `pink`, `symphony` |
| DMAT-011 Document cookbook conventions and demonstrate daemon maturity behavior  | Backlog        | `pink`        | `pink`, `symphony` |

Each generated ticket payload must include:

- Linear team: `ABC`
- Project: `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`
- Target repository: `https://github.com/Orchestra-Bio/symphony.git`
- Assignee: Jeremy Carroll when identity resolution is available
- Base branch: `main`
- Integration branch: `symphony/daemon-maturity/integration`
- Source inputs and source notes copied from the item
- Owned files copied from `owned_files`
- Owned external resources copied from `owned_external_resources` when present
- Dependency entries preserved as ticket-description guidance, not Linear
  blocker relations
- Validation expectations copied exactly into the generated ticket
- PR instructions requiring labels `pink` and `symphony`

No live Linear fan-out writes should happen until a trigger/fan-out step prints
and records the dry-run payloads and receives explicit human confirmation or an
equivalent accepted automation gate.
