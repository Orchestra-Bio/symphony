# Fork Divergences

This file records implemented behavior in the Orchestra fork of Symphony.
`SPEC.md` stays upstream-owned and is intentionally not edited for these
fork-only dispatch rules.

## Team-Scoped Linear Dispatch

`tracker.team_key` may select Linear issues by team instead of
`tracker.project_slug`. When both are configured, `project_slug` takes
precedence; Linear tracker config is invalid when neither selector is present.

## Daemon States And Dispatch States

`tracker.daemon_states` names resting daemon states; an empty list disables the
daemon path. `tracker.daemon_dispatch_states` names daemon-only active states:
the first value is the lease write target, and every configured value is
recognized for daemon identity and recovery.

Operators force a daemon wake by moving the ticket to the first configured
daemon dispatch state, not to an ordinary implementation-active state.

## Timer-Only Daemon Wakes

Daemon cadence labels are `wake:15m`, `wake:1h`, `wake:4h`, and `wake:1d`.
Absent, unknown, or conflicting cadence labels use `tracker.daemon_default_wake`
and never mean wake-now.

Comments do not wake daemons. A sleeping daemon evaluates only when its timer is
due or when an operator moves it to a daemon dispatch state.

## Symphony Workpad Wake Anchor

Symphony maintains one `## Symphony Workpad` comment on each ticket: `New` when
the anchor is first created, and `Last run <ISO 8601>` after every agent run,
including failures. Daemon wake timing uses that comment's server-written
`updatedAt`.

The Linear poll selects that comment server-side with a
`startsWithIgnoreCase` body filter and reads only `id` and `updatedAt`.

## Daemon Lease And Retry Exhaustion

When a resting daemon is due, the orchestrator leases it by moving it to the
first configured daemon dispatch state, refetches the issue, and dispatches it
through the active path.

After finite daemon retry exhaustion, the orchestrator reads recent Linear issue
history, finds the newest transition into a configured daemon dispatch state,
and restores that transition's `fromState`. Exhaustion writes no comment of its
own and does not infer Happy or Unhappy.

## Maturity-Gated Dependencies

`tracker.maturity_labels` extends direct Linear blocker gating: a blocker is
satisfied when it is terminal or carries one configured maturity label. An empty
label list reproduces upstream terminal-only behavior.

The gate is direct-edge only, reads Linear blocker state and labels, and does
not inspect GitHub. Daemon-state blockers are ignored with a warning.

## Maturity Gate State Scope

`tracker.maturity_gate_state_scope` limits which candidate states receive the
blocker gate; its default is `["todo"]`. Out-of-scope means ungated, so removing
`todo` also removes upstream's `Todo` blocker gate; use `maturity_labels: []` to
disable maturity gating while preserving terminal-only blockers.

## Maturity Regression Advisory

If a running dependent's blocker loses maturity, Symphony writes one advisory
comment for the observed transition and leaves the worker running. If the
dependent has not dispatched yet, it simply becomes ineligible again.

## Daemon Dispatch Budgeting

Daemon dispatch occupancy uses existing
`agent.max_concurrent_agents_by_state` limits on daemon dispatch states. Those
limits are ceilings; normal implementation work can still use other available
dispatch capacity.

## Plan-Side Stack Controls

Stack depth limits and branch-base or join-branch behavior are planning and
workflow constraints. The Elixir engine enforces only the direct Linear blocker
gate described above.
