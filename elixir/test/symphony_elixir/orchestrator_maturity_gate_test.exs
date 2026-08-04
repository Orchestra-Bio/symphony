defmodule SymphonyElixir.OrchestratorMaturityGateTest do
  use SymphonyElixir.TestSupport

  @stale_cache_age_ms 5 * 60 * 60 * 1_000

  defmodule FailingLinearClient do
    def fetch_candidate_issues, do: {:error, :rate_limited}
    def fetch_issues_by_states(_states), do: {:ok, []}
    def fetch_issue_states_by_ids(_issue_ids), do: {:ok, []}
    def fetch_issue_state_history(_issue_id, _limit), do: {:ok, []}
    def fetch_comment_body(_comment_id), do: {:error, :comment_not_found}
    def graphql(_query, _variables), do: {:error, :not_implemented}
  end

  setup do
    write_maturity_workflow!()
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    :ok
  end

  test "candidate selection uses default Todo maturity gate scope" do
    immature_blocker = blocker(id: "blocker-immature", state: "In Review")
    mature_blocker = %{immature_blocker | labels: ["mature"]}

    assert {false, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "todo-gated", state: "Todo", blocked_by: [immature_blocker]),
               state()
             )

    assert {true, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "todo-mature", state: "Todo", blocked_by: [mature_blocker]),
               state()
             )

    assert {true, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "progress-default-scope", state: "In Progress", blocked_by: [immature_blocker]),
               state()
             )
  end

  test "candidate selection gates explicitly widened states" do
    write_maturity_workflow!(maturity_gate_state_scope: ["todo", "in progress"])

    immature_blocker = blocker(id: "blocker-immature", state: "In Review")
    mature_blocker = %{immature_blocker | labels: ["mature"]}

    assert {false, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "progress-gated", state: "In Progress", blocked_by: [immature_blocker]),
               state()
             )

    assert {true, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "progress-mature", state: "In Progress", blocked_by: [mature_blocker]),
               state()
             )
  end

  test "candidate selection ignores daemon-state blockers with a warning" do
    daemon_blocker = blocker(id: "daemon-blocker", identifier: "ABC-DAEMON", state: "Happy")

    log =
      capture_log(fn ->
        assert {true, _state} =
                 Orchestrator.evaluate_dispatch_issue_for_test(
                   issue(id: "daemon-dependent", blocked_by: [daemon_blocker]),
                   state()
                 )
      end)

    assert log =~ "Ignoring daemon-state blocker in maturity gate"
    assert log =~ "ABC-DAEMON"
  end

  test "maturity gate snapshot exposes config, gated blockers, and out-of-scope ungated work" do
    terminal_blocker = blocker(id: "blocker-done", identifier: "ABC-DONE", state: "Done")
    mature_blocker = blocker(id: "blocker-mature", identifier: "ABC-MATURE", state: "In Review", labels: ["mature"])
    immature_blocker = blocker(id: "blocker-immature", identifier: "ABC-IMMATURE", state: "In Review")
    daemon_blocker = blocker(id: "blocker-daemon", identifier: "ABC-DAEMON", state: "Happy")

    gated_issue =
      issue(
        id: "gated-dependent",
        identifier: "ABC-GATED",
        title: "Gated dependent",
        state: "Todo",
        blocked_by: [terminal_blocker, mature_blocker, immature_blocker, daemon_blocker]
      )

    out_of_scope_issue =
      issue(
        id: "out-of-scope-dependent",
        identifier: "ABC-OUT",
        title: "Out of scope dependent",
        state: "In Progress",
        blocked_by: [immature_blocker]
      )

    snapshot = Orchestrator.maturity_gate_snapshot_for_test([gated_issue, out_of_scope_issue], state())

    assert snapshot.config == %{
             terminal_states: ["canceled", "done"],
             daemon_states: ["Happy", "Unhappy"],
             maturity_labels: ["mature"],
             maturity_gate_state_scope: ["todo"]
           }

    assert %DateTime{} = snapshot.evaluated_at

    assert [
             %{
               identifier: "ABC-GATED",
               title: "Gated dependent",
               state: "Todo",
               status: :gated,
               scope: :in_scope,
               blockers: gated_blockers
             }
           ] = snapshot.gated

    assert Enum.map(gated_blockers, &{&1.identifier, &1.status, &1.reasons}) == [
             {"ABC-DONE", :satisfied, [:terminal]},
             {"ABC-MATURE", :satisfied, [:maturity_label]},
             {"ABC-IMMATURE", :gating, [:not_terminal, :missing_maturity_label]},
             {"ABC-DAEMON", :ignored, [:daemon_state]}
           ]

    assert [
             %{
               identifier: "ABC-OUT",
               title: "Out of scope dependent",
               state: "In Progress",
               status: :eligible,
               scope: :out_of_scope,
               blockers: [%{identifier: "ABC-IMMATURE", status: :out_of_scope, reasons: [:out_of_gate_scope]}]
             }
           ] = snapshot.out_of_scope
  end

  test "poll updates maturity gate snapshot even when dispatch slots are full" do
    gated_issue =
      issue(
        id: "gated-dependent",
        identifier: "ABC-GATED",
        title: "Gated dependent",
        state: "Todo",
        blocked_by: [blocker(id: "blocker-immature", identifier: "ABC-IMMATURE", state: "In Review")]
      )

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [gated_issue])

    updated_state = Orchestrator.maybe_dispatch_for_test(state(%{max_concurrent_agents: 0}))

    assert %DateTime{} = updated_state.maturity_gate_snapshot.evaluated_at

    assert [
             %{
               identifier: "ABC-GATED",
               blockers: [%{identifier: "ABC-IMMATURE", status: :gating}]
             }
           ] = updated_state.maturity_gate_snapshot.gated
  end

  test "poll clears maturity gate snapshot when candidate fetch fails" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "token",
      tracker_project_slug: "project"
    )

    Application.put_env(:symphony_elixir, :linear_client_module, FailingLinearClient)

    previous_snapshot = %{
      gated: [%{identifier: "ABC-OLD"}],
      out_of_scope: [%{identifier: "ABC-SCOPE"}],
      evaluated_at: ~U[2026-08-02 17:00:00Z],
      error: nil
    }

    updated_state = Orchestrator.maybe_dispatch_for_test(state(%{maturity_gate_snapshot: previous_snapshot}))

    assert updated_state.maturity_gate_snapshot.gated == []
    assert updated_state.maturity_gate_snapshot.out_of_scope == []
    assert updated_state.maturity_gate_snapshot.evaluated_at == nil
    assert updated_state.maturity_gate_snapshot.error =~ "rate_limited"
  end

  test "logs gated maturity decisions with blocker context and suppresses unchanged repeats" do
    gated_issue =
      issue(
        id: "gated-dependent",
        identifier: "ABC-GATED",
        blocked_by: [
          blocker(id: "immature-blocker", identifier: "ABC-BLOCKER", state: "In Review", labels: ["needs-review"])
        ]
      )

    log =
      capture_log(fn ->
        {false, updated_state} = Orchestrator.evaluate_dispatch_issue_for_test(gated_issue, state())
        {false, _unchanged_state} = Orchestrator.evaluate_dispatch_issue_for_test(gated_issue, updated_state)
      end)

    assert log =~ "Maturity gate rejected dispatch"
    assert log =~ "issue_identifier=ABC-GATED"
    assert log =~ "dependent_state=\"Todo\""
    assert log =~ "identifier=ABC-BLOCKER"
    assert log =~ "state=In Review"
    assert log =~ "labels=[\"needs-review\"]"
    assert log =~ "maturity_labels=[\"mature\"]"
    assert log =~ "maturity_gate_state_scope=[\"todo\"]"
    assert log =~ "daemon_states=[\"Happy\", \"Unhappy\"]"
    assert log =~ "terminal_states="
    assert length(String.split(log, "Maturity gate rejected dispatch")) == 2
  end

  test "re-logs unchanged gated maturity decisions after the cache ttl per issue" do
    issue_a =
      issue(
        id: "gated-dependent-a",
        identifier: "ABC-GATED-A",
        blocked_by: [blocker(id: "immature-blocker-a", identifier: "ABC-BLOCKER-A", state: "In Review")]
      )

    issue_b =
      issue(
        id: "gated-dependent-b",
        identifier: "ABC-GATED-B",
        blocked_by: [blocker(id: "immature-blocker-b", identifier: "ABC-BLOCKER-B", state: "In Review")]
      )

    log =
      capture_log(fn ->
        {false, state_a} = Orchestrator.evaluate_dispatch_issue_for_test(issue_a, state())
        {false, state_b} = Orchestrator.evaluate_dispatch_issue_for_test(issue_b, state_a)

        stale_state = backdate_cached_log(state_b, :maturity_gate_log_decisions, issue_a.id)

        {false, state_c} = Orchestrator.evaluate_dispatch_issue_for_test(issue_a, stale_state)
        {false, _state_d} = Orchestrator.evaluate_dispatch_issue_for_test(issue_b, state_c)
      end)

    assert occurrences(log, "Maturity gate rejected dispatch") == 3
    assert occurrences(log, "issue_identifier=ABC-GATED-A") == 2
    assert occurrences(log, "issue_identifier=ABC-GATED-B") == 1
  end

  test "logs changed maturity gate decisions immediately inside the cache ttl" do
    gated_issue =
      issue(
        id: "gated-dependent",
        identifier: "ABC-GATED",
        blocked_by: [blocker(id: "immature-blocker-a", identifier: "ABC-BLOCKER-A", state: "In Review")]
      )

    changed_issue = %{
      gated_issue
      | blocked_by: [blocker(id: "immature-blocker-b", identifier: "ABC-BLOCKER-B", state: "In Review")]
    }

    log =
      capture_log(fn ->
        {false, cached_state} = Orchestrator.evaluate_dispatch_issue_for_test(gated_issue, state())
        {false, _changed_state} = Orchestrator.evaluate_dispatch_issue_for_test(changed_issue, cached_state)
      end)

    assert occurrences(log, "Maturity gate rejected dispatch") == 2
    assert log =~ "identifier=ABC-BLOCKER-A"
    assert log =~ "identifier=ABC-BLOCKER-B"
  end

  test "logs out-of-scope maturity gate decisions without gating dispatch" do
    out_of_scope_issue =
      issue(
        id: "progress-dependent",
        identifier: "ABC-PROGRESS",
        state: "In Progress",
        blocked_by: [blocker(id: "immature-blocker", state: "In Review")]
      )

    log =
      capture_log(fn ->
        assert {true, _state} = Orchestrator.evaluate_dispatch_issue_for_test(out_of_scope_issue, state())
      end)

    assert log =~ "Maturity gate skipped; issue out of gate scope"
    assert log =~ "issue_identifier=ABC-PROGRESS"
    assert log =~ "dependent_state=\"In Progress\""
    assert log =~ "maturity_gate_state_scope=[\"todo\"]"
    refute log =~ "Maturity gate rejected dispatch"
  end

  test "logs slot exhaustion as dispatch rejection, not a gate decision" do
    running_issue = issue(id: "running-slot", identifier: "ABC-RUNNING")
    agent_pid = sleeping_process()

    exhausted_state =
      state(%{
        max_concurrent_agents: 1,
        running: %{running_issue.id => running_entry(running_issue, agent_pid)}
      })

    slot_candidate = issue(id: "slot-dependent", identifier: "ABC-SLOT")

    log =
      capture_log(fn ->
        assert {false, _state} = Orchestrator.evaluate_dispatch_issue_for_test(slot_candidate, exhausted_state)
      end)

    assert log =~ "Dispatch candidate rejected"
    assert log =~ "reason=slot_exhausted"
    assert log =~ "global"
    refute log =~ "Maturity gate rejected dispatch"

    send(agent_pid, :stop)
  end

  test "re-logs unchanged dispatch rejections after the cache ttl per issue" do
    running_issue = issue(id: "running-slot", identifier: "ABC-RUNNING")
    agent_pid = sleeping_process()

    on_exit(fn -> send(agent_pid, :stop) end)

    exhausted_state =
      state(%{
        max_concurrent_agents: 1,
        running: %{running_issue.id => running_entry(running_issue, agent_pid)}
      })

    slot_a = issue(id: "slot-dependent-a", identifier: "ABC-SLOT-A")
    slot_b = issue(id: "slot-dependent-b", identifier: "ABC-SLOT-B")

    log =
      capture_log(fn ->
        {false, state_a} = Orchestrator.evaluate_dispatch_issue_for_test(slot_a, exhausted_state)
        {false, state_b} = Orchestrator.evaluate_dispatch_issue_for_test(slot_b, state_a)

        stale_state = backdate_cached_log(state_b, :dispatch_rejections, slot_a.id)

        {false, state_c} = Orchestrator.evaluate_dispatch_issue_for_test(slot_a, stale_state)
        {false, _state_d} = Orchestrator.evaluate_dispatch_issue_for_test(slot_b, state_c)
      end)

    assert occurrences(log, "Dispatch candidate rejected") == 3
    assert occurrences(log, "issue_identifier=ABC-SLOT-A") == 2
    assert occurrences(log, "issue_identifier=ABC-SLOT-B") == 1
  end

  test "logs changed dispatch rejections immediately inside the cache ttl" do
    running_issue = issue(id: "running-slot", identifier: "ABC-RUNNING")
    rejected_issue = issue(id: "rejected-dependent", identifier: "ABC-REJECT")
    agent_pid = sleeping_process()

    on_exit(fn -> send(agent_pid, :stop) end)

    exhausted_state =
      state(%{
        max_concurrent_agents: 1,
        running: %{running_issue.id => running_entry(running_issue, agent_pid)}
      })

    log =
      capture_log(fn ->
        {false, cached_state} = Orchestrator.evaluate_dispatch_issue_for_test(rejected_issue, exhausted_state)
        claimed_state = %{cached_state | running: %{}, claimed: MapSet.new([rejected_issue.id])}
        {false, _changed_state} = Orchestrator.evaluate_dispatch_issue_for_test(rejected_issue, claimed_state)
      end)

    assert occurrences(log, "Dispatch candidate rejected") == 2
    assert log =~ "reason=slot_exhausted"
    assert log =~ "reason=already_claimed"
  end

  test "logs already claimed running and blocked dispatch rejections distinctly" do
    base_issue = issue(id: "already-dependent", identifier: "ABC-ALREADY")
    agent_pid = sleeping_process()

    log =
      capture_log(fn ->
        assert {false, _state} =
                 Orchestrator.evaluate_dispatch_issue_for_test(
                   base_issue,
                   state(%{claimed: MapSet.new([base_issue.id])})
                 )

        assert {false, _state} =
                 Orchestrator.evaluate_dispatch_issue_for_test(
                   base_issue,
                   state(%{running: %{base_issue.id => running_entry(base_issue, agent_pid)}})
                 )

        assert {false, _state} =
                 Orchestrator.evaluate_dispatch_issue_for_test(
                   base_issue,
                   state(%{blocked: %{base_issue.id => %{error: "codex turn requires operator input"}}})
                 )
      end)

    assert log =~ "reason=already_claimed"
    assert log =~ "reason=already_running"
    assert log =~ "reason=already_blocked"

    send(agent_pid, :stop)
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

    assert {true, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
               issue(id: "todo-mature-waiting", state: "Todo", blocked_by: [mature_blocker]),
               state()
             )

    assert {false, _state} =
             Orchestrator.evaluate_dispatch_issue_for_test(
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
    assert {true, _state} = Orchestrator.evaluate_dispatch_issue_for_test(mature, released)
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

  defp backdate_cached_log(%Orchestrator.State{} = state, field, issue_id) do
    update_in(state, [Access.key(field), issue_id], fn %{logged_at_ms: logged_at_ms} = cached ->
      %{cached | logged_at_ms: logged_at_ms - @stale_cache_age_ms}
    end)
  end

  defp occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
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
