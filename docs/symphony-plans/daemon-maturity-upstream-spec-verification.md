# Upstream SPEC And Retry Verification

```yaml
project_code: daemon-maturity
ticket: ABC-282
base_branch: main
verification_ref: 5fd477434cedb4b22d3b020be468dd593511330f
integration_branch: symphony/daemon-maturity/integration
integration_ref_read: 28e21f61bc24631e8dc1668c102a5cefd67bb97f
```

## Purpose

This document verifies the current `SPEC.md` and Elixir implementation facts
that daemon tickets and maturity-gated dependency work would otherwise rely on.
It is documentation only: no `SPEC.md`, config, retry, daemon, maturity, or
parking behavior is changed here.

## Source Inputs Read

Authoritative in-repo sources:

- `docs/symphony-plans/fan-out-plan-ABC-227-daemon-maturity.md` on `main` at
  `5fd477434cedb4b22d3b020be468dd593511330f`.
- `docs/symphony-plans/daemon-maturity-requirements.md`, especially R3, R7,
  R8, R17, and R18.
- `docs/symphony-plans/daemon-maturity-design.md`, especially Current
  Implementation Anchors, Failure Handling, and Verification Boundaries.
- `SPEC.md`.
- `elixir/AGENTS.md`, `elixir/README.md`, and `elixir/WORKFLOW.md`.
- `elixir/lib/symphony_elixir/config.ex`.
- `elixir/lib/symphony_elixir/config/schema.ex`.
- `elixir/lib/symphony_elixir/linear/adapter.ex`.
- `elixir/lib/symphony_elixir/linear/client.ex`.
- `elixir/lib/symphony_elixir/linear/issue.ex`.
- `elixir/lib/symphony_elixir/orchestrator.ex`.
- `elixir/lib/symphony_elixir/agent_runner.ex`.
- `elixir/lib/symphony_elixir/workspace.ex`.
- Targeted tests under `elixir/test/symphony_elixir/`.

Decision and provenance sources:

- GitHub PR #1 review and decision comments from Jeremy Carroll on
  2026-07-25, including comment IDs `5078588547`, `5078661538`, and
  `5078713319`, plus approval review `4779356496`.
- GitHub PR #2 review and handoff comments from Jeremy Carroll on 2026-07-25,
  including comment IDs `5078833748`, `5078935039`, and `5078968551`, plus
  approval review `4779470436`. PR #2 decision D9 is the source that
  comment-triggered daemon wakes are removed and the current retry path is
  delay-capped rather than attempt-capped.
- GitHub PR #3 review and decision comments from Jeremy Carroll on
  2026-07-25, including comment IDs `5079157760` and `5079172210`, plus
  approval review `4779606397`.
- Internal Google handoffs fetched through the Symphony reader service account:
  Daemon Tickets - Design Handoff (v2), Maturity-Gated Dependencies - Design
  Handoff (v2), and Minimal Ticket State Model - Design Handoff (v7).
  Public readers should use the merged requirements, design, fan-out plan, and
  PR decision comments above as the dereferenceable record.

Integration branch read:

- `origin/symphony/daemon-maturity/integration` was read at
  `28e21f61bc24631e8dc1668c102a5cefd67bb97f`. It contains merged requirements
  and design work, but it is behind `main` for the accepted ABC-227 fan-out
  plan. No conflict is expected for this new verification file.

## Fact Table

