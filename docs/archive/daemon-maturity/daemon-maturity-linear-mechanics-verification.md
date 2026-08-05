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

| Requirement                                          | Result                         | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                  | Follow-up                                                                                                                                                                          |
| ---------------------------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Native relation direction for the fork's query shape | Satisfied                      | Creating `ABC-293 blocks ABC-294` produced `ABC-293.relations.nodes[0].type == "blocks"` with `issue == ABC-293` and `relatedIssue == ABC-294`; the dependent side, `ABC-294.inverseRelations.nodes[0].type == "blocks"`, returned `issue == ABC-293` and `relatedIssue == ABC-294`. The fork must query from the dependent candidate's `inverseRelations` filtered to `type == "blocks"`; each relation's `issue` is the direct blocker. | Keep using dependent-side `inverseRelations` for direct blockers.                                                                                                                  |
| Direct blocker labels are visible                    | Satisfied                      | A dependent issue query selecting `inverseRelations.issue.labels.nodes` returned the direct blocker's labels. A poll-shaped project/state query against `Backlog` also returned `ABC-294.inverseRelations.issue.labels.nodes`, proving the nested selection works even when the blocker itself is not the candidate issue.                                                                                                                | Add the missing nested blocker label selection and normalization in implementation.                                                                                                |
| Label removals are visible in refreshed snapshots    | Satisfied                      | Adding existing label `validation-surface` to `ABC-293` made it appear in `ABC-294.inverseRelations.issue.labels.nodes`; removing the label made it disappear in the next refreshed query. The blocker's `updatedAt` advanced on both label edits.                                                                                                                                                                                        | Regression-prod logic can compare previous and refreshed direct-blocker label snapshots.                                                                                           |
| Default maturity label setup                         | Satisfied for current ABC team | The live rework setup query returned a `mature` team label. The label mechanics proof used existing live labels and remains independent of the final configured default.                                                                                                                                                                                                                                                                  | ABC-295 owns the team-configuration record and switchover checklist. Implementation tickets should consume configured `tracker.maturity_labels`, not stop on physical label setup. |
| Current blocker snapshot shape in fork code          | Drifted                        | `Linear.Client` currently reads direct blockers from `inverseRelations`, but the nested selection only asks for blocker `id`, `identifier`, and `state.name`. `Linear.Issue.blocked_by` likewise has no `labels` field today.                                                                                                                                                                                                             | DMAT-006 or DMAT-010 must extend the query and normalized blocker ref with lowercase labels before enabling `maturity_labels`.                                                     |
| Current gate call sites                              | Drifted                        | Current `should_dispatch_issue?/4` and `retry_candidate_issue?/2` both call the terminal-only `todo_issue_blocked_by_non_terminal?/2` helper.                                                                                                                                                                                                                                                                                             | DMAT-010 must replace both call sites with one shared direct-edge maturity gate.                                                                                                   |
| Linear exposes state category/type data              | Satisfied                      | Team state queries return state `type`, including current `started` states such as `In Progress`, `Rework`, `Waiting for CI`, `Human Input Needed`, and `In Review`.                                                                                                                                                                                                                                                                      | Use state `type` as setup evidence for operator-created daemon states.                                                                                                             |
| Daemon dispatch state can be `Started`-type          | Satisfied for current ABC team | Linear supports `started` workflow states on this team, and the schema exposes `workflowStateCreate(input: {type, name, color, teamId})`. The live rework setup query returned `Evaluating` with `type == "started"`, matching the design's working daemon dispatch state name.                                                                                                                                                           | ABC-295 owns the final team actuals and switchover checklist. Implementation tickets should consume the configured `tracker.daemon_dispatch_state`.                                |
| `Happy` and `Unhappy` daemon resting states exist    | Satisfied for current ABC team | The live rework setup query returned `Happy` with `type == "started"` and `Unhappy` with `type == "started"`.                                                                                                                                                                                                                                                                                                                             | ABC-295 owns the final team actuals and switchover checklist. Implementation tickets should consume configured `tracker.daemon_states`.                                            |

## Direct-Blocker Boundary

The fixture proves only one direct edge: `ABC-293 -> ABC-294`. Queries did not
walk through a second blocker layer and did not assert transitive depth
visibility. That is intentional. Requirements R11 and the design's
`Plan-Side Obligations` keep `max_stack_depth`, default `3`, as a fan-out and
planning constraint. The Elixir gate remains edge-local and depth-agnostic.

## Configuration Ownership And Rollout Prerequisites

The original verification identified team-setup gaps, but those gaps are
operator configuration, not promotion gates for unrelated implementation
tickets. ABC-295 / DMAT-013 is the single owner for documenting and applying
the Linear team configuration. DMAT-006 adds config fields, DMAT-007 is a pure
wake function, and DMAT-010 needs configured `maturity_labels`; none of those
tickets should stop solely to ask for physical Linear states or labels that
ABC-295 owns.

As of the rework setup query, the current ABC team has:

- `mature` label.
- `Happy` state with `type == "started"`.
- `Unhappy` state with `type == "started"`.
- `Evaluating` state with `type == "started"`, matching the design's working
  daemon dispatch state name.

The remaining implementation gap from this verification is code-local: the
current fork query and normalized issue model do not yet include direct blocker
labels. DMAT-006 or DMAT-010 must add those fields before enabling
`maturity_labels`.

If a target deployment lacks the configured states or labels at real-use or
switchover time, record that as Input Needed against ABC-295/team
configuration. No verified mechanics gap changes the accepted design.

## Validation

- `npx prettier --check docs/symphony-plans/daemon-maturity-linear-mechanics-verification.md`
  passed for Markdown formatting.
