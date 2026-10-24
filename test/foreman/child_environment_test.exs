defmodule Foreman.ChildEnvironmentTest do
  use ExUnit.Case, async: true

  alias Foreman.ChildEnvironment

  test "launch command replaces inherited environment and preserves literal arguments" do
    environment = %{"PATH" => "/usr/bin:/bin", "FOREMAN_SESSION" => "user's build\n2"}
    command = ChildEnvironment.command(environment, ["/usr/bin/printenv", "FOREMAN_SESSION"])

    assert {"user's build\n2\n", 0} =
             System.cmd("/bin/sh", ["-c", command],
               env: [{"FOREMAN_DATABASE_URL", "test-only"}, {"RELEASE_NAME", "foreman"}]
             )

    assert {output, 0} =
             System.cmd(
               "/bin/sh",
               ["-c", ChildEnvironment.command(environment, ["/usr/bin/env"])],
               env: [{"FOREMAN_DATABASE_URL", "test-only"}, {"PHX_SERVER", "true"}]
             )

    assert output |> String.split("\n", trim: true) |> Enum.sort() ==
             ["2", "FOREMAN_SESSION=user's build", "PATH=/usr/bin:/bin"]
  end

  test "stale release PATH entries are removed even after release variables are gone" do
    assert ChildEnvironment.clean(%{
             "PATH" => "/old/erts-15/bin/:/old/bin/:/new/bin:/new/erts-16/bin:/user/bin:/usr/bin",
             "ERL_ROOTDIR" => "/old",
             "ERL_AFLAGS" => "+pc unicode"
           }) == %{"PATH" => "/user/bin:/usr/bin", "ERL_AFLAGS" => "+pc unicode"}
  end

  test "release environment becomes a user environment without losing session facts" do
    environment = %{
      "PATH" =>
        "/srv/foreman/releases/old/erts-16.0/bin:/srv/foreman/releases/old/bin:/fixture/user/.local/bin:/usr/bin:/opt/other/bin",
      "RELEASE_ROOT" => "/srv/foreman/releases/old",
      "RELEASE_NAME" => "foreman",
      "RELEASE_RANDOM" => "release value",
      "ERTS_BIN" => "/srv/foreman/releases/old/erts-16.0/bin",
      "ERTS_LIB_DIR" => "/srv/foreman/releases/old/lib",
      "ROOTDIR" => "/srv/foreman/releases/old",
      "BINDIR" => "/srv/foreman/releases/old/erts-16.0/bin",
      "EMU" => "beam",
      "PROGNAME" => "erl",
      "FOREMAN_DATABASE_URL" => "test-only",
      "SECRET_KEY_BASE" => "test-only",
      "PHX_SERVER" => "true",
      "PHX_OTHER" => "test-only",
      "HOME" => "/fixture/user",
      "FOREMAN_SESSION" => "build-1",
      "FOREMAN_ACTOR" => "pi",
      "FOREMAN_URL" => "http://127.0.0.1:4747",
      "FOREMAN_TOKEN_FILE" => "/test/token"
    }

    assert ChildEnvironment.clean(environment) == %{
             "PATH" => "/fixture/user/.local/bin:/usr/bin:/opt/other/bin",
             "HOME" => "/fixture/user",
             "FOREMAN_SESSION" => "build-1",
             "FOREMAN_ACTOR" => "pi",
             "FOREMAN_URL" => "http://127.0.0.1:4747",
             "FOREMAN_TOKEN_FILE" => "/test/token"
           }
  end
end