| Upstream fact relied on                                                         | Current source evidence                                                                                                                                                                                                                | Status                | May daemon/maturity planning rely on it? | Notes                                                                                                                                                                                                         |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Configurable active and terminal state sets exist with upstream defaults.       | `SPEC.md` lists `tracker.active_states` default `["Todo", "In Progress"]` and `tracker.terminal_states` default `["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]`; `Config.Schema.Tracker` has the same defaults.             | confirmed             | yes                                      | Deployment files may override these sets. The in-repo `elixir/WORKFLOW.md` expands active states to `Todo`, `In Progress`, `Merging`, and `Rework`.                                                           |
| State comparisons are case-insensitive.                                         | `SPEC.md` says normalized issue state comparisons use lowercase. The orchestrator trims and downcases state names before active, terminal, blocker, and per-state concurrency checks.                                                  | confirmed             | yes                                      | The implementation is slightly stricter than the spec by also trimming whitespace.                                                                                                                            |
| Polling cadence defaults to 30 seconds and can be overridden.                   | `SPEC.md` and `Config.Schema.Polling` use `polling.interval_ms` default `30000`; `elixir/WORKFLOW.md` sets `5000` for the example workflow.                                                                                            | confirmed             | yes                                      | Daemon timing must use the configured cadence, not assume the default.                                                                                                                                        |
| Startup schedules an immediate poll, then repeats by interval.                  | `Orchestrator.init/1` schedules a tick with delay `0`; after each `:run_poll_cycle`, the orchestrator schedules the next tick with the current `poll_interval_ms`.                                                                     | confirmed             | yes                                      | Runtime config is refreshed before tick transition and before the poll cycle.                                                                                                                                 |
| Current tick sequence is reconcile, validate, fetch candidates, sort, dispatch. | `maybe_dispatch/1` reconciles running and blocked entries, validates config, fetches candidate issues, then `choose_issues/2` sorts and dispatches.                                                                                    | confirmed             | yes                                      | A small dashboard transition timer exists before `maybe_dispatch/1`, but it does not change dispatch ordering.                                                                                                |
| Candidate fetch uses configured active states.                                  | `Linear.Client.fetch_candidate_issues/0` passes `tracker.active_states` to the Linear query filter.                                                                                                                                    | confirmed             | yes                                      | Daemon sleep candidates will require a separate fetch path; they are not available from the current active-candidate fetch unless their state is active.                                                      |
| Normalized issue data contains a scalar `branch_name`.                          | `SPEC.md` defines `branch_name` as `string or null`; `Linear.Client` reads Linear `branchName` into `Issue.branch_name`; `PromptBuilder` passes all issue struct fields into the prompt.                                               | confirmed             | yes, as a scalar only                    | Planning must not rely on multi-repo branch metadata from the current issue model.                                                                                                                            |
| Normalized candidate issues include labels and direct blocker refs.             | `Linear.Client` reads issue labels and `inverseRelations` where relation `type` is `blocks`; blocker refs contain id, identifier, and state.                                                                                           | confirmed limitation  | yes, for current blocker state only      | Blocker labels and comments are not in the current normalized blocker shape; maturity labels and daemon workpad anchors still need implementation work.                                                       |
| The current blocker gate is `Todo`-only.                                        | `should_dispatch_issue?/4` calls `todo_issue_blocked_by_non_terminal?/2`, which checks blockers only when normalized issue state is `todo`.                                                                                            | confirmed             | yes                                      | This is the exact helper the maturity gate must replace for candidate dispatch.                                                                                                                               |
| Retry re-selection reuses the same `Todo`-only blocker helper.                  | `retry_candidate_issue?/2` calls `candidate_issue?/3` and `todo_issue_blocked_by_non_terminal?/2`; `revalidate_issue_for_dispatch/3` also routes through `retry_candidate_issue?/2`.                                                   | confirmed             | yes                                      | PR #2 M-1 is confirmed: candidate dispatch and retry re-selection both need the shared maturity gate or behavior will diverge after abnormal exits.                                                           |
| Dispatch revalidates issue state before launching an agent.                     | `dispatch_issue/4` refetches the issue by id, skips missing or ineligible issues, and dispatches only the refreshed issue.                                                                                                             | confirmed             | yes                                      | Daemon lease and maturity implementations should preserve this refresh-before-dispatch boundary.                                                                                                              |
| Retry backoff is delay-capped, not attempt-capped.                              | `failure_retry_delay/1` computes `min(10000 * 2^(attempt - 1), agent.max_retry_backoff_ms)`, with `max_retry_backoff_ms` default `300000`. No max-attempt config exists.                                                               | confirmed             | yes                                      | This confirms PR #2 D9. A finite daemon boundary must be added without replacing the existing delay-capped path for ordinary work.                                                                            |
| Retry queue entries and timers are in memory.                                   | `Orchestrator.State.retry_attempts` stores retry entries, `Process.send_after/3` schedules timers, and stale timer messages are ignored by per-entry retry tokens.                                                                     | confirmed             | yes                                      | A daemon park must delete or supersede the retry entry and cancel any live timer. Stale timer messages are already safe when the entry is missing or token-mismatched.                                        |
| Restart recovery does not restore retries or workers.                           | `SPEC.md` says no retry timers, running sessions, or live worker state survive restart; the service recovers by startup terminal cleanup, fresh active polling, and redispatch. `Orchestrator.init/1` starts with empty runtime state. | confirmed             | yes, with retry-boundary caveat          | A daemon left in the daemon dispatch state before exhaustion can be redispatched after restart with a fresh in-memory retry series unless the implementation records attempt history in tracker-visible data. |
| Hook contract is workspace-cwd only.                                            | `SPEC.md` says hooks execute with the workspace as `cwd`; `Workspace.run_hook/5` runs local hooks with `System.cmd("sh", ["-lc", command], cd: workspace)` and remote hooks after `cd <workspace>`.                                    | confirmed             | yes                                      | No hook environment metadata is present in the current hook contract.                                                                                                                                         |
| `SPEC.md` still treats first-class orchestrator tracker writes as a TODO.       | `SPEC.md` says tracker mutations are typically agent-tool work and lists first-class tracker write APIs as a TODO. Current `Linear.Adapter` already has narrow `create_comment/2` and `update_issue_state/2`, but no `commentUpdate`.  | drifted, non-blocking | yes, with current adapter facts          | The drift does not block planning: the design already relies on narrow orchestrator state/comment writes. Exhaustion work still needs edit-in-place support or a deliberate create-only fallback.             |

