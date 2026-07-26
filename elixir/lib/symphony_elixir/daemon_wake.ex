defmodule SymphonyElixir.DaemonWake do
  @moduledoc """
  Pure daemon timer wake evaluator.
  """

  alias SymphonyElixir.Linear.Issue

  @jitter_offsets_seconds [-60, -30, 0, 30, 60]
  @default_workpad_title "## Symphony Workpad"
  @supported_wakes %{
    "15m" => 15 * 60,
    "1h" => 60 * 60,
    "4h" => 4 * 60 * 60,
    "1d" => 24 * 60 * 60
  }

  defstruct status: :not_daemon,
            next_wake_at: nil,
            blockers: [],
            warnings: [],
            startup_stagger_ms: 0

  @type status :: :not_daemon | :dispatching | :gated | :invalid | :due | :sleep
  @type warning ::
          :conflicting_wake_labels
          | :unsupported_wake_label
          | :missing_workpad_anchor
          | :missing_created_at
          | :duplicate_titled_comments
  @type config :: %{
          optional(:daemon_states) => [String.t()] | MapSet.t(),
          optional(:daemon_dispatch_states) => [String.t()] | MapSet.t(),
          optional(:terminal_states) => [String.t()] | MapSet.t(),
          optional(:daemon_default_wake) => String.t(),
          optional(:symphony_workpad_title) => String.t()
        }
  @type t :: %__MODULE__{
          status: status(),
          next_wake_at: DateTime.t() | nil,
          blockers: [Issue.blocker_ref()],
          warnings: [warning()],
          startup_stagger_ms: non_neg_integer()
        }

  @spec workpad_title(config()) :: String.t()
  def workpad_title(%{} = config) do
    config_value(config, :symphony_workpad_title, @default_workpad_title)
    |> normalize_workpad_title()
  end

  @spec evaluate(Issue.t(), DateTime.t(), config(), keyword()) :: t()
  def evaluate(%Issue{} = issue, %DateTime{} = now, %{} = config, opts \\ []) do
    daemon_states = normalized_set(config_value(config, :daemon_states, []))
    dispatch_states = normalized_set(config_value(config, :daemon_dispatch_states, []))
    state = normalize_string(issue.state)

    cond do
      MapSet.member?(dispatch_states, state) ->
        %__MODULE__{status: :dispatching}

      not MapSet.member?(daemon_states, state) ->
        %__MODULE__{status: :not_daemon}

      blockers = incomplete_blockers(issue, config) ->
        %__MODULE__{status: :gated, blockers: blockers}

      true ->
        evaluate_timer(issue, now, config, opts)
    end
  end

  @spec deterministic_jitter_seconds(Issue.t(), String.t() | nil, String.t(), DateTime.t()) :: integer()
  def deterministic_jitter_seconds(%Issue{} = issue, anchor_id, cadence, %DateTime{} = anchor_at) do
    key =
      [
        issue.id || issue.identifier || "",
        anchor_id || "issue-created",
        cadence,
        DateTime.to_iso8601(anchor_at)
      ]
      |> Enum.join("|")

    index = :erlang.phash2(key, length(@jitter_offsets_seconds))

    Enum.at(@jitter_offsets_seconds, index)
  end

  @spec stagger_due(t(), DateTime.t(), non_neg_integer()) :: t()
  def stagger_due(%__MODULE__{status: :due} = decision, %DateTime{} = now, delay_ms)
      when is_integer(delay_ms) and delay_ms > 0 do
    %__MODULE__{
      decision
      | status: :sleep,
        next_wake_at: DateTime.add(now, delay_ms, :millisecond),
        startup_stagger_ms: delay_ms
    }
  end

  def stagger_due(%__MODULE__{} = decision, %DateTime{}, delay_ms)
      when is_integer(delay_ms) and delay_ms >= 0 do
    decision
  end

  defp evaluate_timer(issue, now, config, opts) do
    {cadence, cadence_warnings} = resolve_cadence(issue.labels, config)

    case resolve_anchor(issue) do
      {:ok, anchor_id, anchor_at, anchor_warnings} ->
        jitter_fun = Keyword.get(opts, :jitter_fun, &deterministic_jitter_seconds/4)
        jitter_seconds = jitter_fun.(issue, anchor_id, cadence, anchor_at)

        next_wake_at =
          anchor_at
          |> DateTime.add(Map.fetch!(@supported_wakes, cadence), :second)
          |> DateTime.add(jitter_seconds, :second)

        status =
          if DateTime.compare(next_wake_at, now) in [:lt, :eq] do
            :due
          else
            :sleep
          end

        %__MODULE__{
          status: status,
          next_wake_at: next_wake_at,
          warnings: cadence_warnings ++ anchor_warnings
        }

      {:error, warning} ->
        %__MODULE__{status: :invalid, warnings: cadence_warnings ++ [warning]}
    end
  end

  defp incomplete_blockers(issue, config) do
    terminal_states = normalized_set(config_value(config, :terminal_states, []))

    blockers =
      issue.blocked_by
      |> Enum.reject(fn blocker ->
        blocker
        |> map_value(:state, "state")
        |> normalize_string()
        |> then(&MapSet.member?(terminal_states, &1))
      end)

    if blockers == [], do: nil, else: blockers
  end

  defp resolve_cadence(labels, config) do
    default_wake = normalize_wake(config_value(config, :daemon_default_wake, "1h"))

    wake_labels =
      labels
      |> Enum.map(&normalize_string/1)
      |> Enum.filter(&String.starts_with?(&1, "wake:"))
      |> Enum.uniq()

    supported =
      wake_labels
      |> Enum.map(&String.replace_prefix(&1, "wake:", ""))
      |> Enum.filter(&Map.has_key?(@supported_wakes, &1))
      |> Enum.uniq()

    cond do
      Enum.any?(wake_labels, &(not supported_wake_label?(&1))) ->
        {default_wake, [:unsupported_wake_label]}

      length(supported) > 1 ->
        {default_wake, [:conflicting_wake_labels]}

      length(supported) == 1 ->
        {List.first(supported), []}

      true ->
        {default_wake, []}
    end
  end

  defp supported_wake_label?("wake:" <> cadence), do: Map.has_key?(@supported_wakes, cadence)
  defp supported_wake_label?(_label), do: false

  defp resolve_anchor(issue) do
    anchor_comments =
      issue.comments
      |> Enum.map(fn comment ->
        {comment, comment_updated_at(comment)}
      end)
      |> Enum.reject(fn {_comment, updated_at} -> is_nil(updated_at) end)
      |> Enum.map(fn {comment, _updated_at} -> comment end)

    duplicate_warning =
      if length(anchor_comments) > 1, do: [:duplicate_titled_comments], else: []

    case anchor_comments do
      [comment | _rest] ->
        {:ok, comment_id(comment), comment_updated_at(comment), duplicate_warning}

      [] ->
        case issue.created_at do
          %DateTime{} = created_at ->
            {:ok, nil, created_at, [:missing_workpad_anchor]}

          _created_at ->
            {:error, :missing_created_at}
        end
    end
  end

  defp comment_updated_at(comment) do
    comment
    |> map_value(:updated_at, "updatedAt")
    |> parse_datetime()
  end

  defp comment_id(comment), do: map_value(comment, :id, "id")

  defp config_value(config, key, default) do
    Map.get(config, key) || Map.get(config, to_string(key)) || default
  end

  defp map_value(map, atom_key, string_key) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp normalized_set(%MapSet{} = values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalized_set(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalized_set(_values), do: MapSet.new()

  defp normalize_wake(value) do
    value
    |> normalize_string()
    |> String.replace_prefix("wake:", "")
  end

  defp normalize_workpad_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> case do
      "" -> @default_workpad_title
      title -> title
    end
  end

  defp normalize_workpad_title(_title), do: @default_workpad_title

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string(_value), do: ""

  defp parse_datetime(%DateTime{} = datetime), do: datetime
  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_raw), do: nil
end
