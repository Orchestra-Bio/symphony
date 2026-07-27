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
    # The poll query filters comments to Issue.workpad_title/0; an empty list
    # here means no Symphony workpad anchor, not no comments on the ticket.
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
    case latest_anchor_comment(issue) do
      {:ok, %{updated_at: updated_at}} -> {:ok, updated_at}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec new_body() :: String.t()
  def new_body, do: Issue.workpad_title() <> "\n" <> @new_line

  @spec last_run_body(DateTime.t()) :: String.t()
  def last_run_body(%DateTime{} = ran_at) do
    Issue.workpad_title() <> "\n" <> @last_run_prefix <> DateTime.to_iso8601(DateTime.truncate(ran_at, :second))
  end

  @spec latest_anchor_comment(Issue.t()) :: {:ok, Issue.comment_ref()} | {:error, :missing_workpad_anchor}
  def latest_anchor_comment(%Issue{} = issue) do
    Issue.latest_anchor_comment(issue)
  end

  defp anchor_comment_id(%Issue{} = issue) do
    case latest_anchor_comment(issue) do
      {:ok, %{id: comment_id}} when is_binary(comment_id) -> {:ok, comment_id}
      _ -> {:error, :missing_workpad_anchor}
    end
  end
end
