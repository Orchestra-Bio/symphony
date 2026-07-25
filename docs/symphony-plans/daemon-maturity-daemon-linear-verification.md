# Verification: Daemon Linear Comment, Label, And Blocker Fetch

```yaml
project_code: daemon-maturity
ticket: ABC-281
base_branch: main
verification_date: 2026-07-25
```

## Scope

This document verifies the Linear data path required before daemon wake
eligibility and Linear binding implementation rely on it. It covers comment
metadata reads, the poll-shaped candidate query with nested comment metadata,
narrow comment body reads, wake-label visibility, direct blocker relation
visibility, and `commentUpdate` schema availability.

No daemon wake eligibility, orchestrator dispatch behavior, daemon comments, or
daemon target comment edits were implemented. No Linear blocker relations were
created among generated `DMAT-*` tickets. The only live comment update was this
ticket's own `## Codex Workpad`, which is required workflow metadata.

`Comment.updatedAt` existence and advance-on-edit behavior was treated as
already verified by the project requirements/design and PR #2 decision comments.
The workflow workpad update produced a later `updatedAt`, but this ticket did
not rely on that as a platform retest.

## Source Inputs Read

- Linear issue `ABC-281` and project metadata through Symphony
  `linear_graphql`. The issue started in `Todo` and was moved to `In Progress`
  before work.
- Accepted fan-out plan
  `docs/symphony-plans/fan-out-plan-ABC-227-daemon-maturity.md`, especially
  `DMAT-001`, confirmed scope decisions, dependency semantics, and PR #3
  decisions D-A, D-B, and D-C.
- Requirements source
  `docs/symphony-plans/daemon-maturity-requirements.md`, especially R2, R4,
  R5, R6, R7, R8, and R17.
- Design source `docs/symphony-plans/daemon-maturity-design.md`, especially
  titled workpad comments, durable wake fields, wake function,
  lease-at-dispatch, failure handling, blocker snapshot shape, and
  verification boundaries.
- Human decision comments:
  - PR #1 requirements comments and approval:
    `https://github.com/Orchestra-Bio/symphony/pull/1#issuecomment-5078588547`,
    `https://github.com/Orchestra-Bio/symphony/pull/1#issuecomment-5078661538`,
    `https://github.com/Orchestra-Bio/symphony/pull/1#issuecomment-5078713319`,
    and
    `https://github.com/Orchestra-Bio/symphony/pull/1#pullrequestreview-4779356496`.
  - PR #2 design comments and approval:
    `https://github.com/Orchestra-Bio/symphony/pull/2#issuecomment-5078833748`,
    `https://github.com/Orchestra-Bio/symphony/pull/2#issuecomment-5078935039`,
    `https://github.com/Orchestra-Bio/symphony/pull/2#issuecomment-5078968551`,
    and
    `https://github.com/Orchestra-Bio/symphony/pull/2#pullrequestreview-4779470436`.
  - PR #3 fan-out comments and approval:
    `https://github.com/Orchestra-Bio/symphony/pull/3#issuecomment-5079157760`,
    `https://github.com/Orchestra-Bio/symphony/pull/3#issuecomment-5079172210`,
    and
    `https://github.com/Orchestra-Bio/symphony/pull/3#pullrequestreview-4779606397`.
- PR #5 rework review:
  `https://github.com/Orchestra-Bio/symphony/pull/5#pullrequestreview-4779750427`
  requested the poll-shaped comment metadata query and explicit validation
  record added here.
- Current code:
  - `elixir/lib/symphony_elixir/linear/client.ex`
  - `elixir/lib/symphony_elixir/linear/issue.ex`
  - `elixir/lib/symphony_elixir/linear/adapter.ex`
  - `elixir/test/symphony_elixir/extensions_test.exs`

Unavailable sources: none.

## Current Code Baseline

- `SymphonyElixir.Linear.Client` polling selects issue metadata, issue labels,
  `inverseRelations`, `createdAt`, and `updatedAt`. It has no comment read path.
- `SymphonyElixir.Linear.Issue` normalizes `labels` and `blocked_by`. It has no
  normalized comment refs.
- `SymphonyElixir.Linear.Adapter.create_comment/2` wraps `commentCreate`.
  `Adapter` has no `commentUpdate` wrapper.

This matches the fan-out premise: daemon implementation needs new comment read
and comment update support, but the required Linear schema/data paths can be
verified first.

