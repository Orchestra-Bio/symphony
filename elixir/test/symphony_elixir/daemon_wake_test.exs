defmodule SymphonyElixir.DaemonWakeTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.DaemonWake

  @config %{
    daemon_states: ["happy", "unhappy"],
    daemon_dispatch_states: ["evaluating"],
    terminal_states: ["done", "canceled"],
    daemon_default_wake: "4h",
    daemon_workpad_title: "## Codex Workpad",
    orchestrator_workpad_title: "## Symphony Orchestrator Workpad"
  }

  test "timer due wakes daemon from titled workpad anchor" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        comments: [comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad")]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :due
    assert decision.next_wake_at == ~U[2026-07-26 10:00:00Z]
    assert decision.warnings == []
  end

  test "timer sleep returns next wake timestamp" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        comments: [comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad")]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 09:30:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :sleep
    assert decision.next_wake_at == ~U[2026-07-26 10:00:00Z]
  end

  test "missing comment falls back to issue created_at plus default wake" do
    issue =
      issue(%{
        labels: [],
        comments: [],
        created_at: ~U[2026-07-26 09:00:00Z]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :sleep
    assert decision.next_wake_at == ~U[2026-07-26 13:00:00Z]
    assert decision.warnings == [:missing_workpad_anchor]
  end

  test "metadata-only comments signal unresolved titles instead of created_at fallback" do
    issue =
      issue(%{
        labels: [],
        comments: [%{id: "comment-1", updated_at: ~U[2026-07-26 09:00:00Z]}],
        created_at: ~U[2026-07-26 01:00:00Z]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :invalid
    assert decision.next_wake_at == nil
    assert decision.warnings == [:unresolved_comment_titles]
    assert decision.unresolved_comment_ids == ["comment-1"]
  end

  test "conflicting wake labels use default cadence and never wake immediately" do
    issue =
      issue(%{
        labels: ["wake:15m", "wake:1h"],
        comments: [comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad")]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :sleep
    assert decision.next_wake_at == ~U[2026-07-26 13:00:00Z]
    assert decision.warnings == [:conflicting_wake_labels]
  end

  test "deterministic jitter is stable and applied to durable sleep inputs" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        comments: [comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad")]
      })

    jitter = DaemonWake.deterministic_jitter_seconds(issue, "daemon-comment", "1h", ~U[2026-07-26 09:00:00Z])

    assert jitter in [-60, -30, 0, 30, 60]
    assert jitter == DaemonWake.deterministic_jitter_seconds(issue, "daemon-comment", "1h", ~U[2026-07-26 09:00:00Z])

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 09:30:00Z], @config)

    assert decision.next_wake_at ==
             ~U[2026-07-26 09:00:00Z]
             |> DateTime.add(60 * 60, :second)
             |> DateTime.add(jitter, :second)
  end

  test "duplicate titled comments warn and use the latest updated_at anchor" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        comments: [
          comment("old", ~U[2026-07-26 08:00:00Z], "## Codex Workpad"),
          comment("new", ~U[2026-07-26 09:45:00Z], "## Codex Workpad")
        ]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :sleep
    assert decision.next_wake_at == ~U[2026-07-26 10:45:00Z]
    assert decision.warnings == [:duplicate_titled_comments]
  end

  test "blocked daemons are gated until direct blockers reach terminal states" do
    issue =
      issue(%{
        blocked_by: [%{identifier: "ABC-100", state: "In Progress"}],
        comments: [comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad")]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 14:00:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :gated
    assert decision.blockers == [%{identifier: "ABC-100", state: "In Progress"}]
    assert decision.next_wake_at == nil
  end

  test "startup staggering hook delays only overdue daemon decisions" do
    due = %DaemonWake{status: :due, next_wake_at: ~U[2026-07-26 10:00:00Z]}
    sleeping = %DaemonWake{status: :sleep, next_wake_at: ~U[2026-07-26 11:00:00Z]}

    assert DaemonWake.stagger_due(due, ~U[2026-07-26 10:00:00Z], 60_000) == %DaemonWake{
             status: :sleep,
             next_wake_at: ~U[2026-07-26 10:01:00.000Z],
             startup_stagger_ms: 60_000
           }

    assert DaemonWake.stagger_due(sleeping, ~U[2026-07-26 10:00:00Z], 60_000) == sleeping
  end

  test "new comments do not wake daemons before the timer is due" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        comments: [
          comment("daemon-comment", ~U[2026-07-26 09:00:00Z], "## Codex Workpad"),
          comment("human-comment", ~U[2026-07-26 09:59:00Z], "## Human Note")
        ]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 09:30:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :sleep
    assert decision.next_wake_at == ~U[2026-07-26 10:00:00Z]
  end

  test "issue updated_at is never used as a sleep anchor" do
    issue =
      issue(%{
        labels: ["wake:1h"],
        updated_at: ~U[2026-07-26 09:59:00Z],
        comments: [comment("daemon-comment", ~U[2026-07-26 08:00:00Z], "## Codex Workpad")]
      })

    decision = DaemonWake.evaluate(issue, ~U[2026-07-26 09:30:00Z], @config, jitter_fun: zero_jitter())

    assert decision.status == :due
    assert decision.next_wake_at == ~U[2026-07-26 09:00:00Z]
  end

  test "all daemon dispatch states are owned by ordinary active dispatch" do
    issue =
      issue(%{
        state: "Legacy Evaluating",
        labels: ["wake:15m"],
        comments: [comment("daemon-comment", ~U[2026-07-26 08:00:00Z], "## Codex Workpad")]
      })

    config = %{@config | daemon_dispatch_states: ["Evaluating", "Legacy Evaluating"]}

    assert DaemonWake.evaluate(issue, ~U[2026-07-26 10:00:00Z], config).status == :dispatching
  end

  defp issue(attrs) do
    defaults = %{
      id: "issue-1",
      identifier: "ABC-1",
      state: "Happy",
      labels: ["wake:1h"],
      blocked_by: [],
      comments: [],
      created_at: ~U[2026-07-26 08:00:00Z],
      updated_at: ~U[2026-07-26 08:00:00Z]
    }

    struct(Issue, Map.merge(defaults, attrs))
  end

  defp comment(id, updated_at, title) do
    %{id: id, updated_at: updated_at, body: title <> "\n\nbody"}
  end

  defp zero_jitter do
    fn _issue, _anchor_id, _cadence, _anchor_at -> 0 end
  end
end
