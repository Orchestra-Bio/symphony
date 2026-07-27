# Repo-Neutral Workspaces

Symphony work starts from a Linear issue, not from an assumption that the first
local checkout is the target repository. A repo-neutral workflow makes the
target repository explicit and records the checkout used for evidence.

## Required Inputs

Before editing, identify:

- target repository;
- base branch;
- issue identifier;
- branch name;
- validation commands;
- PR target and labels.

Prefer project metadata or the issue description for these values. If the
workspace was provisioned with a different repository, clone the target
repository inside the workspace and work there.

## Local Layout

Use a layout that is easy to audit:

```text
workspace-root/
  target-repo/
  optional-support-repo/
```

Record the target checkout path, remote URL, branch, and base ref in the issue
workpad or equivalent execution log. Do not treat a harness checkout mismatch as
a source-access blocker when the target repository is cloneable.

## Branch And PR Rules

Create the task branch from the selected base branch in the target repository.
For Symphony project work, the branch convention is:

```text
symphony/<project-code>/<issue-id>/<short-description>
```

Open the PR against the selected base branch unless the issue explicitly calls
for a stacked branch. The Linear issue's `branchName` can be useful context, but
the workflow and project metadata decide the submitted branch.

## Evidence

Evidence should name the repository and ref it proves. A validation line such
as `mix test` is incomplete without the checkout and commit it ran against.

Useful evidence fields:

- target repository and path;
- base branch and head SHA;
- command or environment;
- result;
- limitation;
- next handoff.

Repo-neutral evidence lets a reviewer distinguish "this ran in the harness
repo" from "this ran in the target repo."
