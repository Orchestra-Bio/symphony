defmodule SymphonyElixir.DaemonMaturityIssueTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.Issue

  test "issue defaults preserve existing workflows when daemon fields are absent" do
    issue = %Issue{labels: ["backend"]}

    assert issue.blocked_by == []
    assert issue.comments == []
    assert Issue.label_names(issue) == ["backend"]
    assert Issue.routable?(issue, ["backend"])
  end

  test "blocker refs can carry normalized maturity labels" do
    blocker =
      Issue.normalize_blocker_ref(%{
        id: "blocker-1",
        identifier: "ABC-100",
        state: "In Progress",
        labels: [" Mature ", "READY", "mature", nil]
      })

    assert blocker == %{
             id: "blocker-1",
             identifier: "ABC-100",
             state: "In Progress",
             labels: ["mature", "ready"]
           }
  end

  test "blocker refs normalize the verified Linear nested shape" do
    blocker =
      Issue.normalize_blocker_ref(%{
        "id" => "blocker-2",
        "identifier" => "ABC-101",
        "state" => %{"name" => "Review"},
        "labels" => %{"nodes" => [%{"name" => " Mature "}, %{"name" => "Backend"}]}
      })

    assert blocker == %{
             id: "blocker-2",
             identifier: "ABC-101",
             state: "Review",
             labels: ["mature", "backend"]
           }
  end

  test "blocker refs normalize atom-keyed nested shapes" do
    blocker =
      Issue.normalize_blocker_ref(%{
        id: "blocker-3",
        identifier: "ABC-102",
        state: %{name: "Review"},
        labels: %{nodes: [%{name: " Mature "}, "Ready"]}
      })

    assert blocker == %{
             id: "blocker-3",
             identifier: "ABC-102",
             state: "Review",
             labels: ["mature", "ready"]
           }

    assert Issue.normalize_blocker_ref(%{state: %{}}).state == nil
  end

  test "workpad edited in place: updated_at is the last-run anchor, created_at is not" do
    comment =
      Issue.normalize_comment_ref(%{
        "id" => "comment-1",
        "createdAt" => "2026-07-25T16:37:19.692Z",
        "updatedAt" => "2026-07-25T17:35:21.968Z",
        "body" => "## Codex Workpad\nlarge body stays out of the steady-state metadata"
      })

    assert comment.id == "comment-1"
    assert comment.updated_at == ~U[2026-07-25 17:35:21.968Z]
    refute Map.has_key?(comment, :created_at)
    refute Map.has_key?(comment, :body)
  end

  test "comment refs tolerate missing and malformed updated_at values" do
    updated_at = ~U[2026-07-25 17:35:21.968Z]

    assert Issue.normalize_comment_ref(%{id: "comment-2", updated_at: updated_at}).updated_at == updated_at
    assert Issue.normalize_comment_ref(%{id: "comment-3", updated_at: nil}).updated_at == nil
    assert Issue.normalize_comment_ref(%{id: "comment-4", updated_at: "not a timestamp"}).updated_at == nil
    assert Issue.normalize_comment_ref(%{id: "comment-5", updated_at: 123}).updated_at == nil
  end
end
