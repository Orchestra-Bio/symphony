defmodule SymphonyElixir.MaturityGateTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.MaturityGate

  test "empty maturity labels keep terminal-only blocker behavior in scoped states" do
    config = config(maturity_labels: [])

    done_blocker = blocker(id: "blocker-done", state: "Done")
    active_blocker = blocker(id: "blocker-active", state: "In Progress", labels: ["mature"])

    assert %MaturityGate{status: :eligible} =
             MaturityGate.evaluate(issue(blocked_by: [done_blocker]), config)

    decision = MaturityGate.evaluate(issue(blocked_by: [active_blocker]), config)

    assert decision.status == :gated
    assert MaturityGate.result(decision) == {:gated, [active_blocker]}
  end

  test "default scope preserves Todo-only gating and widened scope gates additional candidate states" do
    immature_blocker = blocker(id: "blocker-review", state: "In Review")

    default_config = config()

    assert %MaturityGate{status: :gated} =
             MaturityGate.evaluate(issue(state: "Todo", blocked_by: [immature_blocker]), default_config)

    assert %MaturityGate{status: :eligible} =
             MaturityGate.evaluate(issue(state: "In Progress", blocked_by: [immature_blocker]), default_config)

    widened_config = config(maturity_gate_state_scope: ["todo", "in progress"])

    assert %MaturityGate{status: :gated} =
             MaturityGate.evaluate(issue(state: "In Progress", blocked_by: [immature_blocker]), widened_config)

    mature_blocker = %{immature_blocker | labels: ["mature"]}

    assert %MaturityGate{status: :eligible} =
             MaturityGate.evaluate(issue(state: "In Progress", blocked_by: [mature_blocker]), widened_config)
  end

  test "empty scope leaves issues ungated even when blockers are non-terminal" do
    immature_blocker = blocker(id: "blocker-review", state: "In Review")

    assert %MaturityGate{status: :eligible, blockers: [], warnings: []} =
             MaturityGate.evaluate(
               issue(state: "Todo", blocked_by: [immature_blocker]),
               config(maturity_gate_state_scope: [])
             )
  end

  test "mature direct blockers open depth two and compose in depth three without transitive checks" do
    config = config()

    blocker_a = blocker(id: "a", identifier: "ABC-A", state: "In Review", labels: ["mature"])
    blocker_b = blocker(id: "b", identifier: "ABC-B", state: "In Review", labels: ["mature"])
    blocker_a_regressed = %{blocker_a | labels: []}

    depth_two = issue(id: "b", identifier: "ABC-B", blocked_by: [blocker_a])
    depth_three = issue(id: "c", identifier: "ABC-C", blocked_by: [blocker_b])

    assert %MaturityGate{status: :eligible} = MaturityGate.evaluate(depth_two, config)
    assert %MaturityGate{status: :eligible} = MaturityGate.evaluate(depth_three, config)

    depth_three_still_edge_local = %{depth_three | blocked_by: [blocker_b]}

    assert %MaturityGate{status: :eligible} =
             MaturityGate.evaluate(depth_three_still_edge_local, config)

    assert %MaturityGate{status: :gated} =
             MaturityGate.evaluate(%{depth_two | blocked_by: [blocker_a_regressed]}, config)
  end

  test "daemon-state blockers are ignored with warnings" do
    daemon_blocker = blocker(id: "daemon", identifier: "ABC-D", state: "Happy")
    immature_blocker = blocker(id: "normal", identifier: "ABC-N", state: "In Progress")

    eligible = MaturityGate.evaluate(issue(blocked_by: [daemon_blocker]), config())

    assert eligible.status == :eligible
    assert MaturityGate.result(eligible) == {:eligible_with_warnings, [{:daemon_blocker_ignored, daemon_blocker}]}

    gated = MaturityGate.evaluate(issue(blocked_by: [daemon_blocker, immature_blocker]), config())

    assert gated.status == :gated
    assert gated.warnings == [{:daemon_blocker_ignored, daemon_blocker}]
    assert MaturityGate.result(gated) == {:gated, [immature_blocker]}
  end

  test "decisions explain satisfied, gating, ignored, and out-of-scope blockers" do
    terminal_blocker = blocker(id: "done", identifier: "ABC-DONE", state: "Done")
    mature_blocker = blocker(id: "mature", identifier: "ABC-MATURE", state: "In Review", labels: ["mature"])
    immature_blocker = blocker(id: "immature", identifier: "ABC-IMMATURE", state: "In Review")
    daemon_blocker = blocker(id: "daemon", identifier: "ABC-DAEMON", state: "Happy")

    decision =
      MaturityGate.evaluate(
        issue(blocked_by: [terminal_blocker, mature_blocker, immature_blocker, daemon_blocker]),
        config()
      )

    assert decision.status == :gated
    assert decision.scope == :in_scope
    assert decision.blockers == [immature_blocker]

    assert Enum.map(decision.blocker_decisions, &{&1.blocker.identifier, &1.status, &1.reasons}) == [
             {"ABC-DONE", :satisfied, [:terminal]},
             {"ABC-MATURE", :satisfied, [:maturity_label]},
             {"ABC-IMMATURE", :gating, [:not_terminal, :missing_maturity_label]},
             {"ABC-DAEMON", :ignored, [:daemon_state]}
           ]

    out_of_scope =
      MaturityGate.evaluate(
        issue(state: "In Progress", blocked_by: [immature_blocker]),
        config()
      )

    assert out_of_scope.status == :eligible
    assert out_of_scope.scope == :out_of_scope
    assert [%{status: :out_of_scope, reasons: [:out_of_gate_scope]}] = out_of_scope.blocker_decisions
  end

  test "unknown blockers remain gated" do
    unknown_blocker = %{id: nil, identifier: "", state: nil, labels: nil}

    assert %MaturityGate{status: :gated, blockers: [^unknown_blocker]} =
             MaturityGate.evaluate(issue(blocked_by: [unknown_blocker]), config())
  end

  test "regression detection emits once per eligible to regressed transition" do
    config = config()

    mature_blocker = blocker(id: "blocker", state: "In Review", labels: ["mature"])
    regressed_blocker = %{mature_blocker | labels: []}
    terminal_blocker = %{mature_blocker | state: "Done", labels: []}
    daemon_blocker = %{mature_blocker | state: "Happy", labels: []}

    eligible = issue(blocked_by: [mature_blocker])
    regressed = issue(blocked_by: [regressed_blocker])
    terminal = issue(blocked_by: [terminal_blocker])
    daemon = issue(blocked_by: [daemon_blocker])

    assert MaturityGate.maturity_regressions(eligible, regressed, config) == [regressed_blocker]
    assert MaturityGate.maturity_regressions(regressed, regressed, config) == []
    assert MaturityGate.maturity_regressions(regressed, eligible, config) == []
    assert MaturityGate.maturity_regressions(eligible, terminal, config) == []
    assert MaturityGate.maturity_regressions(eligible, daemon, config) == []
    assert MaturityGate.maturity_regressions(eligible, regressed, config(maturity_labels: [])) == []
  end

  test "regression detection can match blockers by identifier when id is absent" do
    previous = issue(blocked_by: [blocker(id: " ", identifier: "ABC-BLOCKER", state: "Review", labels: ["mature"])])
    refreshed = issue(blocked_by: [blocker(id: " ", identifier: "ABC-BLOCKER", state: "Review", labels: [])])
    unrelated = issue(blocked_by: [blocker(id: nil, identifier: nil, state: "Review", labels: [])])

    assert [_blocker] = MaturityGate.maturity_regressions(previous, refreshed, config())
    assert [] = MaturityGate.maturity_regressions(previous, unrelated, config())
  end

  defp config(overrides \\ []) do
    defaults = %{
      terminal_states: ["done", "canceled"],
      daemon_states: ["happy", "unhappy"],
      maturity_labels: ["mature"],
      maturity_gate_state_scope: ["todo"]
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp issue(overrides) do
    defaults = %{
      id: "dependent",
      identifier: "ABC-DEPENDENT",
      title: "Dependent",
      state: "Todo",
      blocked_by: []
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
end
