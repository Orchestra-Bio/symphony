# Project Completion Sentinel

A project-completion sentinel is a daemon ticket that evaluates whether a Linear
project is done. It is a convention layered on daemon tickets, not a separate
orchestrator concept.

## Linear Shape

Create one daemon issue in the project being watched.

- Resting states are configured daemon states, normally `Happy` and `Unhappy`.
- The dispatch state is the first configured `tracker.daemon_dispatch_states`
  value, normally `Evaluating`.
- Cadence is a `wake:*` label: `wake:15m`, `wake:1h`, `wake:4h`, or
  `wake:1d`.
- The daemon may be blocked by normal setup or frontier tickets while the
  project is not ready for sentinel evaluation.
- Do not make normal work depend on the daemon. A daemon never completes, so a
  daemon blocker is a planning error.

## Completion Predicate

The sentinel should query every issue in its Linear project, including terminal
issues. Candidate polling is not enough because terminal tickets are normally
outside the active candidate set.

A conservative project predicate is:

- every daemon ticket in the project is in the configured satisfied daemon
  resting state, normally `Happy`;
- every non-daemon ticket is in an accepted terminal state, normally `Done` or
  `Canceled`;
- no daemon ticket remains in a configured daemon dispatch state.

If the project treats `Duplicate` as terminal, record that explicitly in the
sentinel verdict. Do not let the sentinel infer project policy from a Linear
state name alone.

## Evaluation Loop

On each daemon run, the sentinel should:

1. Re-read the project through Linear GraphQL.
2. Classify issues by configured daemon, daemon dispatch, and terminal states.
3. Evaluate the completion predicate from the fresh snapshot.
4. Update the daemon agent's own titled workpad with verdict, reason, evidence,
   limitations, and a bounded history.
5. Move the sentinel issue to `Happy` when the predicate is true, or `Unhappy`
   when it is false.
6. Leave advisory comments only where another actor needs a concrete next
   action.

The engine-maintained `## Symphony Workpad` is the daemon wake anchor. It is not
the sentinel verdict. The sentinel verdict belongs in the daemon agent's own
titled workpad, such as `## Codex Workpad` for a Codex-run daemon.

## Operational Notes

Comments do not wake a sentinel. A human or automation that needs an immediate
evaluation should move the daemon issue to the daemon dispatch state.

Unit tests can validate the predicate, but they are not real-use evidence. Real
evidence requires a daemon issue in Linear to sleep, wake by timer, evaluate the
project, and leave an observable verdict.
