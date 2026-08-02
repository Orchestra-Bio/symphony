defmodule SymphonyElixir.MaturityGate do
  @moduledoc """
  Pure direct-blocker maturity gate for dispatch eligibility.
  """

  alias SymphonyElixir.Linear.Issue

  defstruct status: :eligible, scope: :in_scope, blockers: [], warnings: [], blocker_decisions: []

  @type warning :: {:daemon_blocker_ignored, Issue.blocker_ref()}
  @type blocker_reason ::
          :terminal | :maturity_label | :not_terminal | :missing_maturity_label | :daemon_state | :out_of_gate_scope
  @type blocker_decision :: %{
          blocker: Issue.blocker_ref(),
          status: :satisfied | :gating | :ignored | :out_of_scope,
          reasons: [blocker_reason()]
        }
  @type config :: %{
          optional(:terminal_states) => [String.t()],
          optional(:daemon_states) => [String.t()],
          optional(:maturity_labels) => [String.t()],
          optional(:maturity_gate_state_scope) => [String.t()]
        }
  @type t :: %__MODULE__{
          status: :eligible | :gated,
          scope: :in_scope | :out_of_scope,
          blockers: [Issue.blocker_ref()],
          warnings: [warning()],
          blocker_decisions: [blocker_decision()]
        }
  @type result :: :eligible | {:eligible_with_warnings, [warning()]} | {:gated, [Issue.blocker_ref()]}

  @spec evaluate(Issue.t(), config()) :: t()
  def evaluate(%Issue{} = issue, %{} = config) do
    case issue_in_scope?(issue, config) do
      true -> scoped_decision(issue, config)
      false -> out_of_scope_decision(issue)
    end
  end

  @spec result(t()) :: result()
  def result(%__MODULE__{status: :gated, blockers: blockers}), do: {:gated, blockers}
  def result(%__MODULE__{status: :eligible, warnings: []}), do: :eligible
  def result(%__MODULE__{status: :eligible, warnings: warnings}), do: {:eligible_with_warnings, warnings}

  @spec maturity_regressions(Issue.t(), Issue.t(), config()) :: [Issue.blocker_ref()]
  def maturity_regressions(%Issue{} = previous_issue, %Issue{} = refreshed_issue, %{} = config) do
    maturity_labels = normalized_values(Map.get(config, :maturity_labels, []))

    case maturity_labels do
      [] -> []
      _labels -> regression_candidates(previous_issue, refreshed_issue, config, maturity_labels)
    end
  end

  defp scoped_decision(%Issue{} = issue, config) do
    blocker_decisions = Enum.map(issue.blocked_by, &blocker_decision(&1, config))
    blockers = Enum.flat_map(blocker_decisions, &gating_blocker/1)
    warnings = Enum.flat_map(blocker_decisions, &blocker_warning/1)

    %__MODULE__{
      status: if(blockers == [], do: :eligible, else: :gated),
      blockers: blockers,
      warnings: warnings,
      blocker_decisions: blocker_decisions
    }
  end

  defp out_of_scope_decision(%Issue{} = issue) do
    %__MODULE__{
      scope: :out_of_scope,
      blocker_decisions:
        Enum.map(issue.blocked_by, fn blocker ->
          %{blocker: blocker, status: :out_of_scope, reasons: [:out_of_gate_scope]}
        end)
    }
  end

  defp gating_blocker(%{status: :gating, blocker: blocker}), do: [blocker]
  defp gating_blocker(_decision), do: []

  defp blocker_warning(%{status: :ignored, blocker: blocker, reasons: reasons}) do
    if :daemon_state in reasons, do: [{:daemon_blocker_ignored, blocker}], else: []
  end

  defp blocker_warning(_decision), do: []

  defp regression_candidates(previous_issue, refreshed_issue, config, maturity_labels) do
    previous_blockers = previous_blocker_index(previous_issue.blocked_by)

    Enum.filter(refreshed_issue.blocked_by, fn blocker ->
      regressed_blocker?(blocker, previous_blockers, config, maturity_labels)
    end)
  end

  defp regressed_blocker?(blocker, previous_blockers, config, maturity_labels) do
    case Map.get(previous_blockers, blocker_key(blocker)) do
      nil -> false
      previous_blocker -> maturity_regressed?(previous_blocker, blocker, config, maturity_labels)
    end
  end

  defp issue_in_scope?(%Issue{state: state}, config) do
    # Out-of-scope issues are ungated; removing "todo" also removes the
    # upstream terminal-only blocker gate for Todo issues.
    scope = normalized_values(Map.get(config, :maturity_gate_state_scope, []))
    normalize_string(state) in scope
  end

  defp blocker_decision(blocker, config) when is_map(blocker) do
    terminal_states = normalized_values(Map.get(config, :terminal_states, []))
    daemon_states = normalized_values(Map.get(config, :daemon_states, []))
    maturity_labels = normalized_values(Map.get(config, :maturity_labels, []))
    blocker_state = normalize_string(Map.get(blocker, :state))

    cond do
      blocker_state in terminal_states ->
        %{blocker: blocker, status: :satisfied, reasons: [:terminal]}

      blocker_state in daemon_states ->
        %{blocker: blocker, status: :ignored, reasons: [:daemon_state]}

      maturity_labels != [] and has_maturity_label?(blocker, maturity_labels) ->
        %{blocker: blocker, status: :satisfied, reasons: [:maturity_label]}

      true ->
        %{blocker: blocker, status: :gating, reasons: gating_reasons(maturity_labels)}
    end
  end

  defp gating_reasons([]), do: [:not_terminal]
  defp gating_reasons(_maturity_labels), do: [:not_terminal, :missing_maturity_label]

  defp maturity_regressed?(previous_blocker, refreshed_blocker, config, maturity_labels) do
    terminal_states = normalized_values(Map.get(config, :terminal_states, []))
    daemon_states = normalized_values(Map.get(config, :daemon_states, []))
    refreshed_state = normalize_string(Map.get(refreshed_blocker, :state))

    has_maturity_label?(previous_blocker, maturity_labels) and
      not has_maturity_label?(refreshed_blocker, maturity_labels) and
      refreshed_state not in terminal_states and
      refreshed_state not in daemon_states
  end

  defp previous_blocker_index(blockers) do
    blockers
    |> Enum.map(fn blocker -> {blocker_key(blocker), blocker} end)
    |> Enum.reject(fn {key, _blocker} -> is_nil(key) end)
    |> Map.new()
  end

  defp blocker_key(blocker) when is_map(blocker) do
    id = normalize_key(Map.get(blocker, :id))
    identifier = normalize_key(Map.get(blocker, :identifier))

    cond do
      id != nil -> {:id, id}
      identifier != nil -> {:identifier, identifier}
      true -> nil
    end
  end

  defp has_maturity_label?(blocker, maturity_labels) do
    labels = blocker |> Map.get(:labels, []) |> normalized_values()
    Enum.any?(labels, &(&1 in maturity_labels))
  end

  defp normalized_values(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalized_values(_values), do: []

  defp normalize_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_key(_value), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string(_value), do: ""
end
