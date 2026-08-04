defmodule SymphonyElixir.LinearClientDaemonCommentsTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.Issue

  test "poll-shaped candidate fetch reads engine workpad anchor metadata and blocker labels" do
    raw_issue =
      raw_linear_issue(%{
        "labels" => %{"nodes" => [%{"name" => " wake:15m "}, %{"name" => "Pink"}]},
        "inverseRelations" => %{
          "nodes" => [
            %{
              "type" => "blocks",
              "issue" => %{
                "id" => "blocker-1",
                "identifier" => "ABC-100",
                "state" => %{"name" => "In Progress"},
                "labels" => %{"nodes" => [%{"name" => " Mature "}, %{"name" => "Pink"}]}
              }
            }
          ]
        },
        "comments" => %{
          "nodes" => [
            %{
              "id" => "comment-1",
              "createdAt" => "2026-07-25T16:37:19.692Z",
              "updatedAt" => "2026-07-25T17:35:21.968Z",
              "body" => "## Symphony Workpad\nbody stays out of steady-state polling"
            }
          ]
        }
      })

    with_linear_graphql_stub(
      %{
        "data" => %{
          "issues" => %{
            "nodes" => [raw_issue],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          }
        }
      },
      fn endpoint ->
        write_workflow_file!(Workflow.workflow_file_path(),
          tracker_endpoint: endpoint,
          tracker_project_slug: "daemon-project",
          tracker_active_states: ["Happy", "Unhappy"]
        )

        assert {:ok, [issue]} = Client.fetch_candidate_issues()

        assert issue.labels == ["wake:15m", "pink"]

        assert issue.blocked_by == [
                 %{id: "blocker-1", identifier: "ABC-100", state: "In Progress", labels: ["mature", "pink"]}
               ]

        assert issue.comments == [
                 %{id: "comment-1", updated_at: ~U[2026-07-25 17:35:21.968Z]}
               ]

        [comment] = issue.comments
        refute Map.has_key?(comment, :created_at)
        refute Map.has_key?(comment, :body)
      end
    )

    assert_receive {:linear_graphql_request, %{"query" => query, "variables" => variables}}
    assert query =~ "issues("

    assert query =~
             "comments(first: $commentFirst, orderBy: updatedAt, filter: {body: {startsWithIgnoreCase: $commentAnchorTitle}})"

    assert query =~ "updatedAt"
    # `body` appears in the filter expression; this only rejects a selected body field.
    refute query =~ ~r/\n\s+body\s*\n/
    # >= 2 so DaemonWake's :duplicate_workpad_anchors warning is reachable;
    # first: 1 would silently make it dead code.
    assert variables["commentFirst"] == 2
    assert variables["commentAnchorTitle"] == Issue.workpad_title()
    assert variables["relationFirst"] == 50
  end

  test "daemon state fetch preserves configured casing in Linear state filter" do
    with_linear_graphql_stub(
      %{
        "data" => %{
          "issues" => %{
            "nodes" => [],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          }
        }
      },
      fn endpoint ->
        write_workflow_file!(Workflow.workflow_file_path(),
          tracker_endpoint: endpoint,
          tracker_project_slug: "daemon-project"
        )

        assert {:ok, []} = Client.fetch_issues_by_states(["Happy", "Unhappy"])
      end
    )

    assert_receive {:linear_graphql_request, %{"query" => query, "variables" => variables}}
    assert query =~ "state: {name: {in: $stateNames}}"
    assert variables["stateNames"] == ["Happy", "Unhappy"]
  end

  test "issue refetch by id preserves comment metadata and blocker labels" do
    graphql_fun = fn query, variables ->
      send(self(), {:fetch_issue_states_request, query, variables})

      {:ok,
       %{
         "data" => %{
           "issues" => %{
             "nodes" => [
               raw_linear_issue(%{
                 "id" => "issue-1",
                 "comments" => %{
                   "nodes" => [
                     %{"id" => "comment-1", "updatedAt" => "2026-07-25T17:35:21.968Z"}
                   ]
                 },
                 "inverseRelations" => %{
                   "nodes" => [
                     %{
                       "type" => "blocks",
                       "issue" => %{
                         "id" => "blocker-1",
                         "identifier" => "ABC-100",
                         "state" => %{"name" => "Done"},
                         "labels" => %{"nodes" => [%{"name" => "Mature"}]}
                       }
                     }
                   ]
                 }
               })
             ]
           }
         }
       }}
    end

    assert {:ok, [issue]} = Client.fetch_issue_states_by_ids_for_test(["issue-1"], graphql_fun)

    assert issue.comments == [%{id: "comment-1", updated_at: ~U[2026-07-25 17:35:21.968Z]}]
    assert issue.blocked_by == [%{id: "blocker-1", identifier: "ABC-100", state: "Done", labels: ["mature"]}]

    assert_receive {:fetch_issue_states_request, query,
                    %{
                      ids: ["issue-1"],
                      commentFirst: 2,
                      commentAnchorTitle: comment_anchor_title
                    }}

    assert comment_anchor_title == Issue.workpad_title()

    assert query =~ "SymphonyLinearIssuesById"

    assert query =~
             "comments(first: $commentFirst, orderBy: updatedAt, filter: {body: {startsWithIgnoreCase: $commentAnchorTitle}})"

    # `body` appears in the filter expression; this only rejects a selected body field.
    refute query =~ ~r/\n\s+body\s*\n/
  end

  test "narrow comment body fetch requests body by comment id only" do
    graphql_fun = fn query, variables ->
      send(self(), {:fetch_comment_body_request, query, variables})

      {:ok,
       %{
         "data" => %{
           "comment" => %{
             "id" => "comment-1",
             "body" => "## Codex Workpad\nwriter title lives here"
           }
         }
       }}
    end

    assert {:ok, "## Codex Workpad\nwriter title lives here"} =
             Client.fetch_comment_body_for_test("comment-1", graphql_fun)

    assert_receive {:fetch_comment_body_request, query, variables}
    assert query =~ "comment(id: $commentId)"
    assert query =~ "body"
    assert variables.commentId == "comment-1"
    refute query =~ "issues("
  end

  test "narrow comment body fetch reports missing comments" do
    graphql_fun = fn _query, _variables ->
      {:ok, %{"data" => %{"comment" => nil}}}
    end

    assert {:error, :comment_not_found} =
             Client.fetch_comment_body_for_test("missing-comment", graphql_fun)
  end

  test "narrow issue history fetch requests state transitions only" do
    graphql_fun = fn query, variables ->
      send(self(), {:fetch_issue_history_request, query, variables})

      {:ok,
       %{
         "data" => %{
           "issue" => %{
             "history" => %{
               "nodes" => [
                 %{
                   "createdAt" => "2026-07-27T01:29:03.000Z",
                   "fromState" => %{"name" => "Human Input Needed"},
                   "toState" => %{"name" => "Rework"}
                 },
                 %{
                   "createdAt" => "2026-07-27T00:40:33.000Z",
                   "fromState" => %{"name" => "Happy"},
                   "toState" => %{"name" => "Evaluating"}
                 }
               ]
             }
           }
         }
       }}
    end

    assert {:ok,
            [
              %{
                created_at: ~U[2026-07-27 01:29:03.000Z],
                from_state: "Human Input Needed",
                to_state: "Rework"
              },
              %{created_at: ~U[2026-07-27 00:40:33.000Z], from_state: "Happy", to_state: "Evaluating"}
            ]} = Client.fetch_issue_state_history_for_test("issue-1", 6, graphql_fun)

    assert_receive {:fetch_issue_history_request, query, %{issueId: "issue-1", first: 6}}
    assert query =~ "issue(id: $issueId)"
    assert query =~ "history(first: $first)"
    assert query =~ "fromState"
    assert query =~ "toState"
    refute query =~ "comments("
  end

  defp with_linear_graphql_stub(response_body, fun) when is_map(response_body) and is_function(fun, 1) do
    parent = self()

    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_ip, port}} = :inet.sockname(listen_socket)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket, 5_000)
        {:ok, payload} = receive_http_payload(socket)
        send(parent, {:linear_graphql_request, Jason.decode!(payload)})

        body = Jason.encode!(response_body)

        response = [
          "HTTP/1.1 200 OK\r\n",
          "content-type: application/json\r\n",
          "content-length: #{byte_size(body)}\r\n",
          "connection: close\r\n",
          "\r\n",
          body
        ]

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
      end)

    try do
      fun.("http://127.0.0.1:#{port}")
      Task.await(task, 5_000)
    after
      :gen_tcp.close(listen_socket)
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp receive_http_payload(socket), do: receive_http_payload(socket, "")

  defp receive_http_payload(socket, acc) do
    case complete_http_payload(acc) do
      {:ok, payload} ->
        {:ok, payload}

      :more ->
        with {:ok, chunk} <- :gen_tcp.recv(socket, 0, 5_000) do
          receive_http_payload(socket, acc <> chunk)
        end
    end
  end

  defp complete_http_payload(request) do
    case :binary.match(request, "\r\n\r\n") do
      {header_end, 4} ->
        body_start = header_end + 4
        headers = binary_part(request, 0, header_end)
        body = binary_part(request, body_start, byte_size(request) - body_start)
        content_length = http_content_length(headers)

        if byte_size(body) >= content_length do
          {:ok, binary_part(body, 0, content_length)}
        else
          :more
        end

      :nomatch ->
        :more
    end
  end

  defp http_content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(0, &http_content_length_header/1)
  end

  defp http_content_length_header(header) do
    case String.split(header, ":", parts: 2) do
      [name, value] -> parse_content_length_header(String.downcase(name), value)
      _ -> nil
    end
  end

  defp parse_content_length_header("content-length", value), do: String.trim(value) |> String.to_integer()
  defp parse_content_length_header(_name, _value), do: nil

  defp raw_linear_issue(overrides) do
    Map.merge(
      %{
        "id" => "issue-1",
        "identifier" => "ABC-287",
        "title" => "Daemon comment binding",
        "description" => "Ready for daemon Linear plumbing",
        "priority" => 2,
        "state" => %{"name" => "Happy"},
        "branchName" => "abc-287",
        "url" => "https://linear.app/orchestrabio/issue/ABC-287/example",
        "labels" => %{"nodes" => []},
        "inverseRelations" => %{"nodes" => []},
        "comments" => %{"nodes" => []},
        "createdAt" => "2026-07-25T00:00:00Z",
        "updatedAt" => "2026-07-25T00:01:00Z"
      },
      overrides
    )
  end
end
