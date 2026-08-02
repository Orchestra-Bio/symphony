defmodule SymphonyElixir.OrchestratorMaturityGateTest do
  use SymphonyElixir.TestSupport

  setup do
    write_maturity_workflow!()
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    :ok
  end

  test "candidate selection uses default Todo maturity gate scope" do
    immature_blocker = blocker(id: "blocker-immature", state: "In Review")
    mature_blocker = %{immature_blocker | labels: ["mature"]}

    refute Orchestrator.should_dispatch_issue_for_test(
             issue(id: "todo-gated", state: "Todo", blocked_by: [immature_blocker]),
             state()
           )

    assert Orchestrator.should_dispatch_issue_for_test(
             issue(id: "todo-mature", state: "Todo", blocked_by: [mature_blocker]),
             state()
           )

    assert Orchestrator.should_dispatch_issue_for_test(
             issue(id: "progress-default-scope", state: "In Progress", blocked_by: [immature_blocker]),
             state()
           )
  end

  test "candidate selection gates explicitly widened states" do
    write_maturity_workflow!(maturity_gate_state_scope: ["todo", "in progress"])

    immature_blocker = blocker(id: "blocker-immature", state: "In Review")
    mature_blocker = %{immature_blocker | labels: ["mature"]}

    refute Orchestrator.should_dispatch_issue_for_test(
             issue(id: "progress-gated", state: "In Progress", blocked_by: [immature_blocker]),
             state()
           )

    assert Orchestrator.should_dispatch_issue_for_test(
             issue(id: "progress-mature", state: "In Progress", blocked_by: [mature_blocker]),
             state()
           )
  end

  test "candidate selection ignores daemon-state blockers with a warning" do
    daemon_blocker = blocker(id: "daemon-blocker", identifier: "ABC-DAEMON", state: "Happy")

    log =
      capture_log(fn ->
        assert Orchestrator.should_dispatch_issue_for_test(
                 issue(id: "daemon-dependent", blocked_by: [daemon_blocker]),
                 state()
               )
      end)

    assert log =~ "Ignoring daemon-state blocker in maturity gate"
    assert log =~ "ABC-DAEMON"
  end

  test "retry lookup uses the shared maturity gate" do
    issue_id = "retry-dependent"
    immature = issue(id: issue_id, identifier: "ABC-RETRY", blocked_by: [blocker(state: "In Review")])
    mature = %{immature | blocked_by: [blocker(state: "In Review", labels: ["mature"])]}

    claimed_state = state(%{max_concurrent_agents: 0, claimed: MapSet.new([issue_id])})

    released = Orchestrator.handle_retry_issue_lookup_for_test(immature, claimed_state, issue_id, 1, metadata(immature))

    refute MapSet.member?(released.claimed, issue_id)
    refute Map.has_key?(released.retry_attempts, issue_id)

    retained = Orchestrator.handle_retry_issue_lookup_for_test(mature, claimed_state, issue_id, 1, metadata(mature))

    assert MapSet.member?(retained.claimed, issue_id)

    assert %{attempt: 2, identifier: "ABC-RETRY", error: "no available orchestrator slots"} =
             retained.retry_attempts[issue_id]
  end

  test "dispatch-time revalidation uses the shared maturity gate" do
    issue_id = "dispatch-dependent"
    initial = issue(id: issue_id, blocked_by: [blocker(state: "In Review", labels: ["mature"])])
    regressed = %{initial | blocked_by: [blocker(state: "In Review", labels: [])]}

    assert {:ok, ^initial} =
             Orchestrator.revalidate_issue_for_dispatch_for_test(initial, fn [^issue_id] ->
               {:ok, [initial]}
             end)

    assert {:skip, ^regressed} =
             Orchestrator.revalidate_issue_for_dispatch_for_test(initial, fn [^issue_id] ->
               {:ok, [regressed]}
             end)
  end

  test "todo dependent with mature waiting-for-ci blocker is dispatch-eligible" do
    write_maturity_workflow!(maturity_gate_state_scope: ["Todo", "Active"])

    mature_blocker = blocker(id: "blocker-mature", state: "Waiting for CI", labels: ["mature"])
    immature_blocker = %{mature_blocker | labels: []}

    assert Orchestrator.should_dispatch_issue_for_test(
             issue(id: "todo-mature-waiting", state: "Todo", blocked_by: [mature_blocker]),
             state()
           )

    refute Orchestrator.should_dispatch_issue_for_test(
             issue(id: "todo-immature-waiting", state: "Todo", blocked_by: [immature_blocker]),
             state()
           )
  end

  test "fan-out retry releases immature dependent and removes pre-session stale workspace" do
    workspace_root =
      Path.join(System.tmp_dir!(), "symphony-maturity-fanout-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(workspace_root) end)

    write_maturity_workflow!(workspace_root: workspace_root)

    issue_id = "fanout-dependent"
    issue_identifier = "ABC-FANOUT"
    stale_workspace = Path.join(workspace_root, issue_identifier)
    File.mkdir_p!(stale_workspace)
    File.write!(Path.join(stale_workspace, "partial-clone"), "partial")

    immature_blocker = blocker(id: "blocker-fanout", state: "Waiting for CI", labels: [])
    mature_blocker = %{immature_blocker | labels: ["mature"]}
    immature = issue(id: issue_id, identifier: issue_identifier, blocked_by: [immature_blocker])
    mature = %{immature | blocked_by: [mature_blocker]}

    claimed_state =
      state(%{
        claimed: MapSet.new([issue_id]),
        retry_attempts: %{issue_id => %{attempt: 1}}
      })

    released =
      Orchestrator.handle_retry_issue_lookup_for_test(immature, claimed_state, issue_id, 1, %{
        identifier: issue_identifier,
        issue_url: immature.url,
        error: "workspace hook timed out",
        worker_host: nil,
        workspace_path: nil
      })

    refute MapSet.member?(released.claimed, issue_id)
    refute Map.has_key?(released.retry_attempts, issue_id)
    refute File.exists?(stale_workspace)
    assert Orchestrator.should_dispatch_issue_for_test(mature, released)
  end

  test "regression advisory is emitted once per observed transition without killing the worker" do
    issue_id = "running-dependent"
    blocker_mature = blocker(id: "blocker", identifier: "ABC-BLOCKER", state: "In Review", labels: ["mature"])
    blocker_regressed = %{blocker_mature | labels: []}
    agent_pid = sleeping_process()

    previous_issue = issue(id: issue_id, identifier: "ABC-RUNNING", blocked_by: [blocker_mature])
    refreshed_issue = %{previous_issue | blocked_by: [blocker_regressed]}
    eligible_again = %{previous_issue | blocked_by: [blocker_mature]}

    running_state =
      state(%{
        running: %{issue_id => running_entry(previous_issue, agent_pid)},
        claimed: MapSet.new([issue_id])
      })

    first_regression = Orchestrator.reconcile_issue_states_for_test([refreshed_issue], running_state)

    assert_receive {:memory_tracker_comment, ^issue_id, body}, 1_000
    assert body =~ "## Maturity Regression Advisory"
    assert body =~ "ABC-BLOCKER"
    assert body =~ "left running"
    assert Process.alive?(agent_pid)
    assert Map.has_key?(first_regression.running, issue_id)
    assert MapSet.member?(first_regression.claimed, issue_id)

    duplicate_poll = Orchestrator.reconcile_issue_states_for_test([refreshed_issue], first_regression)
    refute_receive {:memory_tracker_comment, ^issue_id, _body}, 50

    eligible_poll = Orchestrator.reconcile_issue_states_for_test([eligible_again], duplicate_poll)
    refute_receive {:memory_tracker_comment, ^issue_id, _body}, 50

    second_regression = Orchestrator.reconcile_issue_states_for_test([refreshed_issue], eligible_poll)
    assert_receive {:memory_tracker_comment, ^issue_id, second_body}, 1_000
    assert second_body =~ "ABC-BLOCKER"
    assert Process.alive?(agent_pid)
    assert Map.has_key?(second_regression.running, issue_id)

    send(agent_pid, :stop)
  end

  defp write_maturity_workflow!(opts \\ []) do
    maturity_labels = Keyword.get(opts, :maturity_labels, ["mature"])
    maturity_gate_state_scope = Keyword.get(opts, :maturity_gate_state_scope, ["todo"])
    workspace_root = Keyword.get(opts, :workspace_root, Path.join(System.tmp_dir!(), "symphony_workspaces"))

    workflow = """
    ---
    tracker:
      kind: memory
      active_states: ["Todo", "In Progress", "Evaluating"]
      terminal_states: ["Done", "Canceled"]
      daemon_states: ["Happy", "Unhappy"]
      daemon_dispatch_states: ["Evaluating"]
      daemon_default_wake: "1h"
      maturity_labels: #{yaml_value(maturity_labels)}
      maturity_gate_state_scope: #{yaml_value(maturity_gate_state_scope)}
    workspace:
      root: #{yaml_value(workspace_root)}
    agent:
      max_concurrent_agents: 3
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

  defp issue(overrides) do
    defaults = %{
      id: "dependent",
      identifier: "ABC-DEPENDENT",
      title: "Dependent",
      state: "Todo",
      url: "https://linear.example/ABC-DEPENDENT",
      labels: [],
      blocked_by: [],
      comments: [%{id: "workpad", updated_at: ~U[2026-07-27 08:00:00Z]}],
      created_at: ~U[2026-07-27 08:00:00Z],
      updated_at: ~U[2026-07-27 08:00:00Z]
    }

    struct(Issue, Map.merge(defaults, Map.new(overrides)))
  end

  defp blocker(overrides) do
    defaults = %{
      id: "blocker",
      identifier: "ABC-BLOCKER",
      state: "In Progress",
      labels: []
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp metadata(%Issue{} = issue) do
    %{identifier: issue.identifier, issue_url: issue.url, error: "agent exited"}
  end

  defp running_entry(%Issue{} = issue, pid) when is_pid(pid) do
    %{
      pid: pid,
      ref: nil,
      identifier: issue.identifier,
      issue: issue,
      worker_host: nil,
      workspace_path: nil,
      session_id: nil,
      started_at: DateTime.utc_now()
    }
  end

  defp sleeping_process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp yaml_value(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &inspect/1) <> "]"
  end

  defp yaml_value(value) when is_binary(value), do: inspect(value)
end
