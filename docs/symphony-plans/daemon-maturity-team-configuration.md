# Daemon Maturity Team Configuration

```yaml
project_code: daemon-maturity
ticket: ABC-295
base_branch: main
configuration_date: 2026-07-25
```

## Part 1 - Required Shape, Repo-Neutral

This is the deployment-level Linear team shape required by daemon tickets and
maturity-gated dependencies. The fork code consumes configured strings; this
document describes what the deployment must provide in Linear before real daemon
use or the state-model switchover.

Do not delete legacy states as part of setup. Deleting Linear workflow states is
irreversible operational work because Linear prompts issue reassignment,
including archived issues. Do not migrate issue states as part of setup; ticket
migration belongs to the switchover.

### Workflow States

| Role                         | Required Linear category | Config relationship                                                                                                              | Notes                                                                                        |
| ---------------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Backlog                      | Backlog                  | Outside active and terminal dispatch.                                                                                            | Existing backlog state may be reused.                                                        |
| Implementation active pool   | Started                  | Listed in `tracker.active_states`; implementation-class dispatch uses this pool after excluding `tracker.daemon_dispatch_state`. | Replaces older implementation states such as todo, in-progress, or rework during switchover. |
| Someone else's move          | Unstarted                | Not listed in `tracker.active_states`.                                                                                           | One inactive state; reason is carried by `waiting:*` labels when this state is adopted.      |
| Daemon resting, satisfied    | Started                  | Listed in `tracker.daemon_states`.                                                                                               | Resting daemon state; not dispatched as ordinary active work.                                |
| Daemon resting, dissatisfied | Started                  | Listed in `tracker.daemon_states`.                                                                                               | Resting daemon state; not dispatched as ordinary active work.                                |
| Daemon dispatch/evaluating   | Started                  | Equals `tracker.daemon_dispatch_state` and is also listed in `tracker.active_states`.                                            | Daemon-only lease target. It must be excluded from the implementation-class active scope.    |
| Done                         | Completed                | Listed in `tracker.terminal_states`.                                                                                             | Existing done state may be reused.                                                           |
| Cancelled                    | Canceled                 | Listed in `tracker.terminal_states`.                                                                                             | Existing cancelled state may be reused.                                                      |
| Duplicate                    | Duplicate                | Listed in `tracker.terminal_states` when the deployment has a duplicate workflow state.                                          | Existing duplicate state may be reused.                                                      |

The daemon dispatch state is a deliberate extra active state. It is a work-class
state, not a pipeline state. It exists so daemon evaluation can be dispatched,
reconciled, and capped with the existing per-state concurrency controls while
remaining distinguishable from normal implementation work.

### Labels

| Role                  | Required label shape                                     | Required when                                          | Notes                                                                                                                                                                   |
| --------------------- | -------------------------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Maturity marker       | At least one configured `tracker.maturity_labels` value. | Before maturity-gated dependency dispatch is enabled.  | The default value is `mature`. Empty `maturity_labels` reproduces upstream terminal-only blocker behavior.                                                              |
| Daemon cadence        | `wake:15m`, `wake:1h`, `wake:4h`, `wake:1d`.             | Before real daemon use.                                | The wake implementation lowercases and trims label names before matching. Unknown, absent, or conflicting wake labels use the workflow default and never mean wake-now. |
| Inactive reason hints | `waiting:human`, `waiting:ai-review`, `waiting:ci`.      | Before the inactive state is adopted for live tickets. | These labels are non-exclusive stale-cache hints; the reconciler must re-derive the true waiting reason from reality.                                                   |

Do not adopt the inactive state for a deployment unless there is also a
reliable releaser for the waiting reasons. Where GitHub-to-Linear bridge
automation exists, bridge events can release tickets from `waiting:*` labels.
Where that automation does not exist, moving live tickets to inactive states can
strand them instead of pausing them.

### Switchover Invariants

- `tracker.daemon_dispatch_state` must normalize to exactly one configured
  active state and must be disjoint from daemon and terminal states.
