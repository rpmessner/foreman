defmodule Foreman.DeployMigrationTest do
  use ExUnit.Case, async: true

  alias Foreman.DeployMigration

  @tag :tmp_dir
  test "override loads literal data, ignores unrelated secrets and never consults units", %{
    tmp_dir: root
  } do
    path = Path.join(root, "override.env")

    File.write!(path, """
    # literal systemd data, not a script
    DATABASE_URL='ecto://test:$(touch nope)@localhost/test'
    POOL_SIZE=4
    ECTO_IPV6="true"
    SECRET_KEY_BASE=do-not-forward
    """)

    assert {:ok, env} = DeployMigration.environment(%{env_file: path})

    assert Map.new(env) == %{
             "DATABASE_URL" => "ecto://test:$(touch nope)@localhost/test",
             "POOL_SIZE" => "4",
             "ECTO_IPV6" => "true"
           }

    refute File.exists?(Path.join(root, "nope"))
  end

  @tag :tmp_dir
  test "discovery loads ordered environment files from both installed units", %{tmp_dir: root} do
    runtime = Path.join(root, "runtime.env")
    web = Path.join(root, "web.env")
    File.write!(runtime, "DATABASE_URL=ecto://test:private@localhost/test\nPOOL_SIZE=2\n")
    File.write!(web, "SECRET_KEY_BASE=never-forward\n")

    runner = fn "systemctl",
                ["--user", "show", "--property=EnvironmentFiles", "--value", unit],
                opts ->
      assert opts[:into] == ""
      assert opts[:env] == []
      extra = if unit == "web.service", do: " #{web} (ignore_errors=no)", else: ""
      {runtime <> " (ignore_errors=no)" <> extra <> "\n", 0}
    end

    config = %{
      env_file: nil,
      command: runner,
      cwd: root,
      worker: "worker.service",
      web: "web.service"
    }

    assert {:ok, env} = DeployMigration.environment(config)

    assert Map.new(env) == %{
             "DATABASE_URL" => "ecto://test:private@localhost/test",
             "POOL_SIZE" => "2"
           }

    File.write!(web, "DATABASE_URL=ecto://different/database\n")
    assert {:error, :environment_unavailable} = DeployMigration.environment(config)
  end

  test "pending command cannot create the migration table or take migration locks" do
    {_, ["eval", code], opts} = DeployMigration.command("/new/release", [], :pending)
    assert code =~ "skip_table_creation: true"
    assert code =~ "migration_lock: false"
    refute code =~ "Ecto.Migrator.run"
    assert opts[:into] == ""
  end

  @tag :tmp_dir
  test "quoted Unicode values are preserved and malformed quoting fails closed", %{tmp_dir: root} do
    path = Path.join(root, "runtime.env")
    File.write!(path, "DATABASE_URL='ecto://test:páss@localhost/test'\n")

    assert {:ok, [{"DATABASE_URL", "ecto://test:páss@localhost/test"}]} =
             DeployMigration.environment(%{env_file: path})

    for raw <- ["'one'two'", "\"one\"two\"", "value\\\ncontinued", "'not closed"] do
      File.write!(path, "DATABASE_URL=" <> raw)
      assert {:error, _} = DeployMigration.environment(%{env_file: path})
    end
  end

  @tag :tmp_dir
  test "child stdout and stderr containing credentials are captured, never streamed", %{
    tmp_dir: root
  } do
    bin = Path.join(root, "bin")
    File.mkdir_p!(bin)

    File.write!(
      Path.join(bin, "foreman"),
      "#!/bin/sh\nprintf '%s' \"$DATABASE_URL\"\nprintf '%s' \"$DATABASE_URL\" >&2\nexit 1\n"
    )

    File.chmod!(Path.join(bin, "foreman"), 0o700)

    {executable, args, opts} =
      DeployMigration.command(root, [{"DATABASE_URL", "fake-private-value"}], :migrate)

    captured =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {output, 1} = System.cmd(executable, args, opts ++ [stderr_to_stdout: true])
        assert output == "fake-private-valuefake-private-value"
      end)

    assert captured == ""
  end

  test "migration command carries database settings only in the child environment" do
    secret = "ecto://test:private@localhost/test"

    assert {executable, ["eval", code], opts} =
             DeployMigration.command("/new/release", [{"DATABASE_URL", secret}], :migrate)

    assert executable == "/new/release/bin/foreman"
    assert code =~ "Ecto.Migrator.with_repo"
    assert code =~ "Ecto.Migrator.run(repo, :up, all: true)"
    refute code =~ secret
    assert opts[:env] |> Map.new() |> Map.fetch!("DATABASE_URL") == secret
    assert {"FOREMAN_ROLE", "worker"} in opts[:env]
    assert {"PHX_SERVER", nil} in opts[:env]
    assert {"SECRET_KEY_BASE", nil} in opts[:env]
    assert {"POOL_SIZE", nil} in opts[:env]
    assert {"ECTO_IPV6", nil} in opts[:env]
    assert {"ERL_CRASH_DUMP", "/dev/null"} in opts[:env]
    assert opts[:into] == ""
  end
end
