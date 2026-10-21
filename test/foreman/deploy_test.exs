defmodule Foreman.DeployTest do
  use ExUnit.Case, async: true

  setup do
    root = Path.join(System.tmp_dir!(), "foreman-deploy-#{System.unique_integer([:positive])}")
    releases = Path.join(root, "releases")
    old = Path.join(releases, "previous")
    File.mkdir_p!(Path.join(old, "bin"))
    File.write!(Path.join(old, "bin/foreman"), "old")
    File.ln_s!("releases/previous", Path.join(root, "current"))
    env_file = Path.join(root, "runtime.env")
    File.write!(env_file, "DATABASE_URL=ecto://test:private@localhost/test\n")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, releases: releases, env_file: env_file}
  end

  test "migration phase precedes stop and fails without rollback" do
    assert Foreman.DeployLifecycle.step(:installing, :succeeded, %{}) ==
             {:migrating, [run: :migrate]}

    assert Foreman.DeployLifecycle.step(:migrating, :succeeded, %{}) ==
             {:stopping, [run: :stop]}

    assert Foreman.DeployLifecycle.step(:migrating, :failed, %{}) == {:failed, []}
  end

  test "release smoke selects the installed path rather than the build directory" do
    code = """
    import runpy
    from pathlib import Path
    smoke = runpy.run_path('tools/release-smoke.py')
    assert smoke['release_path'](['--release', '/tmp/installed-foreman']) == Path('/tmp/installed-foreman')
    """

    assert {_, 0} = System.cmd("python3", ["-c", code], stderr_to_stdout: true)
  end

  test "dirty tree and non-main branch refuse before any build", ctx do
    for {git, reason} <- [
          {[dirty: "?? untracked\n"], "Dirty tree"},
          {[branch: "feature\n"], "Not on main"}
        ] do
      assert {:error, message} = deploy(ctx, [], git)
      assert message =~ reason
      refute_received {:command, "mix", _, _}
      assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
    end
  end

  test "migration failure leaves current and running services untouched without leaking output",
       ctx do
    File.write!(Path.join(ctx.root, "services"), "running")

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        captured =
          ExUnit.CaptureIO.capture_io(fn ->
            assert {:error, output} = deploy(ctx, [], migration_status: 1)
            assert output =~ "migrate failed"
            refute output =~ "private"
            refute output =~ "Rollback"
          end)

        refute captured =~ "private"
      end)

    refute logs =~ "private"
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
    assert File.read!(Path.join(ctx.root, "services")) == "running"
    calls = commands()
    refute Enum.any?(calls, fn {exe, _, _} -> exe in ["systemctl", "ln", "mv", "python3"] end)

    assert Enum.any?(calls, fn
             {exe, ["eval", code], env} ->
               assert File.read!(exe) == "new release"
               refute code =~ "private"
               assert {"DATABASE_URL", "ecto://test:private@localhost/test"} in env
               true

             _ ->
               false
           end)

    refute Enum.any?(calls, fn {exe, _, env} ->
             not String.ends_with?(exe, "/bin/foreman") and
               Enum.any?(env, fn {key, _} -> key == "DATABASE_URL" end)
           end)
  end

  test "env-file flag overrides discovery and isolates values from other commands", ctx do
    override = Path.join(ctx.root, "override.env")

    File.write!(
      override,
      "DATABASE_URL=ecto://override:hidden@localhost/test\nSECRET_KEY_BASE=unrelated-secret\n"
    )

    captured =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, output} = deploy(ctx, ["--env-file", override], [])
        refute output =~ "hidden"
        refute output =~ "unrelated-secret"
      end)

    refute captured =~ "hidden"
    refute captured =~ "unrelated-secret"

    for {exe, args, env} <- commands() do
      refute args |> Enum.join(" ") |> String.contains?("hidden")

      if String.ends_with?(exe, "/bin/foreman") do
        assert {"DATABASE_URL", "ecto://override:hidden@localhost/test"} in env
        assert {"SECRET_KEY_BASE", nil} in env
      else
        refute Enum.any?(env, fn {key, _} -> key == "DATABASE_URL" end)
        refute exe == "systemctl" and "show" in args
      end
    end
  end

  test "unreadable env file fails before stopping or switching", ctx do
    assert {:error, output} = deploy(ctx, ["--env-file", Path.join(ctx.root, "missing")], [])
    assert output =~ "migrate failed"
    refute_received {:command, "systemctl", _, _}
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
  end

  test "successful deploy switches to a new complete release and installs CLI last", ctx do
    assert {:ok, output} =
             deploy(ctx, ["--allow-dirty", "--allow-non-main"],
               dirty: " M README.md",
               branch: "feature\n"
             )

    assert output =~ "Smoke passed"
    target = File.read_link!(Path.join(ctx.root, "current"))
    assert File.read!(Path.join(target, "bin/foreman")) == "new release"
    assert File.read!(Path.join(ctx.root, "cli/foreman")) == "new CLI"
    commands = commands()
    smoke = Enum.find_index(commands, fn {exe, _, _} -> exe == "python3" end)

    cli =
      Enum.find_index(commands, fn {exe, args, _} ->
        exe == "mix" and args == ["escript.build"]
      end)

    assert smoke < cli
    temporary = Path.join(ctx.root, "current.deploy-" <> Path.basename(target))

    assert Enum.map(commands, fn {exe, args, _} -> {exe, args} end) == [
             {"git", ["status", "--porcelain"]},
             {"git", ["branch", "--show-current"]},
             {"mix", ["compile"]},
             {"mix", ["assets.deploy"]},
             {"mix", ["release", "--overwrite"]},
             {Path.join(target, "bin/foreman"), ["eval", migration_code()]},
             {"systemctl", ["--user", "stop", "foreman-worker.service", "foreman-web.service"]},
             {"ln", ["-s", target, temporary]},
             {"mv", ["-Tf", temporary, Path.join(ctx.root, "current")]},
             {"systemctl", ["--user", "start", "foreman-web.service", "foreman-worker.service"]},
             {"python3", ["tools/release-smoke.py", "--release", target]},
             {"mix", ["escript.build"]}
           ]

    assert {"systemctl", ["--user", "stop", "foreman-worker.service", "foreman-web.service"], []} in commands

    assert {"systemctl", ["--user", "start", "foreman-web.service", "foreman-worker.service"], []} in commands

    assert {"python3", ["tools/release-smoke.py", "--release", target], []} in commands

    assert Enum.any?(commands, fn {exe, args, env} ->
             exe == "mix" and args == ["assets.deploy"] and env == [{"MIX_ENV", "prod"}]
           end)

    refute Enum.any?(commands, fn {exe, args, _} ->
             exe == "systemctl" and Enum.any?(args, &String.contains?(&1, "tmux"))
           end)

    assert File.exists?(Path.join(ctx.releases, "previous/bin/foreman"))
  end

  test "failed smoke restores previous current, starts services and skips CLI", ctx do
    assert {:error, output} = deploy(ctx, [], smoke_status: 1)
    assert output =~ "Smoke failed"
    assert output =~ "Rollback succeeded"
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
    refute File.exists?(Path.join(ctx.root, "cli/foreman"))
    assert File.read!(Path.join(ctx.root, "services")) == "running"
    commands = commands()

    {"python3", [_, "--release", target], []} =
      Enum.find(commands, fn {exe, _, _} -> exe == "python3" end)

    temporary = Path.join(ctx.root, "current.deploy-" <> Path.basename(target))

    assert Enum.take(commands, -4) == [
             {"systemctl", ["--user", "stop", "foreman-worker.service", "foreman-web.service"],
              []},
             {"ln", ["-s", "releases/previous", temporary], []},
             {"mv", ["-Tf", temporary, Path.join(ctx.root, "current")], []},
             {"systemctl", ["--user", "start", "foreman-web.service", "foreman-worker.service"],
              []}
           ]

    assert Enum.count(commands, fn {exe, args, _} -> exe == "systemctl" and "start" in args end) ==
             2

    refute Enum.any?(commands, fn {exe, args, _} ->
             exe == "systemctl" and Enum.any?(args, &String.contains?(&1, "tmux"))
           end)
  end

  test "second deploy keeps both prior releases and replaces CLI safely", ctx do
    assert {:ok, _} = deploy(ctx, [], [])
    first = File.read_link!(Path.join(ctx.root, "current"))
    assert {:ok, _} = deploy(ctx, [], [])
    second = File.read_link!(Path.join(ctx.root, "current"))
    refute first == second
    assert File.exists?(Path.join(first, "bin/foreman"))
    assert File.exists?(Path.join(second, "bin/foreman"))
    assert length(File.ls!(ctx.releases)) == 3
  end

  test "tmux unit overrides and wildcard service names are refused", ctx do
    for unit <- [
          "foreman-tmux",
          "foreman-tmux.service",
          "foreman-*",
          "FOREMAN-TMUX.service",
          "--all",
          "-a"
        ] do
      assert {:error, _} = deploy(ctx, ["--web-unit=" <> unit], [])
      refute_received {:command, "systemctl", _, _}
    end
  end

  test "equivalent unit names cannot stand in for two services", ctx do
    assert {:error, _} = deploy(ctx, ["--web-unit", "same", "--worker-unit", "same.service"], [])
    refute_received {:command, "systemctl", _, _}
  end

  test "stop and start failures restore the old release and running services", ctx do
    for action <- ["stop", "start"] do
      units =
        if action == "stop",
          do: ["foreman-worker.service", "foreman-web.service"],
          else: ["foreman-web.service", "foreman-worker.service"]

      assert {:error, message} =
               deploy(ctx, [], fail_once: {"systemctl", ["--user", action] ++ units})

      assert message =~ "Rollback succeeded"
      assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
      assert File.read!(Path.join(ctx.root, "services")) == "running"
      refute File.exists?(Path.join(ctx.releases, ".deploy-lock"))
    end
  end

  test "rollback failures are explicit and still attempt service recovery", ctx do
    assert {:error, message} =
             deploy(ctx, [],
               smoke_status: 1,
               fail:
                 {"systemctl",
                  ["--user", "start", "foreman-web.service", "foreman-worker.service"]}
             )

    assert message =~ "Rollback FAILED; manual recovery required"
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"

    assert Enum.count(commands(), fn {exe, args, _} -> exe == "systemctl" and "start" in args end) ==
             2
  end

  test "build failure leaves services and current alone", ctx do
    assert {:error, _} = deploy(ctx, [], fail: {"mix", ["compile"]})
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
    refute_received {:command, "systemctl", _, _}
    refute File.exists?(Path.join(ctx.releases, ".deploy-lock"))
  end

  test "link switch failure rolls back and starts both services", ctx do
    assert {:error, message} = deploy(ctx, [], fail_switch: true)
    assert message =~ "Rollback succeeded"
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"

    assert {"systemctl", ["--user", "start", "foreman-web.service", "foreman-worker.service"], []} in commands()
  end

  test "CLI failure keeps the successfully smoked release", ctx do
    assert {:error, message} = deploy(ctx, [], fail: {"mix", ["escript.build"]})
    assert message =~ "Smoke passed"
    refute File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"

    assert Enum.count(commands(), fn {exe, args, _} -> exe == "systemctl" and "stop" in args end) ==
             1
  end

  test "existing deployment lock refuses without service changes", ctx do
    File.mkdir!(Path.join(ctx.releases, ".deploy-lock"))
    assert {:error, message} = deploy(ctx, [], [])
    assert message =~ "Deployment lock exists"
    refute_received {:command, "systemctl", _, _}
  end

  defp deploy(ctx, flags, behavior) do
    runner = fn exe, args, opts ->
      send(self(), {:command, exe, args, opts[:env]})

      cond do
        behavior[:fail_once] == {exe, args} and
            not Process.get({:failed_once, ctx.root, exe, args}, false) ->
          Process.put({:failed_once, ctx.root, exe, args}, true)
          {"forced once", 1}

        Keyword.get(behavior, :fail) == {exe, args} ->
          {"forced failure", 1}

        behavior[:fail_switch] == true and exe == "ln" and Enum.at(args, 1) != "releases/previous" ->
          {"forced link failure", 1}

        true ->
          stub_command(ctx, behavior, exe, args, opts)
      end
    end

    Foreman.Deploy.run(
      [
        "--env-file",
        ctx.env_file,
        "--releases-dir",
        ctx.releases,
        "--cli-path",
        Path.join(ctx.root, "cli/foreman")
      ] ++ flags,
      cwd: ctx.root,
      command: runner
    )
  end

  defp stub_command(ctx, behavior, exe, args, opts) do
    case {exe, args} do
      {"git", ["status", "--porcelain"]} ->
        {Keyword.get(behavior, :dirty, ""), 0}

      {"git", ["branch", "--show-current"]} ->
        {Keyword.get(behavior, :branch, "main\n"), 0}

      {"mix", ["release", "--overwrite"]} ->
        bin = Path.join(ctx.root, "_build/prod/rel/foreman/bin")
        File.mkdir_p!(bin)
        File.write!(Path.join(bin, "foreman"), "new release")
        {"", 0}

      {"mix", ["escript.build"]} ->
        File.write!(Path.join(ctx.root, "foreman"), "new CLI")
        {"", 0}

      {"systemctl", ["--user", action, _, _]} when action in ["stop", "start"] ->
        File.write!(
          Path.join(ctx.root, "services"),
          if(action == "start", do: "running", else: "stopped")
        )

        {"", 0}

      {_, ["eval", _]} ->
        if behavior[:pending] do
          {Keyword.get(
             behavior,
             :pending_output,
             "ecto://test:private@localhost/test\nFOREMAN_PENDING 20261021123456 add_requests\nFOREMAN_PENDING_DONE\n"
           ), Keyword.get(behavior, :migration_status, 0)}
        else
          {"ecto://test:private@localhost/test", Keyword.get(behavior, :migration_status, 0)}
        end

      {"python3", _} ->
        {"stub smoke", Keyword.get(behavior, :smoke_status, 0)}

      {exe, _} when exe in ["ln", "mv"] ->
        System.cmd(exe, args, opts)

      _ ->
        {"", 0}
    end
  end

  defp migration_code do
    {_, ["eval", code], _} = Foreman.DeployMigration.command("/unused", [], :migrate)
    code
  end

  defp commands(acc \\ []) do
    receive do
      {:command, exe, args, env} -> commands(acc ++ [{exe, args, env}])
    after
      0 -> acc
    end
  end

  test "dry run lists pending names with explicitly supplied environment and never migrates",
       ctx do
    bin = Path.join(ctx.root, "_build/prod/rel/foreman/bin")
    File.mkdir_p!(bin)
    File.write!(Path.join(bin, "foreman"), "built release")

    captured =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, plan} = deploy(ctx, ["--dry-run"], pending: true)
        assert plan =~ "20261021123456 add_requests"
        refute plan =~ "private"
      end)

    refute captured =~ "private"
    calls = commands()
    assert Enum.count(calls, fn {_, args, _} -> match?(["eval", _], args) end) == 1

    refute Enum.any?(calls, fn {exe, args, _} ->
             exe == "mix" or exe == "systemctl" or args == ["eval", migration_code()]
           end)

    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
  end

  test "dry run distinguishes no pending migrations from an unavailable query", ctx do
    bin = Path.join(ctx.root, "_build/prod/rel/foreman/bin")
    File.mkdir_p!(bin)
    File.write!(Path.join(bin, "foreman"), "built release")

    assert {:ok, plan} =
             deploy(ctx, ["--dry-run"], pending: true, pending_output: "FOREMAN_PENDING_DONE\n")

    assert plan =~ "Pending migrations: none"

    for behavior <- [
          [pending: true, pending_output: "private"],
          [pending: true, migration_status: 1]
        ] do
      assert {:ok, plan} = deploy(ctx, ["--dry-run"], behavior)
      assert plan =~ "Pending migrations unavailable"
      refute plan =~ "private"
    end
  end

  test "dry run reports unavailable when release is not built", ctx do
    assert {:ok, plan} = deploy(ctx, ["--dry-run"], [])
    assert plan =~ "Pending migrations unavailable"
    refute Enum.any?(commands(), fn {_, args, _} -> match?(["eval", _], args) end)
  end

  test "dry run prints the ordered plan without changing the release", ctx do
    runner = fn
      "git", ["status", "--porcelain"], _ -> {"", 0}
      "git", ["branch", "--show-current"], _ -> {"main\n", 0}
      exe, args, _ -> flunk("dry run executed #{inspect({exe, args})}")
    end

    assert {:ok, plan} =
             Foreman.Deploy.run(["--dry-run", "--releases-dir", ctx.releases],
               cwd: ctx.root,
               command: runner
             )

    assert plan =~ "MIX_ENV=prod mix compile"
    assert plan =~ "mix assets.deploy"
    assert plan =~ "mix release --overwrite"
    assert plan =~ "stop foreman-worker.service foreman-web.service"
    assert plan =~ "start foreman-web.service foreman-worker.service"
    assert plan =~ "release-smoke.py --release"
    assert plan =~ "MIX_ENV=dev mix escript.build"
    assert plan =~ "Rollback"
    assert plan =~ "Pending migrations unavailable"
    assert plan =~ "--env-file"
    assert plan =~ "Migrate with"
    assert plan =~ "migration failure leaves current and services unchanged"

    positions =
      Enum.map(
        [
          "MIX_ENV=prod mix compile",
          "mix assets.deploy",
          "mix release --overwrite",
          "Copy _build",
          "Migrate with",
          "systemctl --user stop",
          "Atomically switch",
          "systemctl --user start",
          "python3 tools/release-smoke.py --release",
          "MIX_ENV=dev mix escript.build",
          "Install foreman"
        ],
        fn text ->
          {position, _} = :binary.match(plan, text)
          position
        end
      )

    assert positions == Enum.sort(positions)
    assert File.read_link!(Path.join(ctx.root, "current")) == "releases/previous"
    assert File.ls!(ctx.releases) == ["previous"]
  end
end