## Retry Boundary Verification

### Current Retry Path

Current retry state is owned by `SymphonyElixir.Orchestrator`:

- Normal worker exit schedules a continuation retry with a fixed `1000` ms delay
  and attempt `1` when the issue remains active.
- Abnormal worker exit, spawn failure, and stall detection schedule failure
  retries through `schedule_issue_retry/4`.
- Retry poll failures and no-slot retry attempts reschedule through the same
  helper with `attempt + 1`.
- `schedule_issue_retry/4` cancels the prior retry timer if one exists, stores a
  fresh retry token, records `attempt`, `due_at_ms`, issue metadata, worker host,
  and workspace path, then sends `{:retry_issue, issue_id, retry_token}` after
  the computed delay.
- `handle_retry_issue/4` fetches active candidates, finds the retry issue by id,
  and either dispatches it, reschedules it, or releases the claim.
- `handle_active_retry/4` dispatches only when the issue is still a retry
  candidate and both global and per-state slots are available.

The formula for failure-driven retries is:

```text
delay_ms = min(10000 * 2^(attempt - 1), agent.max_retry_backoff_ms)
```

`failure_retry_delay/1` caps the exponent at `10`, and the default
`agent.max_retry_backoff_ms` is `300000` ms. There is no current attempt
exhaustion boundary.

### Intended Finite Daemon Boundary

The design requires `agent.daemon_max_retry_attempts`, default `3`. It should
compose with the existing path as a daemon-only exhaustion check, not as a
replacement for ordinary retry backoff:

1. When a daemon-owned issue in `daemon_dispatch_state` fails through the normal
   failure retry path, keep using `schedule_issue_retry/4` and the existing
   delay formula while the retry attempt is within the daemon limit.
2. Treat the current retry queue's 1-based `attempt` as the natural counter for
   the first implementation because that is the value already stored in
   `retry_attempts`, passed back into `AgentRunner.run/3`, and exposed to the
   prompt as retry context.
3. Park instead of scheduling the next retry when the next failure-driven retry
   would exceed the configured daemon limit. With the design default, a daemon
   reaches exhaustion after retry attempt `3` has failed and the code would
   otherwise schedule attempt `4`.
4. On exhaustion, cancel/delete the retry entry, release the normal active
   claim, write or update the orchestrator's titled workpad with
   `verdict: unevaluated`, move the issue to `Unhappy`, leave cadence labels in
   place, and do not immediately redispatch.
5. Do not count normal continuation retries as daemon failure exhaustion. A
   successful daemon evaluator is expected to write its verdict and move out of
   the dispatch state; if it exits cleanly but leaves itself active, current
   continuation behavior will re-check active eligibility and should be covered
   by daemon exit-contract tests.

This leaves ordinary active work on the upstream-compatible delay-capped retry
path while adding the finite daemon boundary needed by R8 and PR #2 D9.

### Hot-Loop And Stale-Entry Risks

- Without the finite boundary, a failed daemon in the dispatch state retries
  forever at the capped delay. That is not a per-tick hot loop, but it is still
  an unbounded dispatch-state retry loop and does not satisfy R8.
- The park must move the issue out of the daemon dispatch state before any
  stale retry can redispatch it. `Unhappy` must remain outside `active_states`.
- The park must delete the retry entry and cancel a live timer if present.
  Existing retry-token handling already makes stale timer messages harmless
  when a newer entry replaced them or no entry remains.
- If the orchestrator restarts before exhaustion, the current implementation
  loses retry attempts and timers. A daemon still in the daemon dispatch state
  will be redispatched by fresh active polling. That matches current upstream
  restart recovery, but it means the finite boundary is per in-memory retry
  series unless the implementation deliberately derives an attempt counter from
  tracker-visible data.
- If the orchestrator parks a daemon and then a late worker writes a real
  verdict, the design says the real verdict supersedes the unevaluated park.
  The current code has no compare-and-swap support, so tests should cover that
  accepted last-writer interleaving rather than add locking.

## Blockers

No drift was found that blocks daemon or maturity planning.

Implementation tickets should still record these non-blocking risks explicitly:

- Exact off-by-one semantics for `daemon_max_retry_attempts` must be named in
  tests.
- Retry exhaustion across orchestrator restarts is not durable unless future
  implementation stores or derives attempts outside `retry_attempts`.
- Maturity implementation still needs blocker labels in the normalized blocker
  shape.
- Daemon Linear binding still needs comment metadata fetches and `commentUpdate`
  or an explicitly accepted create-only fallback.

## Validation Plan

Run Markdown formatting validation for this file:

```sh
npx prettier --check docs/symphony-plans/daemon-maturity-upstream-spec-verification.md
```
