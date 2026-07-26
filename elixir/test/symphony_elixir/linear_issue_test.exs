defmodule SymphonyElixir.LinearIssueTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Linear.Issue

  test "normalize_blocker_ref accepts string and atom keyed shapes with labels" do
    assert Issue.normalize_blocker_ref(%{
             "id" => "blocker-1",
             "identifier" => "ABC-100",
             "state" => %{"name" => "In Progress"},
             "labels" => %{"nodes" => [%{"name" => " Mature "}, %{"name" => "Pink"}]}
           }) == %{
             id: "blocker-1",
             identifier: "ABC-100",
             state: "In Progress",
             labels: ["mature", "pink"]
           }

    assert Issue.normalize_blocker_ref(%{
             id: "blocker-2",
             identifier: "ABC-101",
             state: %{name: "Review"},
             labels: %{nodes: [%{name: " Ready "}, "Mature"]}
           }) == %{
             id: "blocker-2",
             identifier: "ABC-101",
             state: "Review",
             labels: ["ready", "mature"]
           }
  end

  test "normalize_blocker_ref tolerates missing and empty label shapes" do
    assert Issue.normalize_blocker_ref(%{id: "blocker-1", state: "Done"}) == %{
             id: "blocker-1",
             identifier: nil,
             state: "Done",
             labels: []
           }

    assert Issue.normalize_blocker_ref(%{"labels" => %{"nodes" => []}}).labels == []
    assert Issue.normalize_blocker_ref(%{state: %{}}).state == nil
  end

  test "normalize_comment_ref keeps id and parses supported updatedAt values" do
    updated_at = ~U[2026-07-25 17:35:21.968Z]

    assert Issue.normalize_comment_ref(%{"id" => "comment-1", "updatedAt" => "2026-07-25T17:35:21.968Z"}) ==
             %{id: "comment-1", updated_at: updated_at}

    assert Issue.normalize_comment_ref(%{id: "comment-2", updated_at: updated_at}) ==
             %{id: "comment-2", updated_at: updated_at}
  end

  test "normalize_comment_ref tolerates missing and malformed updatedAt values" do
    assert Issue.normalize_comment_ref(%{id: "comment-3"}).updated_at == nil
    assert Issue.normalize_comment_ref(%{id: "comment-4", updated_at: nil}).updated_at == nil
    assert Issue.normalize_comment_ref(%{id: "comment-5", updated_at: "not a timestamp"}).updated_at == nil
    assert Issue.normalize_comment_ref(%{id: "comment-6", updated_at: 123}).updated_at == nil
  end

  test "normalize_labels accepts Linear node maps and bare label lists" do
    assert Issue.normalize_labels(%{"nodes" => [%{"name" => " Pink "}, %{"name" => "PINK"}]}) == ["pink"]
    assert Issue.normalize_labels(%{nodes: [%{name: " Mature "}, " Ready ", nil]}) == ["mature", "ready"]
    assert Issue.normalize_labels([" Wake:15M ", %{name: "pink"}, %{"name" => " "}, 123]) == ["wake:15m", "pink"]
    assert Issue.normalize_labels(:not_labels) == []
  end

  test "label helpers and workpad title expose the shared Linear vocabulary" do
    issue = %Issue{labels: ["backend", "pink"]}

    assert Issue.label_names(issue) == ["backend", "pink"]
    assert Issue.routable?(issue, [" Backend ", "PINK"])
    refute Issue.routable?(issue, ["missing"])
    refute Issue.routable?(%Issue{issue | assigned_to_worker: false}, ["backend"])
    assert Issue.workpad_title() == "## Symphony Workpad"
  end
end
