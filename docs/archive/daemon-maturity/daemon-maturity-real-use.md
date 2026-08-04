# Daemon Maturity Real-Use Evidence

## Result

Real-use verification is blocked for this agent-owned checkpoint. The cookbook
docs can be written locally, but daemon and maturity behavior still need an
operator-owned run of the fork's `main` against the ABC Linear team with the
switchover configuration below.

This document intentionally does not claim unit or integration tests as a
substitute for real Linear use.

## Target Ref

- Implementation target already merged for operator verification:
  `Orchestra-Bio/symphony` `main` at or after `44b23cd`.
- Documentation checkpoint: `ABC-290` PR branch until it is merged.
- Required operator evidence target: exact post-merge `main` SHA recorded before
  running the daemon and maturity checks.

## Linear Project And Issues

- Linear team: `ABC` / `Symphony`.
- Linear project: `Daemon Tickets + Maturity-Gated Dependencies (symphony fork)`.
- Evidence issue for this checkpoint: `ABC-290`.
- Real-use sentinel issue: not created by this agent checkpoint.
- Real-use maturity fixture: not created by this agent checkpoint.

Do not create blocker relations among generated `DMAT-*` tickets. Temporary or
human-approved Linear demo fixtures may use blocker relations when the operator
performs the real-use proof.

## Daemon Cadence And Workpads

Supported daemon cadence labels:

- `wake:15m`
- `wake:1h`
- `wake:4h`
- `wake:1d`

Engine wake anchor:

- Title: `## Symphony Workpad`
- First body: `New`
- Later body: `Last run <ISO 8601 timestamp>`
- Clock input: Linear comment `updatedAt`

Daemon verdict workpad:

- Written by the daemon agent, not by the engine.
- For Codex-run daemons, use `## Codex Workpad`.
- Records Happy or Unhappy verdict, reason, evidence, limitations, and next
  handoff.

Comments do not wake daemons. An urgent daemon evaluation requires moving the
daemon issue to the daemon dispatch state.

## Maturity Labels

The shipped config default is:

```yaml
tracker:
  maturity_labels: []
  maturity_gate_state_scope:
    - todo
```

That reproduces upstream terminal-only blocker behavior. The standard explicit
enablement value for real use is:

```yaml
tracker:
  maturity_labels:
    - mature
```

The maturity gate is direct-edge only. It evaluates Linear native blocker
relations, blocker states, and blocker labels. It does not read GitHub branch or
review state.

## Deployment And Switch Config

The real-use run needs the fork's `main` actually running for the ABC team with
configuration equivalent to:

```yaml
tracker:
  team_key: ABC
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
  daemon_dispatch_states:
    - Evaluating
  daemon_default_wake: 1h
  maturity_labels:
    - mature
  maturity_gate_state_scope:
    - todo

agent:
  max_concurrent_agents_by_state:
    evaluating: 5
```

The team states and labels exist per
`docs/archive/daemon-maturity/daemon-maturity-team-configuration.md`, but this
checkpoint did not switch the live orchestrator to the fork's `main`.

Do not adopt `Inactive` for live fork-hosted tickets as part of this proof. This
repository has no GitHub-to-Linear bridge workflows to release `waiting:*`
labels automatically, so any such transitions would be manual operator work.

## Blocker

The required proof is unavailable to this agent session for three concrete
reasons:

- the live orchestrator is not running the merged daemon-maturity implementation
  from `Orchestra-Bio/symphony` `main`;
- switching the live orchestrator requires human operator control of the ABC
  team configuration and running deployment;
- the flagship sentinel proof requires wall-clock daemon sleep, timer wake, and
  verdict observation, which cannot be substituted by a short local command.

Owner: human operator / human lead Jeremy Carroll.

## Limitations

- No live sentinel issue was run.
- No maturity demo fixture was run.
- No dispatch, advisory, restart, fix, or revert evidence was produced.
- Local tests remain useful regression checks but are not accepted as real-use
  proof for this ticket.

## Local Validation

Commands run for this documentation checkpoint:

- `npx prettier --check docs/archive/daemon-maturity/project-completion-sentinel.md docs/archive/daemon-maturity/daemon-workpad-verdicts.md docs/archive/daemon-maturity/daemon-maturity-real-use.md`
  passed.
- `mix deps.get` passed in `elixir/` to install dependencies needed by the local
  PR-body checker in this fresh clone.
- `mix pr_body.check --file /tmp/abc-290-pr-body.md` passed in `elixir/`.

No real-use daemon or maturity commands were run.

## Fixes, Reverts, And Restarts

None performed in this checkpoint.

Required real-use evidence must record any fixes, reverts, restart commands, and
post-restart observations if the operator run exposes a problem.

## Dispatch And Advisory Observations

None observed in real Linear use during this checkpoint.

The operator run still needs to record:

- a daemon issue sleeping in `Happy` or `Unhappy`;
- timer wake and lease into `Evaluating`;
- agent verdict and return to `Happy` or `Unhappy`;
- retry exhaustion restoring a daemon to its pre-lease resting state when that
  state is known, or leaving it in dispatch for operator recovery when it is
  not known;
- maturity-gated dependent dispatch when a direct blocker carries `mature`;
- release of a maturity-gated retry claim so a normal poll can re-evaluate the
  dependent after the blocker matures;
- maturity-regression advisory behavior if the blocker loses the label after
  dependent dispatch.

## Next Handoff

1. Switch the live ABC orchestrator to `Orchestra-Bio/symphony` `main` at the
   exact target SHA.
2. Apply the deployment configuration above.
3. Select or create human-approved sentinel and maturity fixture issues.
4. Let the sentinel sleep and wake by timer.
5. Record Linear issue identifiers, workpad timestamps, state transitions,
   daemon verdict, retry-restoration behavior, maturity label changes, retry
   claim release, advisory comments, restart evidence, any fixes or reverts, and
   final result.
6. If real use fails, fix or revert on `main`, restart the daemon, and record the
   recovery evidence.
