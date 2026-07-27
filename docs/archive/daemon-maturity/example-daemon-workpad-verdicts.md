# Daemon Workpad Verdicts

Daemon tickets use two different titled comments for two different jobs:

- `## Symphony Workpad` is written by the engine and anchors timer wakes.
- The daemon agent's own titled workpad records the daemon verdict.

Keep those roles separate. The engine cannot author a `## Codex Workpad`, and a
daemon verdict should not be hidden inside the engine wake anchor.

## Engine Anchor

The engine creates `## Symphony Workpad` when a candidate issue has no visible
anchor comment. The first body is:

```text
## Symphony Workpad
New
```

After every agent run, including failed runs, the engine edits that same comment
in place:

```text
## Symphony Workpad
Last run 2026-07-26T15:42:07Z
```

Linear's server-written comment `updatedAt` is the wake anchor. The poll query
matches this title server-side and selects only comment metadata needed for the
clock. Comment bodies are not part of steady-state polling.

## Verdict Workpad

The daemon agent writes its own verdict in its own titled workpad. For Codex-run
daemons, use the existing `## Codex Workpad` slot.

Recommended verdict section:

```md
### Daemon Verdict

- Verdict: Happy
- Checked at: 2026-07-26T15:42:07Z
- Scope: Linear project `example-project`
- Predicate: all daemons Happy; all non-daemons terminal
- Evidence: queried 12 issues, 0 non-terminal normal issues, 0 daemons evaluating
- Limitations: none
- Next handoff: none
```

For an `Unhappy` verdict, include the blocking issue identifiers and the action
needed from the next actor. Keep a short rolling history in the workpad body
when repeated evaluations matter.

## Wake Rules

- A daemon wakes by timer only.
- Comments left while a daemon sleeps are inputs for the next scheduled run,
  not wake triggers.
- Urgent evaluation is a state write to the daemon dispatch state.
- `issue.updatedAt` is never a wake anchor.
- Comment `createdAt` is not a steady-state wake input.
- Missing, unknown, or conflicting `wake:*` labels use the configured default
  cadence and never mean wake now.

## Failure Boundary

Daemon evaluation failures use the normal worker retry path. When daemon retry
exhaustion is reached, the current implementation restores the ticket to its
known pre-lease resting state. If the pre-lease state is not known, it leaves
the ticket in the dispatch state for operator recovery rather than guessing.

That failure handling is dispatch lifecycle, not a Happy or Unhappy verdict.
Happy and Unhappy are project or daemon evaluation results written by the
daemon agent.
