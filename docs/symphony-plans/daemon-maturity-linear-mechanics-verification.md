# Verification: Daemon Maturity Linear Mechanics

```yaml
project_code: daemon-maturity
ticket: ABC-284
base_branch: main
verification_date: 2026-07-25
```

## Purpose

This document verifies the Linear mechanics that the daemon-maturity design
depends on before implementation tickets rely on them: native blocker relation
direction, labels on direct blockers, label-change visibility in refreshed
snapshots, current custom state setup, and the daemon dispatch state's required
`Started`-type behavior.

Relation verification is deliberately scoped to direct blockers only.
Transitive blocker walking and `max_stack_depth` remain plan-side obligations
and are out of engine scope for this project.

## Sources Read

- Accepted fan-out plan:
  `docs/symphony-plans/fan-out-plan-ABC-227-daemon-maturity.md` on
  `Orchestra-Bio/symphony` `main`, merged by PR #3.
- Requirements:
  `docs/symphony-plans/daemon-maturity-requirements.md`, especially R1, R10,
  R11, R12, R14, R15, and R17.
- Design: `docs/symphony-plans/daemon-maturity-design.md`, especially
  `State Classes And Identity`, `Blocker Snapshot Shape`, `Gate Function`,
  `Plan-Side Obligations`, and `Verification Boundaries`.
- PR #2 decision comments, especially D9: comments never wake daemons, the
  daemon dispatch state is a deliberate extra active state, and that state must
  be a `Started`-type Linear state.
- Internal handoffs were re-fetched through the Symphony Google Docs reader for
  source parity. Their SHA-256 hashes matched the design source records:
  `b52f85b72709075449c44db207e96a0e758c27fd4be6a8c5bdfced9cd4040d2f`,
  `7a4d9bcdf19e4fbb452db3b8a228aef1464eba61c8f84326f7c1aa510385ea45`,
  and `ae2a97e943f43a7ece9e050da81a9a2e7ff70dc50384997fbda7afb71a2fe91e`.
- Current code anchors:
  `elixir/lib/symphony_elixir/linear/client.ex`,
  `elixir/lib/symphony_elixir/linear/issue.ex`, and
  `elixir/lib/symphony_elixir/orchestrator.ex`.

## Live Fixture

Linear live target:

- Team: `ABC` / `Symphony` (`2395627c-dad6-46f1-8345-cd82bae50680`).
- Project: `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`,
  slug `1966c5cbbf8f`.
- Disposable blocker: `ABC-293`, issue id
  `618ef50b-b571-4f3c-8421-428a452267b0`.
- Disposable dependent: `ABC-294`, issue id
  `31b8a2e0-6a71-4ac9-baf3-91dbbf714fdb`.
- Relation id: `30f7c6be-219f-4a5e-a2d1-6dd03ec42df7`.

Both disposable issues were created in `Backlog` with label `pink`, used only
for this verification, then moved to `Canceled` after the checks. No blocker
relations were created to or from generated `DMAT-*` tickets.

## Results