## Verification Targets

- Live issue/comment target: `ABC-281`, comment
  `f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f`, created as this ticket's
  `## Codex Workpad`.
- Live poll-shaped target: the `daemon-maturity` Linear project, using the
  configured poll-style state set `Todo`, `In Progress`, `Merging`, and
  `Rework`; the current candidate set returned `ABC-296`, `ABC-284`,
  `ABC-281`, and `ABC-282`.
- Live blocker relation target: `ABC-247`, which has an `inverseRelations`
  `blocks` edge to blocker `ABC-246`.
- Wake-label fixture: current `labels.nodes.name` shape plus code inspection of
  `extract_labels/1`, because the ABC team currently has no `wake:15m`,
  `wake:1h`, `wake:4h`, or `wake:1d` label definitions.
- No disposable Linear issue was created.

## Results Summary

| Check                                           | Target                                  | Result               | Notes                                                                                                       |
| ----------------------------------------------- | --------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------- |
| Comment metadata `id`, `createdAt`, `updatedAt` | Live `ABC-281` workpad comment          | Pass                 | Raw Linear shape is available; current code still needs normalization work.                                 |
| Poll-shaped comment metadata                    | Live daemon-maturity candidate poll     | Pass                 | `issues(filter:)` with nested `comments(first: 20)` succeeded at current client page bounds.                |
| Narrow body fetch by comment id                 | Live `ABC-281` workpad comment          | Pass                 | Body is fetched only by id, not in steady-state polling.                                                    |
| Wake-label visibility                           | Live issue-label path plus fixture      | Pass with setup note | ABC team does not yet define the four wake labels. The GraphQL path and current normalizer preserve labels. |
| Blocker relation visibility                     | Live `ABC-247` blocked by `ABC-246`     | Pass                 | `inverseRelations(type: blocks)` exposes blocker id, identifier, state, and labels.                         |
| `commentUpdate` schema                          | Linear introspection and workpad update | Pass                 | Mutation exists; workpad update returned `success: true`; no daemon target comment was edited.              |

Input Needed blockers: none for the GraphQL mechanics checked here. The only
setup note is that the ABC team does not currently define the four `wake:*`
labels; create them before operating real daemons if label pre-creation is part
of deployment setup.

## Comment Metadata

Exact selection:

```graphql
query CommentMetadata($issueId: String!) {
  issue(id: $issueId) {
    id
    identifier
    comments(first: 20) {
      nodes {
        id
        createdAt
        updatedAt
      }
    }
  }
}
```

Variables:

```json
{ "issueId": "38c7ef75-b1f1-4f8c-aa51-c18ea09b082f" }
```

Observed response shape:

```json
{
  "issue": {
    "id": "38c7ef75-b1f1-4f8c-aa51-c18ea09b082f",
    "identifier": "ABC-281",
    "comments": {
      "nodes": [
        {
          "id": "f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f",
          "createdAt": "2026-07-25T16:37:19.692Z",
          "updatedAt": "2026-07-25T16:43:20.249Z"
        }
      ]
    }
  }
}
```

Cost notes:

- Steady-state daemon polling should use this metadata-only selection, not
  `body`.
- The tested page size was `first: 20`. The implementation should choose a
  bounded page size and pagination policy for the one-per-writer comment
  convention.
- The Linear response observed through the injected tool did not expose a
  numeric query-cost extension.

Result: pass for Linear field availability. Current code still needs a
normalized comment-ref shape in a later implementation ticket.

## Poll-Shaped Comment Metadata

Exact selection:

