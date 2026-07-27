# Multi-Repo Workspaces

Use a multi-repo workspace when one Linear issue needs coordinated local reads
or edits across repositories. Keep the repositories separate and make the
submitted PR surface explicit.

## Workspace Map

Record a small workspace map before editing:

```text
workspace-root/
  engine/       Orchestra-Bio/symphony, branch symphony/example/ABC-123/engine
  operator/     Orchestra-Bio/orc-app, read-only source context
```

For each repository, record whether it is edited, read-only, or only used for a
helper script. This prevents accidental commits in support checkouts.

## Change Ownership

Most issues should submit one PR in one repository. If multiple repositories
must change, each repository needs its own branch, validation evidence, and PR
or an explicit handoff saying which repository remains pending.

Do not hide cross-repo requirements in local uncommitted support files. If a
support repository supplies a script, document the command and the source ref
used.

## Dependency And Maturity Notes

The maturity gate reads Linear direct blocker relations, blocker states, and
blocker labels. It does not inspect GitHub branches or prove that a branch base
exists. Branch and join-base instructions are plan-side obligations, not engine
dispatch inputs.

For multi-repo work, this means:

- create Linear blocker relations only for real issue dependencies;
- use maturity labels to mirror the selected maturity signal into Linear;
- keep branch-base and join-base instructions in the plan or issue text;
- validate each repository at the ref that reviewers will inspect.

## Validation Matrix

Use a compact matrix when evidence crosses repositories:

| Repository | Ref                               | Command or environment | Result | Limitation |
| ---------- | --------------------------------- | ---------------------- | ------ | ---------- |
| `engine`   | `symphony/example/ABC-123/engine` | `mix test`             | Pass   | none       |
| `operator` | `main`                            | source read only       | Pass   | no edits   |

If real end-to-end evidence depends on a deployed operator or a human-owned
environment, record the missing handoff instead of replacing it with local unit
tests.
