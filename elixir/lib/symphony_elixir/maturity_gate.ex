defmodule SymphonyElixir.MaturityGate do
  @moduledoc """
  Pure direct-blocker maturity gate for dispatch eligibility.
  """

  alias SymphonyElixir.Linear.Issue

  defstruct status: :eligible, blockers: [], warnings: []

  @type warning :: {:daemon_blocker_ignored, Issue.blocker_ref()}
  @type config :: %{
          optional(:terminal_states) => [String.t()],
          optional(:daemon_states) => [String.t()],
          optional(:maturity_labels) => [String.t()],
          optional(:maturity_gate_state_scope) => [String.t()]
        }
  @type t :: %__MODULE__{
          status: :eligible | :gated,
          blockers: [Issue.blocker_ref()],
          warnings: [warning()]
        }
  @type result :: :eligible | {:eligible_with_warnings, [warning()]} | {:gated, [Issue.blocker_ref()]}

  @spec evaluate(Issue.t(), config()) :: t()
  def evaluate(%Issue{} = issue, %{} = config) do
    case issue_in_scope?(issue, config) do
      true -> scoped_decision(issue, config)
      false -> %__MODULE__{}
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
    {blockers, warnings} =
      Enum.reduce(issue.blocked_by, {[], []}, fn blocker, acc ->
        record_blocker_status(blocker_status(blocker, config), blocker, acc)
      end)

    %__MODULE__{
      status: if(blockers == [], do: :eligible, else: :gated),
      blockers: Enum.reverse(blockers),
      warnings: Enum.reverse(warnings)
    }
  end

  defp record_blocker_status(:satisfied, _blocker, acc), do: acc
  defp record_blocker_status(:gated, blocker, {blockers, warnings}), do: {[blocker | blockers], warnings}
  defp record_blocker_status({:warning, warning}, _blocker, {blockers, warnings}), do: {blockers, [warning | warnings]}

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
    scope = normalized_values(Map.get(config, :maturity_gate_state_scope, []))
    normalize_string(state) in scope
  end

  defp blocker_status(blocker, config) when is_map(blocker) do
    terminal_states = normalized_values(Map.get(config, :terminal_states, []))
    daemon_states = normalized_values(Map.get(config, :daemon_states, []))
    maturity_labels = normalized_values(Map.get(config, :maturity_labels, []))
    blocker_state = normalize_string(Map.get(blocker, :state))

    cond do
      blocker_state in terminal_states ->
        :satisfied

      blocker_state in daemon_states ->
        {:warning, {:daemon_blocker_ignored, blocker}}

      maturity_labels != [] and has_maturity_label?(blocker, maturity_labels) ->
        :satisfied

      true ->
        :gated
    end
  end

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