- `tracker.daemon_states` must be disjoint from active and terminal states after
  normalization.
- Implementation-class dispatch must use
  `tracker.active_states - {tracker.daemon_dispatch_state}`.
- An operator forcing a daemon wake must move the ticket to the daemon dispatch
  state, not to an ordinary implementation active state.
- Daemons use `wake:*` labels for cadence and titled workpad comments for their
  verdict anchor. Comments do not cause wake eligibility.

## Part 2 - ABC Team Actuals

Team: `ABC` / `Symphony` (`2395627c-dad6-46f1-8345-cd82bae50680`).

Dispatch state name proposal pending human-lead ratification: `Evaluating`.

Target switchover config values:

```yaml
tracker:
  active_states:
    - Active
    - Evaluating
  terminal_states:
    - Done
    - Canceled
    - Duplicate
  daemon_states:
    - Happy
    - Unhappy
  daemon_dispatch_state: Evaluating
  daemon_default_wake: 1h
  maturity_labels:
    - mature

agent:
  max_concurrent_agents_by_state:
    evaluating: 5
```

During a rename or migration window, `tracker.active_states` may temporarily
include legacy implementation names alongside `Active` and `Evaluating`. That is
a compatibility bridge only; the switchover target is the config above.

### Workflow State Record

Verified by query after creation on 2026-07-25:

| Role                         | ABC state name | Linear type | Color     | State id                               | Status                                                  |
| ---------------------------- | -------------- | ----------- | --------- | -------------------------------------- | ------------------------------------------------------- |
| Implementation active pool   | `Active`       | `started`   | `#f2c94c` | `140d6370-5bb1-4920-a279-53e8e6fbacdd` | Created and verified.                                   |
| Someone else's move          | `Inactive`     | `unstarted` | `#e2e2e2` | `1f18c71e-1156-414a-96bf-efcf29561fd3` | Created and verified; not yet adopted for live tickets. |
| Daemon resting, satisfied    | `Happy`        | `started`   | `#4cb782` | `40f011da-6d0f-4ec2-9a51-47eddb99d5b8` | Created and verified.                                   |
| Daemon resting, dissatisfied | `Unhappy`      | `started`   | `#eb5757` | `4d966452-93e8-4494-8148-96fa28e0259b` | Created and verified.                                   |
| Daemon dispatch/evaluating   | `Evaluating`   | `started`   | `#26b5ce` | `755e4ffc-87ca-4c1a-af46-a488ab906be8` | Created and verified.                                   |
| Backlog                      | `Backlog`      | `backlog`   | `#bec2c8` | `3b055245-258c-49e1-96bf-dcd416fd8059` | Existing; unchanged.                                    |
| Done                         | `Done`         | `completed` | `#5e6ad2` | `733d1bce-7420-4b00-b4cf-b6614afc7125` | Existing; unchanged.                                    |
| Cancelled                    | `Canceled`     | `canceled`  | `#95a2b3` | `e5d310e9-4cea-48de-9dad-cc5f7f0f2b87` | Existing; unchanged.                                    |
| Duplicate                    | `Duplicate`    | `duplicate` | `#95a2b3` | `72d1e676-671b-4b11-a6a2-1dfccebfdd79` | Existing; unchanged.                                    |

Legacy implementation/review states still exist and were not deleted or used for
state migration by this ticket: `Todo`, `In Progress`, `Rework`,
`Waiting for CI`, `Human Input Needed`, and `In Review`.

### Label Record

Verified by query after creation on 2026-07-25:

