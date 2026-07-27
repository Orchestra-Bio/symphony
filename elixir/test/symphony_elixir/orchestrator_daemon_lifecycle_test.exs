defmodule SymphonyElixir.OrchestratorDaemonLifecycleTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Config.Schema

  setup do
    write_daemon_workflow!()
    :ok
  end

  test "sleeping daemon is skipped and comments do not wake it" do
    daemon =
      issue(%{
        id: "daemon-sleep",
        identifier: "ABC-288-SLEEP",
        state: "Happy",
        labels: ["wake:1h"],
        comments: [comment("workpad-sleep", ~U[2026-07-26 09:00:00Z])],
        updated_at: ~U[2026-07-26 09:59:00Z]
      })

    assert {:ok, []} =
             Orchestrator.append_due_daemon_candidates_for_test(
               [],
               state(),
               ~U[2026-07-26 09:30:00Z],
               fetch_issues_by_states: fn ["happy", "unhappy"] -> {:ok, [daemon]} end,
               update_issue_state: fn issue_id, state_name ->
                 send(self(), {:unexpected_lease, issue_id, state_name})
                 :ok
               end
             )

    refute_receive {:unexpected_lease, _, _}, 50
  end

  test "due daemon is leased to the first configured dispatch state and refetched" do
    daemon =
      issue(%{
        id: "daemon-due",
        identifier: "ABC-288-DUE",
        state: "Unhappy",
        labels: ["wake:1h"],
        comments: [comment("workpad-due", ~U[2026-07-26 09:00:00Z])]
      })

    leased = %{daemon | state: "Evaluating"}

    assert {:ok, [^leased], updated_state} =
             Orchestrator.append_due_daemon_candidates_with_state_for_test(
               [],
               state(),
               ~U[2026-07-26 10:02:00Z],
               fetch_issues_by_states: fn ["happy", "unhappy"] -> {:ok, [daemon]} end,
               update_issue_state: fn "daemon-due", "Evaluating" ->
                 send(self(), {:leased, "daemon-due", "Evaluating"})
                 :ok
               end,
               fetch_issue_states_by_ids: fn ["daemon-due"] -> {:ok, [leased]} end
             )

    assert_receive {:leased, "daemon-due", "Evaluating"}
    assert updated_state.running == %{}
  end

  test "daemon sleep candidates create missing workpad anchors before wake evaluation" do
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    daemon =
      issue(%{
        id: "daemon-new-anchor",
        identifier: "ABC-288-ANCHOR",
        state: "Happy",
        labels: ["wake:1h"],
        comments: [],
        created_at: ~U[2026-07-26 08:00:00Z]
      })

    assert {:ok, []} =
             Orchestrator.append_due_daemon_candidates_for_test(
               [],
               state(),
               ~U[2026-07-26 10:00:00Z],
               fetch_issues_by_states: fn ["happy", "unhappy"] -> {:ok, [daemon]} end,
               update_issue_state: fn issue_id, state_name ->
                 send(self(), {:unexpected_lease, issue_id, state_name})
                 :ok
               end
             )

    assert_receive {:memory_tracker_comment, "daemon-new-anchor", "## Symphony Workpad\nNew"}
    refute_receive {:unexpected_lease, _, _}, 50
  end

  test "daemon in any configured dispatch state is dispatchable for crash recovery" do
    recovery_issue =
      issue(%{
        id: "daemon-recover",
        identifier: "ABC-288-RECOVER",
        state: "Legacy Evaluating"
      })

    assert Orchestrator.should_dispatch_issue_for_test(recovery_issue, state())
  end

  test "daemon dispatch occupancy uses per-state running counts" do
    write_daemon_workflow!(max_concurrent_agents_by_state: %{"evaluating" => 1})

    running_daemon =
      issue(%{
        id: "daemon-running",
        identifier: "ABC-288-RUNNING",
        state: "Evaluating"
      })

    evaluating_candidate =
      issue(%{
        id: "daemon-candidate",
        identifier: "ABC-288-CANDIDATE",
        state: "Evaluating"
      })

    todo_candidate =
      issue(%{
        id: "normal-candidate",
        identifier: "ABC-288-NORMAL",
        state: "Todo"
      })

    state =
      state(%{
        running: %{
          running_daemon.id => %{issue: running_daemon}
        }
      })

    refute Orchestrator.should_dispatch_issue_for_test(evaluating_candidate, state)
    assert Orchestrator.should_dispatch_issue_for_test(todo_candidate, state)
  end

  test "normal tickets without daemon config behave as before" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")

    active_issue =
      issue(%{
        id: "normal-ready",
        identifier: "ABC-288-READY",
        state: "Todo",
        blocked_by: [%{id: "blocker-done", identifier: "ABC-288-DONE", state: "Done"}]
      })

    assert Orchestrator.should_dispatch_issue_for_test(active_issue, state())

    assert {:ok, [^active_issue]} =
             Orchestrator.append_due_daemon_candidates_for_test(
               [active_issue],
               state(),
               ~U[2026-07-26 10:00:00Z],
               fetch_issues_by_states: fn _states ->
                 flunk("daemon sleep candidates should not be fetched without daemon config")
               end
             )
  end

  test "schema fallback helpers keep full coverage for daemon config validation" do
    assert Schema.normalize_string_set(:not_list) == []
    assert Schema.normalize_issue_state(:todo) == "todo"

    changeset = Ecto.Changeset.change(%Schema.Tracker{})
    assert Schema.reject_config_fields(changeset, nil, ["daemon_label"]) == changeset

    tracker_changeset =
      Schema.Tracker.changeset(%Schema.Tracker{}, %{
        "active_states" => nil,
        "daemon_states" => ["Happy"],
        "daemon_dispatch_states" => ["Evaluating"]
      })

    refute tracker_changeset.valid?
    assert {:daemon_dispatch_states, {"must be listed in tracker.active_states", []}} in tracker_changeset.errors
  end

  defp write_daemon_workflow!(opts \\ []) do
    max_concurrent_agents_by_state = Keyword.get(opts, :max_concurrent_agents_by_state, %{})

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
      max_concurrent_agents_by_state: #{yaml_value(max_concurrent_agents_by_state)}
    ---
    You are an agent for this repository.
    """

    File.write!(Workflow.workflow_file_path(), workflow)
    WorkflowStore.force_reload()
  end

  defp state(overrides \\ %{}) do
    struct(
      Orchestrator.State,
      Map.merge(
        %{
          max_concurrent_agents: 3,
          running: %{},
          claimed: MapSet.new(),
          blocked: %{},
          retry_attempts: %{},
          codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0}
        },
        overrides
      )
    )
  end

  defp issue(attrs) do
    defaults = %{
      id: "issue-1",
      identifier: "ABC-288",
      title: "Daemon lifecycle",
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

  defp yaml_value(values) when is_map(values) do
    "{" <>
      Enum.map_join(values, ", ", fn {key, value} ->
        "#{inspect(to_string(key))}: #{yaml_value(value)}"
      end) <> "}"
  end

  defp yaml_value(value) when is_integer(value), do: to_string(value)
end
