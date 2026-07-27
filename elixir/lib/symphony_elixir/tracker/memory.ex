defmodule SymphonyElixir.Tracker.Memory do
  @moduledoc """
  In-memory tracker adapter used for tests and local development.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Linear.Issue

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    {:ok, issue_entries()}
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) do
    normalized_states =
      state_names
      |> Enum.map(&normalize_state/1)
      |> MapSet.new()

    {:ok,
     Enum.filter(issue_entries(), fn %Issue{state: state} ->
       MapSet.member?(normalized_states, normalize_state(state))
     end)}
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    wanted_ids = MapSet.new(issue_ids)

    {:ok,
     Enum.filter(issue_entries(), fn %Issue{id: id} ->
       MapSet.member?(wanted_ids, id)
     end)}
  end

  @spec fetch_issue_state_history(String.t(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def fetch_issue_state_history(issue_id, limit) when is_binary(issue_id) and is_integer(limit) and limit > 0 do
    history =
      configured_issue_history()
      |> Map.get(issue_id, [])
      |> Enum.filter(&is_map/1)
      |> Enum.take(limit)

    {:ok, history}
  end

  @spec fetch_comment_body(String.t()) :: {:ok, String.t()} | {:error, term()}
  def fetch_comment_body(comment_id) when is_binary(comment_id) do
    case Map.fetch(configured_comment_bodies(), comment_id) do
      {:ok, body} when is_binary(body) -> {:ok, body}
      _ -> {:error, :comment_not_found}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    send_event({:memory_tracker_comment, issue_id, body})
    :ok
  end

  @spec update_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def update_comment(comment_id, body) do
    send_event({:memory_tracker_comment_update, comment_id, body})
    :ok
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    send_event({:memory_tracker_state_update, issue_id, state_name})
    :ok
  end

  defp configured_issues do
    Application.get_env(:symphony_elixir, :memory_tracker_issues, [])
  end

  defp configured_comment_bodies do
    Application.get_env(:symphony_elixir, :memory_tracker_comment_bodies, %{})
  end

  defp configured_issue_history do
    Application.get_env(:symphony_elixir, :memory_tracker_issue_history, %{})
  end

  defp issue_entries do
    Enum.filter(configured_issues(), &match?(%Issue{}, &1))
  end

  defp send_event(message) do
    case Application.get_env(:symphony_elixir, :memory_tracker_recipient) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state), do: ""
end
