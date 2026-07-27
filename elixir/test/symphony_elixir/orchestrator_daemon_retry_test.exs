defmodule SymphonyElixir.OrchestratorDaemonRetryTest do
  use SymphonyElixir.TestSupport

  setup do
    write_daemon_workflow!()
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    :ok
  end

  test "crash during daemon evaluation uses active retry before exhaustion" do
    issue_id = "daemon-retry"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :DaemonActiveRetryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
    stop_on_exit(pid)

    running_issue =
      issue(%{
        id: issue_id,
        identifier: "ABC-288-RETRY",
        state: "Evaluating",
        comments: [comment("workpad-retry", ~U[2026-07-26 15:00:00Z])]
      })

    :sys.replace_state(pid, fn state ->
      %{
        state
        | running: %{issue_id => running_entry(running_issue, ref, retry_attempt: 2)},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{}
      }
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})

    assert_receive {:memory_tracker_comment_update, "workpad-retry", body}, 1_000
    assert String.starts_with?(body, "## Symphony Workpad\nLast run ")

    Process.sleep(50)

    assert %{
             attempt: 3,
             identifier: "ABC-288-RETRY",
             error: "agent exited: :boom"
           } = :sys.get_state(pid).retry_attempts[issue_id]

    refute_receive {:memory_tracker_state_update, ^issue_id, _state}, 50
  end

  test "finite daemon retry exhaustion restores the state named by issue history" do
    issue_id = "daemon-exhausted"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :DaemonExhaustionOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
    stop_on_exit(pid)

    Application.put_env(:symphony_elixir, :memory_tracker_issue_history, %{
      issue_id => [
        %{created_at: ~U[2026-07-26 15:03:00Z], from_state: "Human Input Needed", to_state: "Rework"},
        %{created_at: ~U[2026-07-26 15:01:00Z], from_state: "Unhappy", to_state: "Evaluating"},
        %{created_at: ~U[2026-07-26 15:02:00Z], from_state: "Happy", to_state: "Legacy Evaluating"}
      ]
    })

    running_issue =
      issue(%{
        id: issue_id,
        identifier: "ABC-288-EXHAUSTED",
        state: "Legacy Evaluating",
        comments: [comment("workpad-exhausted", ~U[2026-07-26 15:00:00Z])]
      })

    :sys.replace_state(pid, fn state ->
      %{
        state
        | running: %{issue_id => running_entry(running_issue, ref, retry_attempt: 3)},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{}
      }
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})

    assert_receive {:memory_tracker_comment_update, "workpad-exhausted", body}, 1_000
    assert String.starts_with?(body, "## Symphony Workpad\nLast run ")
    assert_receive {:memory_tracker_state_update, ^issue_id, "Happy"}, 1_000
    refute_receive {:memory_tracker_comment, ^issue_id, _body}, 50

    state = :sys.get_state(pid)
    refute Map.has_key?(state.retry_attempts, issue_id)
    refute MapSet.member?(state.claimed, issue_id)

    assert :ok = Tracker.update_issue_state(issue_id, "Unhappy")
    assert_receive {:memory_tracker_state_update, ^issue_id, "Unhappy"}
  end

  test "daemon exhaustion without a lease transition leaves dispatch state without guessing" do
    issue_id = "daemon-missing-history"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :DaemonUnknownPreLeaseOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
    stop_on_exit(pid)

    Application.put_env(:symphony_elixir, :memory_tracker_issue_history, %{
      issue_id => [
        %{created_at: ~U[2026-07-26 15:02:00Z], from_state: "Human Input Needed", to_state: "Rework"}
      ]
    })

    running_issue =
      issue(%{
        id: issue_id,
        identifier: "ABC-288-MISSING-HISTORY",
        state: "Evaluating",
        comments: [comment("workpad-missing-history", ~U[2026-07-26 15:00:00Z])]
      })

    :sys.replace_state(pid, fn state ->
      %{
        state
        | running: %{issue_id => running_entry(running_issue, ref, retry_attempt: 3)},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{}
      }
    end)

    log =
      capture_log(fn ->
        send(pid, {:DOWN, ref, :process, self(), :boom})

        assert_receive {:memory_tracker_comment_update, "workpad-missing-history", body}, 1_000
        assert String.starts_with?(body, "## Symphony Workpad\nLast run ")

        Process.sleep(50)
      end)

    assert log =~ "no matching lease transition"
    refute_receive {:memory_tracker_state_update, ^issue_id, _state}, 50

    state = :sys.get_state(pid)
    refute Map.has_key?(state.retry_attempts, issue_id)
    assert MapSet.member?(state.claimed, issue_id)
  end

  test "normal tickets keep retrying after the daemon exhaustion boundary" do
    issue_id = "normal-retry"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :NormalRetryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
    stop_on_exit(pid)

    running_issue =
      issue(%{
        id: issue_id,
        identifier: "ABC-288-NORMAL",
        state: "Todo",
        comments: [comment("workpad-normal", ~U[2026-07-26 15:00:00Z])]
      })

    :sys.replace_state(pid, fn state ->
      %{
        state
        | running: %{issue_id => running_entry(running_issue, ref, retry_attempt: 3)},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{}
      }
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})

    assert_receive {:memory_tracker_comment_update, "workpad-normal", _body}, 1_000
    Process.sleep(50)

    assert %{attempt: 4, identifier: "ABC-288-NORMAL"} = :sys.get_state(pid).retry_attempts[issue_id]
    refute_receive {:memory_tracker_state_update, ^issue_id, _state}, 50
  end

  defp write_daemon_workflow! do
    workflow = """
    ---
    tracker:
      kind: memory
      active_states: ["Todo", "Evaluating", "Legacy Evaluating"]
      terminal_states: ["Done", "Canceled"]
      daemon_states: ["Happy", "Unhappy"]
      daemon_dispatch_states: ["Evaluating", "Legacy Evaluating"]
      daemon_default_wake: "1h"
    agent:
      max_concurrent_agents: 3
      max_concurrent_agents_by_state: {"evaluating": 2, "legacy evaluating": 2}
    polling:
      interval_ms: 60000
    ---
    You are an agent for this repository.
    """

    File.write!(Workflow.workflow_file_path(), workflow)
    WorkflowStore.force_reload()
  end

  defp issue(attrs) do
    defaults = %{
      id: "issue-1",
      identifier: "ABC-288",
      title: "Daemon retry",
      state: "Todo",
      url: "https://linear.example/ABC-288",
      labels: [],
      blocked_by: [],
      comments: [comment("workpad-1", ~U[2026-07-26 08:00:00Z])],
      created_at: ~U[2026-07-26 08:00:00Z],
      updated_at: ~U[2026-07-26 08:00:00Z]
    }

    struct(Issue, Map.merge(defaults, attrs))
  end

  defp comment(id, updated_at), do: %{id: id, updated_at: updated_at}

  defp running_entry(%Issue{} = issue, ref, opts) do
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
      started_at: DateTime.utc_now(),
      retry_attempt: Keyword.fetch!(opts, :retry_attempt)
    }
  end

  defp stop_on_exit(pid) when is_pid(pid) do
    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
  end
end
