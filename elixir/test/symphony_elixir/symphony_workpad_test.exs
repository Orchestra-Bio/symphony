defmodule SymphonyElixir.SymphonyWorkpadTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.SymphonyWorkpad

  setup do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    :ok
  end

  test "ensure_created creates the New workpad only when the filtered anchor is absent" do
    assert {:ok, :created} =
             SymphonyWorkpad.ensure_created(issue(%{id: "issue-new", comments: []}))

    assert_receive {:memory_tracker_comment, "issue-new", "## Symphony Workpad\nNew"}

    assert {:ok, :existing} =
             SymphonyWorkpad.ensure_created(issue(%{id: "issue-existing", comments: [comment("comment-1", ~U[2026-07-26 15:00:00Z])]}))

    refute_receive {:memory_tracker_comment, "issue-existing", _body}, 50
  end

  test "record_last_run updates the newest filtered workpad comment in place" do
    workpad_issue =
      issue(%{
        comments: [
          comment("comment-old", ~U[2026-07-26 14:00:00Z]),
          comment("comment-new", ~U[2026-07-26 15:00:00Z])
        ]
      })

    assert {:ok, ~U[2026-07-26 15:00:00Z]} = SymphonyWorkpad.anchor_updated_at(workpad_issue)

    assert :ok =
             SymphonyWorkpad.record_last_run(workpad_issue, ~U[2026-07-26 15:42:07.987Z])

    assert_receive {:memory_tracker_comment_update, "comment-new", "## Symphony Workpad\nLast run 2026-07-26T15:42:07Z"}

    refute_receive {:memory_tracker_comment, _issue_id, _body}, 50
  end

  test "record_last_run fails closed when the poll did not return an anchor id" do
    assert {:error, :missing_workpad_anchor} =
             SymphonyWorkpad.record_last_run(issue(%{comments: []}), ~U[2026-07-26 15:42:07Z])

    refute_receive {:memory_tracker_comment_update, _comment_id, _body}, 50
    refute_receive {:memory_tracker_comment, _issue_id, _body}, 50
  end

  test "orchestrator creates a missing workpad from the candidate poll before dispatch" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      poll_interval_ms: 60_000
    )

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [
      issue(%{id: "issue-create", identifier: "ABC-298", title: "Create workpad", comments: []})
    ])

    {:ok, pid} = Orchestrator.start_link(name: Module.concat(__MODULE__, :CreateWorkpadOrchestrator))
    stop_on_exit(pid)

    assert_receive {:memory_tracker_comment, "issue-create", "## Symphony Workpad\nNew"}, 1_000
    refute_receive {:memory_tracker_comment, "issue-create", _body}, 100
  end

  test "orchestrator records Last run for successful and failed agent exits" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      poll_interval_ms: 60_000
    )

    {:ok, pid} = Orchestrator.start_link(name: Module.concat(__MODULE__, :LastRunOrchestrator))
    stop_on_exit(pid)

    normal_ref = make_ref()
    failed_ref = make_ref()

    normal_issue =
      issue(%{
        id: "issue-normal",
        identifier: "ABC-299",
        comments: [comment("comment-normal", ~U[2026-07-26 15:00:00Z])]
      })

    failed_issue =
      issue(%{
        id: "issue-failed",
        identifier: "ABC-300",
        comments: [comment("comment-failed", ~U[2026-07-26 15:00:00Z])]
      })

    :sys.replace_state(pid, fn state ->
      %{
        state
        | running: %{
            normal_issue.id => running_entry(normal_issue, normal_ref),
            failed_issue.id => running_entry(failed_issue, failed_ref)
          },
          claimed: MapSet.new([normal_issue.id, failed_issue.id])
      }
    end)

    send(pid, {:DOWN, normal_ref, :process, self(), :normal})
    assert_receive {:memory_tracker_comment_update, "comment-normal", normal_body}, 1_000
    assert last_run_body?(normal_body)

    send(pid, {:DOWN, failed_ref, :process, self(), :shutdown})
    assert_receive {:memory_tracker_comment_update, "comment-failed", failed_body}, 1_000
    assert last_run_body?(failed_body)
  end

  defp issue(attrs) do
    defaults = %{
      id: "issue-1",
      identifier: "ABC-1",
      title: "Workpad ticket",
      description: "Exercise Symphony workpad writes",
      state: "Todo",
      url: "https://linear.example/ABC-1",
      comments: [],
      created_at: ~U[2026-07-26 14:00:00Z]
    }

    struct(Issue, Map.merge(defaults, attrs))
  end

  defp comment(id, updated_at), do: %{id: id, updated_at: updated_at}

  defp running_entry(%Issue{} = issue, ref) do
    %{
      pid: self(),
      ref: ref,
      identifier: issue.identifier,
      issue: issue,
      worker_host: nil,
      workspace_path: nil,
      session_id: nil,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      started_at: DateTime.utc_now()
    }
  end

  defp last_run_body?(body) when is_binary(body) do
    Regex.match?(~r/\A## Symphony Workpad\nLast run \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body)
  end

  defp stop_on_exit(pid) when is_pid(pid) do
    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
  end
end
