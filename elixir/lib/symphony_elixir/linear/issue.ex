defmodule SymphonyElixir.Linear.Issue do
  @moduledoc """
  Normalized Linear issue representation used by the orchestrator.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :assignee_id,
    blocked_by: [],
    comments: [],
    labels: [],
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type blocker_ref :: %{
          optional(:id) => String.t() | nil,
          optional(:identifier) => String.t() | nil,
          optional(:state) => String.t() | nil,
          optional(:labels) => [String.t()]
        }

  # Linear has no "last evaluated" field, so daemon workpads use the
  # server-written updatedAt of titled comments as the last-run clock. Comments
  # anchor timer wakes; they never trigger daemon wake decisions.
  @type comment_ref :: %{
          id: String.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          blocked_by: [blocker_ref()],
          comments: [comment_ref()],
          labels: [String.t()],
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}) do
    labels
  end

  @spec normalize_blocker_ref(map()) :: blocker_ref()
  def normalize_blocker_ref(%{} = blocker) do
    %{
      id: map_value(blocker, :id, "id"),
      identifier: map_value(blocker, :identifier, "identifier"),
      state: state_name(map_value(blocker, :state, "state")),
      labels: normalize_labels(map_value(blocker, :labels, "labels"))
    }
  end

  @spec normalize_comment_ref(map()) :: comment_ref()
  def normalize_comment_ref(%{} = comment) do
    %{
      id: map_value(comment, :id, "id"),
      updated_at: parse_datetime(map_value(comment, :updated_at, "updatedAt"))
    }
  end

  @spec normalize_labels(term()) :: [String.t()]
  def normalize_labels(%{"nodes" => labels}) when is_list(labels), do: normalize_labels(labels)
  def normalize_labels(%{nodes: labels}) when is_list(labels), do: normalize_labels(labels)

  def normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(&label_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_label/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_labels(_labels), do: []

  @spec routable?(t(), [String.t()]) :: boolean()
  def routable?(%__MODULE__{assigned_to_worker: true, labels: labels}, required_labels)
      when is_list(labels) and is_list(required_labels) do
    issue_labels = MapSet.new(labels, &normalize_label/1)
    Enum.all?(required_labels, &MapSet.member?(issue_labels, normalize_label(&1)))
  end

  def routable?(%__MODULE__{}, _required_labels), do: false

  defp map_value(map, atom_key, string_key) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp state_name(%{"name" => state}) when is_binary(state), do: state
  defp state_name(%{name: state}) when is_binary(state), do: state
  defp state_name(state) when is_binary(state), do: state
  defp state_name(_state), do: nil

  defp label_name(%{"name" => label}) when is_binary(label), do: label
  defp label_name(%{name: label}) when is_binary(label), do: label
  defp label_name(label) when is_binary(label), do: label
  defp label_name(_label), do: nil

  defp normalize_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
  end

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
