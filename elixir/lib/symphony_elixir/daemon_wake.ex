defmodule SymphonyElixir.DaemonWake do
  @moduledoc """
  Pure daemon timer wake evaluator.
  """

  alias SymphonyElixir.Linear.Issue

  @jitter_offsets_seconds [-60, -30, 0, 30, 60]
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
          | :duplicate_workpad_anchors
  @type config :: %{
          optional(:daemon_states) => [String.t()],
          optional(:daemon_dispatch_states) => [String.t()],
          optional(:terminal_states) => [String.t()],
          optional(:daemon_default_wake) => String.t()
        }
  @type t :: %__MODULE__{
          status: status(),
          next_wake_at: DateTime.t() | nil,
          blockers: [Issue.blocker_ref()],
          warnings: [warning()],
          startup_stagger_ms: non_neg_integer()
        }

  @spec evaluate(Issue.t(), DateTime.t(), config(), keyword()) :: t()
  def evaluate(%Issue{} = issue, %DateTime{} = now, %{} = config, opts \\ []) do
    daemon_states = normalized_states(Map.get(config, :daemon_states) || [])
    dispatch_states = normalized_states(Map.get(config, :daemon_dispatch_states) || [])
    state = normalize_string(issue.state)

    cond do
      state in dispatch_states ->
        %__MODULE__{status: :dispatching}

      state not in daemon_states ->
        %__MODULE__{status: :not_daemon}

      blockers = incomplete_blockers(issue, config) ->
        %__MODULE__{status: :gated, blockers: blockers}

      true ->
        evaluate_timer(issue, now, config, opts)
    end
  end

  # Jitter is pseudorandom but fixed per daemon per sleep cycle, not drawn per call.
  # Nothing stores next_wake_at, so a fresh random draw on each poll could move the
  # due time back and forth. What we need is decorrelation: stable for one sleep,
  # different across daemons, and reproducible after restart.
  #
  # The hash key uses only durable wake inputs: issue id, anchor id, cadence, and
  # anchor timestamp. Including the anchor reshuffles the offset after each
  # evaluation while keeping the current sleep's wake time explainable.
  #
  # The spread is intentionally coarse: five buckets over +/-60s. Per-state
  # concurrency caps still bound a herd; jitter just thins the first wave.
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
    terminal_states = normalized_states(Map.get(config, :terminal_states) || [])

    blockers =
      issue.blocked_by
      |> Enum.reject(fn blocker ->
        blocker
        |> Map.get(:state)
        |> normalize_string()
        |> then(&(&1 in terminal_states))
      end)

    if blockers == [], do: nil, else: blockers
  end

  defp resolve_cadence(labels, config) do
    default_wake = normalize_wake(Map.get(config, :daemon_default_wake) || "1h")

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

  defp resolve_anchor(issue) do
    anchor_comments =
      issue.comments
      |> Enum.flat_map(fn comment ->
        case comment_updated_at(comment) do
          %DateTime{} = updated_at -> [%{comment: comment, updated_at: updated_at}]
          _updated_at -> []
        end
      end)

    duplicate_warning =
      if length(anchor_comments) > 1, do: [:duplicate_workpad_anchors], else: []

    case latest_anchor(anchor_comments) do
      %{comment: comment, updated_at: updated_at} ->
        {:ok, comment_id(comment), updated_at, duplicate_warning}

      nil ->
        case issue.created_at do
          %DateTime{} = created_at ->
            {:ok, nil, created_at, [:missing_workpad_anchor]}

          _created_at ->
            {:error, :missing_created_at}
        end
    end
  end

  defp latest_anchor(anchor_comments) do
    Enum.max_by(
      anchor_comments,
      & &1.updated_at,
      fn left, right -> DateTime.compare(left, right) != :lt end,
      fn -> nil end
    )
  end

  defp comment_updated_at(comment), do: Map.get(comment, :updated_at)
  defp comment_id(comment), do: Map.get(comment, :id)

  defp normalized_states(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_wake(value) do
    value
    |> normalize_string()
    |> String.replace_prefix("wake:", "")
  end

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string(_value), do: ""
end