| Requirement                                          | Result                                                    | Evidence                                                                                                                                                                                                                                                                                                                   | Follow-up                                                                                                                                                                       |
| ---------------------------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Native relation direction for the fork's query shape | Satisfied                                                 | Creating `ABC-293 blocks ABC-294` produced `ABC-293.relations.nodes[0].type == "blocks"` with `relatedIssue == ABC-294`; `ABC-294.inverseRelations.nodes[0].type == "blocks"` with `issue == ABC-293`. This matches the fork's current `inverseRelations` + `type == "blocks"` read path for a blocked issue.              | Keep using `inverseRelations` for direct blockers.                                                                                                                              |
| Direct blocker labels are visible                    | Satisfied                                                 | A dependent issue query selecting `inverseRelations.issue.labels.nodes` returned the direct blocker's labels. A poll-shaped project/state query against `Backlog` also returned `ABC-294.inverseRelations.issue.labels.nodes`, proving the nested selection works even when the blocker itself is not the candidate issue. | Add the missing nested blocker label selection and normalization in implementation.                                                                                             |
| Label removals are visible in refreshed snapshots    | Satisfied                                                 | Adding existing label `validation-surface` to `ABC-293` made it appear in `ABC-294.inverseRelations.issue.labels.nodes`; removing the label made it disappear in the next refreshed query. The blocker's `updatedAt` advanced on both label edits.                                                                         | Regression-prod logic can compare previous and refreshed direct-blocker label snapshots.                                                                                        |
| Default maturity label setup                         | Blocked for downstream promotion                          | Team label list contains `pink` and many process labels, but no `mature` label. The label mechanics are verified with an existing label, not with the final default maturity label.                                                                                                                                        | Input Needed before maturity implementation promotion: create the `mature` Linear issue label or configure `tracker.maturity_labels` to a real team label.                      |
| Current blocker snapshot shape in fork code          | Drifted                                                   | `Linear.Client` currently reads direct blockers from `inverseRelations`, but the nested selection only asks for blocker `id`, `identifier`, and `state.name`. `Linear.Issue.blocked_by` likewise has no `labels` field today.                                                                                              | DMAT-006 or DMAT-010 must extend the query and normalized blocker ref with lowercase labels before enabling `maturity_labels`.                                                  |
| Current gate call sites                              | Drifted                                                   | Current `should_dispatch_issue?/4` and `retry_candidate_issue?/2` both call the terminal-only `todo_issue_blocked_by_non_terminal?/2` helper.                                                                                                                                                                              | DMAT-010 must replace both call sites with one shared direct-edge maturity gate.                                                                                                |
| Linear exposes state category/type data              | Satisfied                                                 | Team state queries return state `type`, including current `started` states such as `In Progress`, `Rework`, `Waiting for CI`, `Human Input Needed`, and `In Review`.                                                                                                                                                       | Use state `type` as setup evidence for operator-created daemon states.                                                                                                          |
| Daemon dispatch state can be `Started`-type          | Satisfied for Linear mechanics, blocked for current setup | Linear supports `started` workflow states on this team, and the schema exposes `workflowStateCreate(input: {type, name, color, teamId})`. Current team setup has no explicit daemon dispatch state such as `Evaluating` or `Active`.                                                                                       | Input Needed before daemon lease implementation promotion: choose or create the daemon dispatch state as a `Started`-type state and record the configured name.                 |
| `Happy` and `Unhappy` daemon resting states exist    | Blocked for current setup                                 | Current team states are `Backlog`, `Todo`, `In Progress`, `Waiting for CI`, `Human Input Needed`, `Canceled`, `Done`, `Duplicate`, `Rework`, and `In Review`. There are no `Happy` or `Unhappy` states.                                                                                                                    | Input Needed before daemon state migration or real-use verification: create `Happy` and `Unhappy` with the chosen state category, or record a deliberate renamed configuration. |

## Direct-Blocker Boundary

The fixture proves only one direct edge: `ABC-293 -> ABC-294`. Queries did not
walk through a second blocker layer and did not assert transitive depth
visibility. That is intentional. Requirements R11 and the design's
`Plan-Side Obligations` keep `max_stack_depth`, default `3`, as a fan-out and
planning constraint. The Elixir gate remains edge-local and depth-agnostic.

## Current Setup Gaps

The mechanics needed for implementation are usable, but current team setup is
not complete for rollout:

- `mature` label is missing.
- `Happy` and `Unhappy` states are missing.
- A distinct daemon dispatch state is not named or created yet.
- The current fork query and normalized issue model do not yet include direct
  blocker labels.

These are Input Needed blockers for downstream implementation tickets before
they move out of `Backlog` or are otherwise promoted for daemon/maturity
rollout. They do not require changing the accepted design: the design already
expects operator configuration values for state names and expects the
implementation to add blocker label fields.

## Validation

- `npx prettier --check docs/symphony-plans/daemon-maturity-linear-mechanics-verification.md`
  passed for Markdown formatting.
