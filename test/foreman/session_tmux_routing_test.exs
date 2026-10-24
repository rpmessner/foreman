defmodule Foreman.SessionTmuxRoutingTest do
  use Foreman.DataCase, async: false
  alias Foreman.SessionTmux, as: Tmux

  setup c do
    socket = "fm-routing-#{Ecto.UUID.generate()}"
    dir = Path.join(System.tmp_dir!(), socket)
    File.mkdir_p!(dir)

    {_, 0} =
      System.cmd("tmux", [
        "-L",
        socket,
        "-f",
        "/dev/null",
        "start-server",
        ";",
        "set-option",
        "-g",
        "exit-empty",
        "off",
        ";",
        "set-option",
        "-g",
        "default-shell",
        "/bin/sh"
      ])

    executable = Path.join(dir, "receiver")

    File.write!(
      executable,
      "#!/bin/sh\nprintf ready > \"ready-$2\"\nIFS= read -r line || exit 0\nprintf '%s' \"$line\" > received\nread more\n"
    )

    File.chmod!(executable, 0o700)

    {:ok, config} =
      Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

    config = if c.shared, do: put_in(config, ["board", "tmux_session"], "board"), else: config

    Foreman.Repo.insert_all("board_config", [
      %{id: 1, config: config, source: "test", discovered: [], loaded_at: DateTime.utc_now()}
    ])

    on_exit(fn ->
      System.cmd("tmux", ["-L", socket, "kill-server"], stderr_to_stdout: true)
      File.rm_rf!(dir)
    end)

    %{socket: socket, dir: dir, opts: [socket: socket, executable: executable]}
  end

  for shared <- [false, true] do
    @tag shared: shared
    test "launch routing and pane ownership with shared=#{shared}", c do
      run = fn args ->
        {out, 0} = System.cmd("tmux", ["-L", c.socket] ++ args)
        String.trim(out)
      end

      first = %{
        project: "alpha",
        ticket: "x-1.2",
        session_id: Ecto.UUID.generate(),
        workdir: c.dir
      }

      other_dir = Path.join(c.dir, "other")
      File.mkdir_p!(other_dir)
      other = %{first | project: "beta", session_id: Ecto.UUID.generate(), workdir: other_dir}

      coordinator = %{
        first
        | project: "__foreman__",
          ticket: "coordinator",
          session_id: Ecto.UUID.generate()
      }

      assert {:ok, a} = Tmux.launch(first, "flow", c.opts)
      assert {:ok, b} = Tmux.launch(other, "flow", c.opts)
      assert {:ok, co} = Tmux.launch(coordinator, "/orient", c.opts)
      refute a == b

      expected =
        if c.shared,
          do: ["board|alpha/x-1.2", "board|beta/x-1.2", "board|__foreman__/coordinator"],
          else: ["alpha|x-1.2", "beta|x-1.2", "coordinator|coordinator"]

      rows = run.(["list-windows", "-a", "-F", ~S(#{session_name}|#{window_name})])
      assert Enum.sort(String.split(rows, "\n")) == Enum.sort(expected)
      assert {:ok, ^a} = Tmux.launch(first, "ignored", c.opts)
      assert {:ok, %{window: ^b}} = Tmux.observe(other, c.opts)
      first = Map.put(first, :window, a)

      assert eventually(fn ->
               File.exists?(Path.join(c.dir, "ready-#{first.session_id}")) and
                 File.exists?(Path.join(other_dir, "ready-#{other.session_id}"))
             end)

      assert eventually(fn ->
               Tmux.observe(first, c.opts) == {:ok, %{window: a, state: :running}}
             end)

      pane = run.(["display-message", "-p", "-t", a, ~S(#{pane_id})])
      build = run.(["split-window", "-t", a, "-P", "-F", ~S(#{pane_id}), "cat"])
      assert :ok = Tmux.focus_build("alpha", build, c.opts)
      active_session = if c.shared, do: "=board:", else: "=alpha:"

      assert run.(["display-message", "-p", "-t", active_session, ~S(#{window_id}|#{pane_id})]) ==
               "#{a}|#{build}"

      assert {:error, :invalid_window} = Tmux.focus_build("beta", build, c.opts)
      assert {:error, :invalid_window} = Tmux.focus_build("alpha", b, c.opts)
      assert :ok = Tmux.focus_build("alpha", "x-1.2", c.opts)
      assert :ok = Tmux.focus(first, c.opts)
      assert {:error, :no_client} = Tmux.open_session(first, c.opts)
      assert :ok = Tmux.continue_session(first, c.opts)
      assert eventually(fn -> File.exists?(Path.join(c.dir, "received")) end)
      assert File.read!(Path.join(c.dir, "received")) == "continue"
      refute File.exists?(Path.join(other_dir, "received"))
      assert run.(["display-message", "-p", "-t", a, ~S(#{pane_id})]) == build

      client =
        Port.open({:spawn_executable, System.find_executable("tmux")}, [
          :binary,
          :exit_status,
          args: ["-L", c.socket, "-C", "attach", "-t", b]
        ])

      assert eventually(fn ->
               Tmux.attached?(Map.put(other, :window, b), c.opts) == {:ok, true}
             end)

      assert :ok = Tmux.open_session(first, c.opts)
      assert run.(["display-message", "-p", "-t", a, ~S(#{pane_id})]) == pane
      Port.close(client)
      attach_session = if c.shared, do: "board", else: "alpha"

      assert Tmux.attach_command(first, c.opts) ==
               "tmux -L '#{c.socket}' attach -t '#{attach_session}:#{a}'"

      assert {:ok, %{window: ^co}} = Tmux.observe(coordinator, c.opts)

      draft = %{
        first
        | ticket: "draft:arrangement",
          session_id: Ecto.UUID.generate(),
          window: nil
      }

      assert {:ok, draft_window} = Tmux.launch(draft, "flow", c.opts)
      assert {:ok, %{window: ^draft_window}} = Tmux.observe(draft, c.opts)
      assert {:ok, ^draft_window} = Tmux.launch(draft, "ignored", c.opts)

      draft_location =
        if c.shared, do: "board|alpha/draft:arrangement", else: "alpha|draft:arrangement"

      assert run.([
               "display-message",
               "-p",
               "-t",
               draft_window,
               ~S(#{session_name}|#{window_name})
             ]) == draft_location

      socket_path = run.(["display-message", "-p", "-t", co, ~S(#{socket_path})])
      co_pane = run.(["display-message", "-p", "-t", co, ~S(#{pane_id})])

      assert {:ok, ^co} =
               Tmux.coordinator_pane(%{"socket" => socket_path, "pane" => co_pane}, c.opts)

      assert {:error, :invalid_coordinator_pane} =
               Tmux.coordinator_pane(%{"socket" => socket_path, "pane" => pane}, c.opts)

      assert eventually(fn ->
               File.exists?(Path.join(c.dir, "ready-#{draft.session_id}")) and
                 File.exists?(Path.join(c.dir, "ready-#{coordinator.session_id}"))
             end)

      foreign_pane = run.(["display-message", "-p", "-t", b, ~S(#{pane_id})])
      run.(["set-option", "-w", "-t", a, "@foreman-pane", foreign_pane])
      assert {:error, :window_gone} = Tmux.open_session(first, c.opts)
      assert {:error, :invalid_window} = Tmux.continue_session(first, c.opts)
      refute File.exists?(Path.join(other_dir, "received"))
      File.mkdir_p!("tmp")

      File.write!(
        "tmp/session-routing-#{c.shared}.txt",
        "Scratch socket: #{c.socket}\n#{rows}\n#{draft_location}\nWindows: #{a}, #{b}, #{co}; draft: #{draft_window}\nCoordinator pane: #{pane}; build pane: #{build}\nContinue received by alpha only; beta received nothing.\nFocus refused beta access to alpha's build pane.\nOpen session selected the marked pane with a client attached.\nForeign pane marker refused by Open session and Continue.\nAttach: #{Tmux.attach_command(first, c.opts)}\n"
      )
    end
  end

  @tag shared: true
  test "simultaneous first launches both get a window in the shared session", c do
    parent = self()

    runner = fn exe, args, opts ->
      if "new-session" in args do
        send(parent, {:creating, self()})

        receive do
          :create -> :ok
        after
          5_000 -> raise "launch barrier timed out"
        end
      end

      System.cmd(exe, args, opts)
    end

    tasks =
      for project <- ["alpha", "beta"] do
        Task.async(fn ->
          Tmux.launch(
            %{project: project, ticket: "x-1", session_id: Ecto.UUID.generate(), workdir: c.dir},
            "flow",
            Keyword.put(c.opts, :runner, runner)
          )
        end)
      end

    assert_receive {:creating, first}, 5_000
    assert_receive {:creating, second}, 5_000
    send(first, :create)
    send(second, :create)
    for task <- tasks, do: assert({:ok, _} = Task.await(task))
    assert eventually(fn -> length(Path.wildcard(Path.join(c.dir, "ready-*"))) == 2 end)

    assert {rows, 0} =
             System.cmd("tmux", [
               "-L",
               c.socket,
               "list-windows",
               "-a",
               "-F",
               ~S(#{session_name}|#{window_name})
             ])

    assert Enum.sort(String.split(rows, "\n", trim: true)) == [
             "board|alpha/x-1",
             "board|beta/x-1"
           ]
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (receive do
         after
           20 -> eventually(fun, attempts - 1)
         end)
  end
end
