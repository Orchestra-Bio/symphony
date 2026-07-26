defmodule SymphonyElixir.DaemonMaturityConfigTest do
  use SymphonyElixir.TestSupport

  test "omitted daemon and maturity config preserves existing workflow behavior" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_api_token: nil,
      tracker_project_slug: nil,
      tracker_team_key: nil
    )

    config = Config.settings!()

    assert config.tracker.active_states == ["Todo", "In Progress"]
    assert config.tracker.terminal_states == ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    assert config.tracker.daemon_states == []
    assert config.tracker.daemon_dispatch_states == []
    assert config.tracker.daemon_default_wake == "1h"
    assert config.tracker.maturity_labels == ["mature"]
    assert config.tracker.maturity_gate_state_scope == ["todo"]

    assert Config.daemon_state_set() == MapSet.new()
    assert Config.daemon_dispatch_state_set() == MapSet.new()
    assert Config.daemon_dispatch_target_state() == nil
    assert Config.daemon_default_wake() == "1h"
    assert Config.maturity_label_set() == MapSet.new(["mature"])
    assert Config.maturity_gate_state_scope_set() == MapSet.new(["todo"])
    assert Config.max_concurrent_agents_for_state("Todo") == 10
  end

  test "daemon and maturity tracker config is normalized" do
    write_daemon_workflow!(%{
      "active_states" => ["Todo", "Evaluating", "Review"],
      "terminal_states" => ["Done", "Canceled"],
      "daemon_states" => [" Happy ", "UNHAPPY", "happy"],
      "daemon_dispatch_states" => [" Evaluating "],
      "daemon_default_wake" => " 4H ",
      "maturity_labels" => [" Mature ", "READY", "mature"],
      "maturity_gate_state_scope" => [" Todo ", "REVIEW"]
    })

    config = Config.settings!()

    assert config.tracker.daemon_states == ["happy", "unhappy"]
    assert config.tracker.daemon_dispatch_states == ["evaluating"]
    assert config.tracker.daemon_default_wake == "4h"
    assert config.tracker.maturity_labels == ["mature", "ready"]
    assert config.tracker.maturity_gate_state_scope == ["todo", "review"]
    assert Config.daemon_dispatch_target_state() == "evaluating"
  end

  test "daemon state classes validate against active and terminal states" do
    write_daemon_workflow!(%{
      "active_states" => ["Todo"],
      "terminal_states" => ["Done"],
      "daemon_states" => ["Happy"],
      "daemon_dispatch_states" => []
    })

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_dispatch_states"
    assert message =~ "must be configured when daemon_states is non-empty"

    write_daemon_workflow!(%{
      "active_states" => ["Todo"],
      "terminal_states" => ["Done"],
      "daemon_states" => ["Happy"],
      "daemon_dispatch_states" => ["Evaluating"]
    })

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_dispatch_states"
    assert message =~ "must be listed in tracker.active_states"

    write_daemon_workflow!(%{
      "active_states" => ["Todo", "Evaluating"],
      "terminal_states" => ["Done"],
      "daemon_states" => ["Todo"],
      "daemon_dispatch_states" => ["Evaluating"]
    })

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_states"
    assert message =~ "must be disjoint from tracker.active_states"

    write_daemon_workflow!(%{
      "active_states" => ["Todo", "Evaluating"],
      "terminal_states" => ["Done"],
      "daemon_states" => ["Happy"],
      "daemon_dispatch_states" => ["Done"]
    })

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_dispatch_states"
    assert message =~ "must be disjoint from tracker.terminal_states"
  end

  test "daemon default wake accepts only supported normalized durations" do
    write_daemon_workflow!(%{"daemon_default_wake" => " wake:1h "})

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_default_wake"

    write_daemon_workflow!(%{"daemon_default_wake" => "15M"})
    assert Config.settings!().tracker.daemon_default_wake == "15m"
  end

  test "retired daemon label and class-budget config are rejected" do
    write_daemon_workflow!(%{"daemon_label" => "daemon"})

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.daemon_label"
    assert message =~ "is not supported"

    write_daemon_workflow!(%{}, %{"max_concurrent_agents_by_class" => %{"daemon" => 2}})

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent.max_concurrent_agents_by_class"
    assert message =~ "is not supported"

    write_daemon_workflow!(%{}, %{"daemon_max_concurrent_agents_by_class" => %{"daemon" => 2}})

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent.daemon_max_concurrent_agents_by_class"
    assert message =~ "is not supported"
  end

  defp write_daemon_workflow!(tracker_overrides, agent_overrides \\ %{}) do
    tracker =
      Map.merge(
        %{
          "kind" => "memory",
          "active_states" => ["Todo", "In Progress"],
          "terminal_states" => ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
        },
        tracker_overrides
      )

    agent = Map.merge(%{"max_concurrent_agents" => 10}, agent_overrides)

    workflow = """
    ---
    #{section_yaml("tracker", tracker)}
    #{section_yaml("agent", agent)}
    ---
    You are an agent for this repository.
    """

    File.write!(Workflow.workflow_file_path(), workflow)
    WorkflowStore.force_reload()
  end

  defp section_yaml(name, values) do
    entries =
      Enum.map(values, fn {key, value} ->
        "  #{key}: #{yaml_value(value)}"
      end)

    Enum.join([name <> ":" | entries], "\n")
  end

  defp yaml_value(value) when is_binary(value), do: "\"" <> String.replace(value, "\"", "\\\"") <> "\""
  defp yaml_value(value) when is_integer(value), do: to_string(value)
  defp yaml_value(values) when is_list(values), do: "[" <> Enum.map_join(values, ", ", &yaml_value/1) <> "]"

  defp yaml_value(values) when is_map(values) do
    "{" <>
      Enum.map_join(values, ", ", fn {key, value} ->
        "#{yaml_value(to_string(key))}: #{yaml_value(value)}"
      end) <> "}"
  end

  defp yaml_value(nil), do: "null"
end
