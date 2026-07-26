defmodule SymphonyElixir.LinearAdapterCommentUpdateTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.Adapter

  defmodule FakeLinearClient do
    def fetch_candidate_issues, do: {:ok, []}
    def fetch_issues_by_states(_states), do: {:ok, []}
    def fetch_issue_states_by_ids(_issue_ids), do: {:ok, []}
    def fetch_comment_body(comment_id), do: {:ok, "body for #{comment_id}"}

    def graphql(query, variables) do
      send(self(), {:graphql_called, query, variables})

      case Process.get({__MODULE__, :graphql_results}) do
        [result | rest] ->
          Process.put({__MODULE__, :graphql_results}, rest)
          result

        _ ->
          Process.get({__MODULE__, :graphql_result})
      end
    end
  end

  setup do
    Application.put_env(:symphony_elixir, :linear_client_module, FakeLinearClient)
    :ok
  end

  test "commentUpdate succeeds and commentCreate still uses its existing mutation" do
    Process.put(
      {FakeLinearClient, :graphql_results},
      [
        {:ok, %{"data" => %{"commentUpdate" => %{"success" => true}}}},
        {:ok, %{"data" => %{"commentCreate" => %{"success" => true}}}}
      ]
    )

    assert :ok = Adapter.update_comment("comment-1", "updated body")

    assert_receive {:graphql_called, update_query, %{body: "updated body", commentId: "comment-1"}}
    assert update_query =~ "commentUpdate"
    assert update_query =~ "updatedAt"
    refute update_query =~ "commentCreate"

    assert :ok = Adapter.create_comment("issue-1", "new body")

    assert_receive {:graphql_called, create_query, %{body: "new body", issueId: "issue-1"}}
    assert create_query =~ "commentCreate"
    refute create_query =~ "commentUpdate"
  end

  test "commentUpdate reports Linear failure responses" do
    Process.put(
      {FakeLinearClient, :graphql_result},
      {:ok, %{"data" => %{"commentUpdate" => %{"success" => false}}}}
    )

    assert {:error, :comment_update_failed} = Adapter.update_comment("comment-1", "broken")
  end

  test "commentUpdate passes through client errors" do
    Process.put({FakeLinearClient, :graphql_result}, {:error, :boom})

    assert {:error, :boom} = Adapter.update_comment("comment-1", "boom")
  end

  test "commentUpdate rejects malformed payloads" do
    Process.put({FakeLinearClient, :graphql_result}, {:ok, %{"data" => %{}}})
    assert {:error, :comment_update_failed} = Adapter.update_comment("comment-1", "weird")

    Process.put({FakeLinearClient, :graphql_result}, :unexpected)
    assert {:error, :comment_update_failed} = Adapter.update_comment("comment-1", "odd")
  end
end