| Role            | ABC label name | Color     | Label id                               | Status                |
| --------------- | -------------- | --------- | -------------------------------------- | --------------------- |
| Maturity marker | `mature`       | `#2ea44f` | `79e9c1b2-3357-4a1e-bf86-d071d086e2a8` | Created and verified. |
| Daemon cadence  | `wake:15m`     | `#f2c94c` | `edb26db4-3a00-47ff-8831-d60e2bcc82e3` | Created and verified. |
| Daemon cadence  | `wake:1h`      | `#4EA7FC` | `8a8f3762-a9d9-4a8a-964f-d5f0fe68b931` | Created and verified. |
| Daemon cadence  | `wake:4h`      | `#7C3AED` | `686b7fc6-5c96-4ee7-8eff-f6847ef32c8e` | Created and verified. |
| Daemon cadence  | `wake:1d`      | `#95a2b3` | `e37b87e8-18bf-4f95-9e75-3ef6abee66f3` | Created and verified. |

Deferred until `Inactive` is adopted for live tickets:

- `waiting:human`
- `waiting:ai-review`
- `waiting:ci`

Those labels were not created by ABC-295 because no tickets were migrated to
`Inactive` and the inactive reason workflow is not live yet. For fork-hosted
work in `Orchestra-Bio/symphony`, there are also no GitHub-to-Linear bridge
workflows to release tickets from `waiting:*` labels, so adopting `Inactive`
there would strand tickets unless an operator manually performs every release.

### Recorded Creation Operations

The setup was performed through Linear GraphQL, not console clicks.

Workflow state inputs:

```graphql
workflowStateCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  type: "started",
  name: "Active",
  color: "#f2c94c"
})

workflowStateCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  type: "unstarted",
  name: "Inactive",
  color: "#e2e2e2"
})

workflowStateCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  type: "started",
  name: "Happy",
  color: "#4cb782"
})

workflowStateCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  type: "started",
  name: "Unhappy",
  color: "#eb5757"
})

workflowStateCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  type: "started",
  name: "Evaluating",
  color: "#26b5ce"
})
```

Label inputs:

```graphql
issueLabelCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  name: "mature",
  color: "#2ea44f",
  description: "Maturity-gated dependency marker; default tracker.maturity_labels value."
})

issueLabelCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  name: "wake:15m",
  color: "#f2c94c",
  description: "Daemon cadence label: wake every 15 minutes."
})

issueLabelCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  name: "wake:1h",
  color: "#4EA7FC",
  description: "Daemon cadence label: wake every 1 hour."
})

issueLabelCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  name: "wake:4h",
  color: "#7C3AED",
  description: "Daemon cadence label: wake every 4 hours."
})

issueLabelCreate(input: {
  teamId: "2395627c-dad6-46f1-8345-cd82bae50680",
  name: "wake:1d",
  color: "#95a2b3",
  description: "Daemon cadence label: wake every 1 day."
})
```

### Verification Query

The state and label records above were verified with this query after the
creation mutations:

```graphql
query VerifyDaemonMaturityTeamConfig($teamId: String!) {
  team(id: $teamId) {
    id
    key
    name
    states(first: 100) {
      nodes {
        id
        name
        type
        color
        position
      }
    }
    labels(first: 250) {
      nodes {
        id
        name
        color
        description
      }
    }
  }
}
```

Variables:

```json
{ "teamId": "2395627c-dad6-46f1-8345-cd82bae50680" }
```

### Switchover Checklist

- Configure `tracker.active_states` to include `Active` and `Evaluating`.
- Configure implementation-class dispatch to use active states minus
  `Evaluating`.
- Ratify `Evaluating` with the human lead before treating the daemon dispatch
  state name as final.
- Configure `tracker.daemon_dispatch_state` as `Evaluating`.
- Configure `tracker.daemon_states` as `Happy` and `Unhappy`.
- Configure `tracker.terminal_states` as `Done`, `Canceled`, and `Duplicate`.
- Configure `tracker.maturity_labels` as `mature`, unless intentionally
  disabling the maturity gate with an empty list.
- Confirm daemon cadence labels exist before creating or operating daemon
  tickets.
- Create and verify `waiting:*` labels, and confirm release automation exists,
  before adopting `Inactive` for live tickets.
- Migrate issue states only during the switchover, not during setup.
- Leave legacy states and labels in place until well after a successful
  switchover.
