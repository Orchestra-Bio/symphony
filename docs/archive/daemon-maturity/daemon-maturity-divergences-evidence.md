# Daemon Maturity Divergences Evidence

```yaml
project_code: daemon-maturity
ticket: ABC-291
base_branch: main
source_ref: a9deb3c993c1cc564a2496c2ac8917c07ee08ab8
```

## Purpose

This is the source-read and implementation-evidence record for the root
`DIVERGENCES.md` created by ABC-291. It is project history, not maintained
operator guidance; the root `DIVERGENCES.md` is the current behavior guide.

## Sources Read

- Linear issue `ABC-291` and project metadata for scope, project code
  `daemon-maturity`, color `pink`, base branch `main`, no integration branch,
  and human lead Jeremy Carroll.
- Internal Google handoff sources were fetched through the required Symphony
  reader helper. Public readers should use the archived requirements and design
  documents below as the dereferenceable record of those inputs.
- Local planning sources:
  `docs/archive/daemon-maturity/daemon-maturity-requirements.md`,
  `docs/archive/daemon-maturity/daemon-maturity-design.md`, and
  `docs/archive/daemon-maturity/fan-out-plan-ABC-227-daemon-maturity.md`.
- Verification and setup sources:
  `docs/archive/daemon-maturity/daemon-maturity-daemon-linear-verification.md`,
  `docs/archive/daemon-maturity/daemon-maturity-upstream-spec-verification.md`,
  `docs/archive/daemon-maturity/daemon-maturity-linear-mechanics-verification.md`,
  and `docs/archive/daemon-maturity/daemon-maturity-team-configuration.md`.
- GitHub PR evidence: PR #1, #2, and #3 decision/review comments; PR #7 body
  and review for `tracker.team_key`; PR #12 and #13 second review comments for
  the Symphony workpad anchor; PR #14 for DMAT-016; PR #17 for daemon lifecycle;
  PR #18 for maturity gating; PR #20 for history-based retry-exhaustion restore;
  PR #22 for maturity-gated retry-claim release; PR #23 for dispatch decision
  logging and slot-exhaustion visibility; and PR #24 for maturity-gate dashboard
  visibility; PR #25 for time-bounded dispatch log dedupe; PR #26 for dashboard
  section order; and PR #27 for daemon-state filter casing.
- PR #19 / ABC-290 status: open at source-read time. It writes three archive
  files directly to `docs/archive/daemon-maturity/` when it lands and records
  real-use verification as blocked on operator switchover to fork `main`.
- Original implementation source read at
  `4f141507d8eb76e7cc4765293f31488fdf8aefc6`, especially
  `elixir/lib/symphony_elixir/config.ex`,
  `config/schema.ex`, `linear/client.ex`, `linear/issue.ex`,
  `linear/adapter.ex`, `tracker.ex`, `tracker/memory.ex`,
  `daemon_wake.ex`, `maturity_gate.ex`, `symphony_workpad.ex`, and
  `orchestrator.ex`.
- Rework implementation code at `f948c8dc389bd3bd48803ad0121843644511b57b`,
  especially `orchestrator.ex`, `maturity_gate.ex`, `presenter.ex`, and
  `dashboard_live.ex`.
- Current implementation code at `a9deb3c993c1cc564a2496c2ac8917c07ee08ab8`,
  especially `config/schema.ex`, `linear/client.ex`, `daemon_wake.ex`,
  `orchestrator.ex`, `maturity_gate.ex`, `presenter.ex`, and
  `dashboard_live.ex`.

Unavailable sources: none.

## Dependency Status

- DMAT-009 daemon lifecycle and failure handling: merged as PR #17.
- DMAT-010 maturity gate and regression advisory: merged as PR #18.
- DMAT-016 Symphony workpad writer and wake anchor: merged as PR #14.
- DMAT-020 history-based daemon retry restoration: merged as PR #20 and present
  on `main` before this document was written.
- DMAT-011 real-use evidence: PR #19 is open and records the remaining operator
  blocker. No synthetic evidence is substituted here.

## Implemented Behavior Evidence

- `Config.validate_settings/1` rejects Linear tracker config when both
  `tracker.project_slug` and `tracker.team_key` are absent. `Linear.Client`
  chooses `project_slug` before `team_key`.
- `Config.Schema.Tracker` owns `daemon_states`,
  `daemon_dispatch_states`, `daemon_default_wake`, `maturity_labels`, and
  `maturity_gate_state_scope`. `Config.Schema.Agent` keeps daemon capacity on
  `max_concurrent_agents_by_state`.
- `daemon_states` preserves configured casing for Linear state-name filters,
  while runtime daemon and maturity-gate comparisons normalize state names.
- `Linear.Client` filters the `## Symphony Workpad` anchor server-side with
  `startsWithIgnoreCase`, reads `id` and `updatedAt`, and keeps comment body
  reads off the wake path.
- `SymphonyWorkpad.ensure_created/1` creates `## Symphony Workpad\nNew` when a
  visible candidate lacks the anchor, and `record_last_run/2` updates it to
  `Last run <ISO 8601>` after agent runs.
- `DaemonWake.evaluate/4` uses configured daemon states, dispatch states,
  terminal states, wake labels, the default wake cadence, comment `updatedAt`,
  and deterministic jitter. It has no comment-triggered wake branch.
- `Orchestrator.append_due_daemon_candidates/4` fetches resting daemon states
  only when daemon config is present, ensures their workpad anchors, leases due
  daemons to the first configured dispatch state, refetches, and dispatches
  through the normal active path.
- `Orchestrator.park_exhausted_daemon/4` reads recent issue state history and
  restores the newest transition's `fromState` when that transition entered a
  configured daemon dispatch state. It leaves the ticket in the dispatch state
  for operator recovery when history is missing or unreadable.
- `Orchestrator.maybe_dispatch/1` fetches visible candidates before dispatch
  capacity checks, records maturity-gate snapshot data from that poll, and logs
  repeated gate or dispatch rejection decisions through a four-hour in-memory
  de-dup cache.
- `MaturityGate.evaluate/2` is pure and direct-edge. It treats terminal
  blockers and configured maturity labels as satisfied, ignores daemon-state
  blockers with warnings, and returns `{:gated, blockers}` for unsatisfied
  blockers.
- `Orchestrator` uses the maturity gate in candidate selection, retry lookup,
  and dispatch-time revalidation. A retry lookup that is still maturity-gated
  releases the issue claim for a later poll and removes pre-session workspace
  residue when no session workspace had started.
- `Orchestrator` emits one advisory comment per observed maturity regression
  without killing the running worker.
- The dashboard API and Phoenix dashboard expose maturity-gated and out-of-scope
  candidate snapshots with blocker state, labels, and gate reasons. The
  LiveView places running sessions before rate limits, maturity gate, blocked
  sessions, and retry queue.

## Archive Decision

The planning documents are archived as historical records. They are not edited
to match the final implementation, including their superseded wake and
failure-handling sections or the design's incorrect statement that the
orchestrator has its own Linear writer identity.