```graphql
query PollShapedCommentMetadata(
  $projectSlug: String!
  $stateNames: [String!]!
  $first: Int!
  $relationFirst: Int!
  $commentFirst: Int!
) {
  issues(
    filter: {
      project: { slugId: { eq: $projectSlug } }
      state: { name: { in: $stateNames } }
    }
    first: $first
  ) {
    nodes {
      id
      identifier
      state {
        name
      }
      labels {
        nodes {
          name
        }
      }
      inverseRelations(first: $relationFirst) {
        nodes {
          type
          issue {
            id
            identifier
            state {
              name
            }
          }
        }
      }
      comments(first: $commentFirst) {
        nodes {
          id
          createdAt
          updatedAt
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

Variables:

```json
{
  "projectSlug": "daemon-tickets-maturity-gated-dependencies-symphony-fork-1966c5cbbf8f",
  "stateNames": ["Todo", "In Progress", "Merging", "Rework"],
  "first": 50,
  "relationFirst": 50,
  "commentFirst": 20
}
```

Observed response shape:

```json
{
  "issues": {
    "nodes": [
      {
        "id": "455ed51b-932c-4468-88a3-195cf80d7cd8",
        "identifier": "ABC-296",
        "state": { "name": "In Progress" },
        "labels": { "nodes": [{ "name": "pink" }] },
        "inverseRelations": { "nodes": [] },
        "comments": {
          "nodes": [
            {
              "id": "3ac48320-971b-4edc-b8e4-a35afad7d0ec",
              "createdAt": "2026-07-25T17:26:23.224Z",
              "updatedAt": "2026-07-25T17:26:23.168Z"
            },
            {
              "id": "c6b1eac2-f3f2-47a2-bd6b-80a5d13f4619",
              "createdAt": "2026-07-25T17:24:48.672Z",
              "updatedAt": "2026-07-25T17:24:48.655Z"
            }
          ]
        }
      },
      {
        "id": "71cf49a2-cb62-40ac-a47c-4885da85c8c4",
        "identifier": "ABC-284",
        "state": { "name": "Rework" },
        "labels": { "nodes": [{ "name": "pink" }] },
        "inverseRelations": {
          "nodes": [
            {
              "type": "related",
              "issue": {
                "id": "a2cd0889-4924-4793-b7fb-af541817924c",
                "identifier": "ABC-287",
                "state": { "name": "Backlog" }
              }
            },
            {
              "type": "related",
              "issue": {
                "id": "57587fba-38fc-4328-99d8-bc934f19c477",
                "identifier": "ABC-295",
                "state": { "name": "Waiting for CI" }
              }
            }
          ]
        },
        "comments": {
          "nodes": [
            {
              "id": "55901f8d-14b9-49df-a1e4-488f04c3a7dd",
              "createdAt": "2026-07-25T16:47:10.234Z",
              "updatedAt": "2026-07-25T16:54:25.536Z"
            }
          ]
        }
      },
      {
        "id": "38c7ef75-b1f1-4f8c-aa51-c18ea09b082f",
        "identifier": "ABC-281",
        "state": { "name": "Rework" },
        "labels": { "nodes": [{ "name": "pink" }] },
        "inverseRelations": {
          "nodes": [
            {
              "type": "related",
              "issue": {
                "id": "a2cd0889-4924-4793-b7fb-af541817924c",
                "identifier": "ABC-287",
                "state": { "name": "Backlog" }
              }
            },
            {
              "type": "related",
              "issue": {
                "id": "57587fba-38fc-4328-99d8-bc934f19c477",
                "identifier": "ABC-295",
                "state": { "name": "Waiting for CI" }
              }
            }
          ]
        },
        "comments": {
          "nodes": [
            {
              "id": "f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f",
              "createdAt": "2026-07-25T16:37:19.692Z",
              "updatedAt": "2026-07-25T16:45:57.073Z"
            }
          ]
        }
      },
      {
        "id": "33669732-0c60-4dbf-8d70-95dc292cd383",
        "identifier": "ABC-282",
        "state": { "name": "Rework" },
        "labels": { "nodes": [{ "name": "pink" }] },
        "inverseRelations": {
          "nodes": [
            {
              "type": "related",
              "issue": {
                "id": "455ed51b-932c-4468-88a3-195cf80d7cd8",
                "identifier": "ABC-296",
                "state": { "name": "In Progress" }
              }
            }
          ]
        },
        "comments": {
          "nodes": [
            {
              "id": "5a4be83d-fbea-497c-9a20-6810fde3f5cc",
              "createdAt": "2026-07-25T16:38:45.001Z",
              "updatedAt": "2026-07-25T16:45:59.851Z"
            }
          ]
        }
      }
    ],
    "pageInfo": {
      "endCursor": "33669732-0c60-4dbf-8d70-95dc292cd383",
      "hasNextPage": false
    }
  }
}
```

Cost notes:

- This poll-shaped query is the shape DMAT-008 is expected to extend. It
  returns candidate nodes through `issues(filter: ...)`, with comment metadata
  nested under each candidate node.
- The selection used the current client issue/relation page bound of `50` and a
  bounded comment page of `20`; the live daemon-maturity candidate set returned
  4 issues and 5 comment metadata nodes total with `hasNextPage: false`.
- The configured example poll interval in `elixir/WORKFLOW.md` is `5000ms`.
  At these page bounds, the added comment metadata branch is bounded at 1,000
  comment metadata nodes per 50-issue page and does not fetch `body`.
- The query returned without GraphQL errors or Linear complexity-budget
  rejection. The injected `linear_graphql` tool did not expose a numeric query
  cost extension or HTTP cost header.

Result: pass for the live poll-shaped candidate query at current page bounds.
DMAT-008 should keep `comments(first:)` bounded and keep comment `body` on the
narrow id lookup path.

## Narrow Body Fetch

Exact selection:

```graphql
query CommentBodyById($commentId: String!) {
  comment(id: $commentId) {
    id
    body
  }
}
```

Variables:

```json
{ "commentId": "f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f" }
```

Observed response shape:

```json
{
  "comment": {
    "id": "f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f",
    "body": "## Codex Workpad\n\n..."
  }
}
```

Cost notes:

- This is the narrow writer-identification path for an unrecognized comment id.
- The selection fetches exactly one comment by id and requests `body` only on
  that path.
- Workpad bodies can be large; daemon polling should not include `body` in the
  steady-state comment list query.

Result: pass.

## Wake Labels

Exact live issue-label selection:

```graphql
query IssueLabels($issueId: String!) {
  issue(id: $issueId) {
    id
    identifier
    labels(first: 20) {
      nodes {
        name
      }
    }
  }
}
```

Observed live issue-label shape on `ABC-281`:

```json
{
  "issue": {
    "id": "38c7ef75-b1f1-4f8c-aa51-c18ea09b082f",
    "identifier": "ABC-281",
    "labels": {
      "nodes": [{ "name": "pink" }]
    }
  }
}
```

Exact team-label availability check:

```graphql
query TeamWakeLabels($teamId: String!) {
  team(id: $teamId) {
    key
    labels(first: 200) {
      nodes {
        id
        name
      }
    }
  }
}
```

Filtered observed shape:

```json
{
  "team": "ABC",
  "wakeLabels": []
}
```

Fixture evidence for the exact wake label names:

```json
{
  "labels": {
    "nodes": [
      { "name": " wake:15m " },
      { "name": "wake:1h" },
      { "name": "Wake:4H" },
      { "name": "WAKE:1D" }
    ]
  }
}
```

Current `extract_labels/1` maps `labels.nodes[].name` through trim and
lowercase normalization. A standalone Elixir fixture using the same
trim/lowercase operations was run with:

```sh
elixir -e 'labels = [" wake:15m ", "wake:1h", "Wake:4H", "WAKE:1D"]; labels |> Enum.map(&(String.trim(&1) |> String.downcase())) |> IO.inspect(label: "normalized_labels")'
```

Observed fixture output:

```json
["wake:15m", "wake:1h", "wake:4h", "wake:1d"]
```

Cost notes:

- The same bounded `labels.nodes.name` selection is already in the current poll
  query.
- The exact `wake:*` labels are data values, not special schema fields.
- The ABC team label check returned no existing wake-label definitions, so no
  live issue could carry those exact labels without a setup mutation.

Result: pass for field shape and normalization mechanics, with setup note that
the four wake labels do not currently exist on the ABC team.

## Blocker Relations

Exact selection:

```graphql
query BlockerRelationVisibility($id: String!) {
  issue(id: $id) {
    id
    identifier
    state {
      name
    }
    inverseRelations(first: 10) {
      nodes {
        type
        issue {
          id
          identifier
          state {
            name
          }
          labels(first: 20) {
            nodes {
              name
            }
          }
        }
      }
    }
    relations(first: 10) {
      nodes {
        type
        relatedIssue {
          id
          identifier
          state {
            name
          }
        }
      }
    }
  }
}
```

Variables:

```json
{ "id": "ABC-247" }
```

Observed response shape:

```json
{
  "issue": {
    "id": "caf90539-9b32-4d7a-a38e-dc05ae5c1066",
    "identifier": "ABC-247",
    "state": { "name": "Todo" },
    "inverseRelations": {
      "nodes": [
        {
          "type": "blocks",
          "issue": {
            "id": "936be26b-bdd7-420a-8e4b-25534d676ec0",
            "identifier": "ABC-246",
            "state": { "name": "Waiting for CI" },
            "labels": {
              "nodes": [{ "name": "yellow" }]
            }
          }
        }
      ]
    },
    "relations": {
      "nodes": [
        {
          "type": "blocks",
          "relatedIssue": {
            "id": "6ac8f5ab-7908-4033-8b71-fff477abce0a",
            "identifier": "ABC-229",
            "state": { "name": "Todo" }
          }
        }
      ]
    }
  }
}
```

Cost notes:

- The current client already uses `inverseRelations(first: relationFirst)` and
  filters `type == "blocks"` to derive `blocked_by`.
- The tested relation page size was `first: 10`; current code uses
  `@issue_page_size` for relation pagination bounds.
- Daemon dormancy needs direct blocker state, not transitive blockers.

Result: pass. For a sleeping daemon, direct incomplete blockers are visible
through the same `inverseRelations` direction current code already consumes.

## `commentUpdate` Schema

Exact introspection selection:

```graphql
query CommentUpdateShape {
  mutationType: __type(name: "Mutation") {
    fields {
      name
      args {
        name
        type {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
            }
          }
        }
      }
      type {
        kind
        name
        ofType {
          kind
          name
        }
      }
    }
  }
  commentUpdateInput: __type(name: "CommentUpdateInput") {
    inputFields {
      name
      type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
          }
        }
      }
    }
  }
  commentPayload: __type(name: "CommentPayload") {
    fields {
      name
      type {
        kind
        name
        ofType {
          kind
          name
        }
      }
    }
  }
}
```

Filtered observed response shape:

```json
{
  "commentUpdate": {
    "name": "commentUpdate",
    "args": [
      { "name": "skipEditedAt", "type": "Boolean" },
      { "name": "input", "type": "CommentUpdateInput!" },
      { "name": "id", "type": "String!" }
    ],
    "type": "CommentPayload!"
  },
  "commentUpdateInput": {
    "inputFields": [
      { "name": "body", "type": "String" },
      { "name": "bodyData", "type": "JSON" },
      { "name": "resolvingUserId", "type": "String" },
      { "name": "resolvingCommentId", "type": "String" },
      { "name": "quotedText", "type": "String" },
      { "name": "subscriberIds", "type": "[String!]" },
      { "name": "doNotSubscribeToIssue", "type": "Boolean" }
    ]
  },
  "commentPayload": {
    "fields": [
      { "name": "lastSyncId", "type": "Float!" },
      { "name": "comment", "type": "Comment!" },
      { "name": "success", "type": "Boolean!" }
    ]
  }
}
```

Safe implementation mutation shape implied by introspection:

```graphql
mutation UpdateCommentBody($id: String!, $body: String!) {
  commentUpdate(id: $id, input: { body: $body }) {
    success
    comment {
      id
      updatedAt
    }
  }
}
```

Cost notes:

- Introspection is development-time verification only and should not be in the
  daemon poll path.
- The implementation mutation is one comment id plus one input object.
- The workflow workpad update on `ABC-281` used this mutation shape and returned
  `success: true` with comment id `f1e4bc22-a42d-4a70-a3e8-44215ea6bf8f`.
- No daemon target comment was edited.

Result: pass.

## Blockers And Follow-Up Notes

- No missing Linear GraphQL field was found.
- No required mutation was unavailable.
- The poll-shaped metadata query succeeded at current client page bounds for
  the live daemon-maturity candidate set; comment bodies can stay on the narrow
  id lookup path.
- The four `wake:*` labels are not currently defined on the ABC team. This is a
  setup note, not a schema blocker.
- Current fork code still lacks comment read normalization and a `commentUpdate`
  adapter wrapper. That is expected and belongs to the follow-up implementation
  ticket for Linear comment reads and updates.

## Validation

- `npx prettier --check docs/symphony-plans/daemon-maturity-daemon-linear-verification.md`
  - passed.
- Live Linear GraphQL verification - passed against `ABC-281`,
  `daemon-maturity` poll-shaped candidate set, and `ABC-247` / `ABC-246`; no
  disposable issue created.
- `elixir -e 'labels = [" wake:15m ", "wake:1h", "Wake:4H", "WAKE:1D"]; labels |> Enum.map(&(String.trim(&1) |> String.downcase())) |> IO.inspect(label: "normalized_labels")'`
  - passed, output `["wake:15m", "wake:1h", "wake:4h", "wake:1d"]`.
