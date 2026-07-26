defmodule SymphonyElixir.SymphonyWorkpad do
  @moduledoc """
  Owns the engine-written Linear workpad used as the daemon wake anchor.
  """

  alias SymphonyElixir.{Linear.Issue, Tracker}

  @new_line "New"
  @last_run_prefix "Last run "

  @type ensure_result :: :existing | :created

  @spec ensure_created(Issue.t()) :: {:ok, ensure_result()} | {:error, term()}
  def ensure_created(%Issue{id: issue_id, comments: comments})
      when is_binary(issue_id) and is_list(comments) do
    if comments == [] do
      case Tracker.create_comment(issue_id, new_body()) do
        :ok -> {:ok, :created}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, :existing}
    end
  end

  def ensure_created(%Issue{}), do: {:error, :missing_issue_id}

  @spec record_last_run(Issue.t()) :: :ok | {:error, term()}
  def record_last_run(%Issue{} = issue) do
    record_last_run(issue, DateTime.utc_now())
  end

  @spec record_last_run(Issue.t(), DateTime.t()) :: :ok | {:error, term()}
  def record_last_run(%Issue{} = issue, %DateTime{} = ran_at) do
    with {:ok, comment_id} <- anchor_comment_id(issue) do
      Tracker.update_comment(comment_id, last_run_body(ran_at))
    end
  end

  @spec anchor_updated_at(Issue.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def anchor_updated_at(%Issue{} = issue) do
    with {:ok, comment} <- latest_anchor_comment(issue),
         %DateTime{} = updated_at <- Map.get(comment, :updated_at) do
      {:ok, updated_at}
    else
      nil -> {:error, :missing_workpad_anchor}
      _ -> {:error, :missing_workpad_anchor}
    end
  end

  @spec new_body() :: String.t()
  def new_body, do: Issue.workpad_title() <> "\n" <> @new_line

  @spec last_run_body(DateTime.t()) :: String.t()
  def last_run_body(%DateTime{} = ran_at) do
    Issue.workpad_title() <> "\n" <> @last_run_prefix <> DateTime.to_iso8601(DateTime.truncate(ran_at, :second))
  end

  defp anchor_comment_id(%Issue{} = issue) do
    with {:ok, comment} <- latest_anchor_comment(issue),
         comment_id when is_binary(comment_id) <- Map.get(comment, :id) do
      {:ok, comment_id}
    else
      nil -> {:error, :missing_workpad_anchor}
      _ -> {:error, :missing_workpad_anchor}
    end
  end

  defp latest_anchor_comment(%Issue{comments: comments}) when is_list(comments) do
    comments
    |> Enum.filter(&match?(%DateTime{}, Map.get(&1, :updated_at)))
    |> Enum.max_by(
      &Map.fetch!(&1, :updated_at),
      fn left, right -> DateTime.compare(left, right) != :lt end,
      fn -> nil end
    )
    |> case do
      nil -> {:error, :missing_workpad_anchor}
      comment -> {:ok, comment}
    end
  end

  defp latest_anchor_comment(%Issue{}), do: {:error, :missing_workpad_anchor}
end
