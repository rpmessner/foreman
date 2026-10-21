#!/usr/bin/env python3
"""Exercise the packaged release with a synthetic export, never a real bd store.

Uses a newly created disposable local Postgres database (the test credentials),
non-default ports and scratch files under this checkout's ignored tmp directory.
No systemd installation or user configuration is touched.
"""

import argparse
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "_build/prod/rel/foreman"
def release_path(args=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, default=RELEASE,
                        help="release directory to exercise (default: build output)")
    return parser.parse_args(args).release.expanduser().resolve()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(check, processes, description):
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        for process in processes:
            assert process.poll() is None, f"release exited: {process.returncode}"
        if check():
            return
        time.sleep(0.1)
    raise AssertionError(f"timed out: {description}")


def main():
    bin_path = release_path() / "bin/foreman"
    assert bin_path.is_file(), "build with MIX_ENV=prod mix release first"
    (ROOT / "tmp").mkdir(exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="release-smoke-", dir=ROOT / "tmp"))
    print(f"Artifacts: {scratch.relative_to(ROOT)}", flush=True)
    repo = scratch / "repo"
    store = repo / ".beads/embeddeddolt/test/.dolt/noms"
    store.mkdir(parents=True)
    (store / "LOCK").touch()
    (repo / ".beads/metadata.json").write_text('{"dolt_mode":"embedded"}')
    (repo / "export.jsonl").write_bytes((ROOT / "test/fixtures/beads/export.jsonl").read_bytes())
    fixture_bin = scratch / "bin"
    fixture_bin.mkdir()
    exporter = fixture_bin / "bd"
    exporter.write_text('#!/bin/sh\n[ "$1" = export ] || exit 99\nexec /bin/cat export.jsonl\n')
    exporter.chmod(0o755)
    config = scratch / "config"
    config.mkdir()
    (config / "foreman.toml").write_text(
        f'[[repos]]\nkey = "release-smoke"\npath = "{repo}"\nenabled = true\n'
    )
    vm_args = scratch / "vm.args"
    probe_path = list(os.fsencode(ROOT / "tools/release-smoke.exs"))
    vm_args.write_text(f'-eval "\'Elixir.Code\':eval_file(list_to_binary({probe_path}))."\n')
    # Do not inherit shell credentials, VM flags, routing overrides or Fluxon values.
    env = {
        "HOME": str(scratch),
        "PATH": f"{fixture_bin}:/usr/local/bin:/usr/bin:/bin",
        "LANG": "C.UTF-8",
        "DATABASE_URL": f"ecto://postgres:postgres@localhost/foreman_release_{secrets.token_hex(6)}_test",
        "FOREMAN_ROLE": "worker",
        "FOREMAN_CONFIG_DIR": str(config),
        "FOREMAN_DISCOVERY_ROOT": str(repo),
        "RELEASE_DISTRIBUTION": "none",
        "RELEASE_TMP": str(scratch / "runtime"),
        "ERL_FLAGS": "+S 2:2",
    }
    database_setup = '''
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    :ok = Ecto.Adapters.Postgres.storage_up(Foreman.Repo.config())
    IO.puts("SMOKE_DATABASE_CREATED")
    {:ok, _, _} = Ecto.Migrator.with_repo(Foreman.Repo, &Ecto.Migrator.run(&1, :up, all: true))
    IO.puts("SMOKE_DATABASE_MIGRATED")
    '''
    database_cleanup = '''
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    :ok = Ecto.Adapters.Postgres.storage_down(Foreman.Repo.config())
    IO.puts("SMOKE_DATABASE_DROPPED")
    '''
    processes = []
    logs = []
    try:
        with (scratch / "database.log").open("w") as log:
            subprocess.run([str(bin_path), "eval", database_setup], env=env, cwd=scratch,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
        ports = {"web": free_port(), "worker": free_port()}
        while ports["worker"] == ports["web"]:
            ports["worker"] = free_port()
        for role in ("web", "worker"):
            role_env = env | {
                "FOREMAN_ROLE": role,
                "PORT": str(ports[role]),
                "PHX_SERVER": "true",
                "RELEASE_VM_ARGS": str(vm_args),
            }
            if role == "web":
                role_env["SECRET_KEY_BASE"] = secrets.token_urlsafe(64)
            log_path = scratch / f"{role}.log"
            log = log_path.open("w")
            logs.append(log)
            process = subprocess.Popen([str(bin_path), "start"], env=role_env, cwd=scratch,
                                       stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            processes.append(process)
            marker = f"SMOKE_{role.upper()}_READY"
            wait_for(lambda: marker in log_path.read_text(), processes, marker)
            print(next(line for line in log_path.read_text().splitlines() if marker in line), flush=True)
        wait_for(lambda: "SMOKE_WEB_RECEIVED_SYNC_VIA_POSTGRES" in (scratch / "web.log").read_text(),
                 processes, "cross-role sync")
        print("SMOKE_WEB_RECEIVED_SYNC_VIA_POSTGRES", flush=True)
        with urllib.request.urlopen(f"http://127.0.0.1:{ports['web']}/settings", timeout=5) as response:
            assert response.status == 200
            html = response.read()
            assert b"release-smoke" in html
            assert b"foreman</title>" in html
            assert b"> foreman" in html
        with urllib.request.urlopen(f"http://127.0.0.1:{ports['web']}/images/favicon.svg", timeout=5) as response:
            assert response.status == 200
            assert b'aria-label="foreman"' in response.read()
        print("SMOKE_WEB_HTTP_200_WITH_SYNCED_REPO_AND_FOREMAN_BRANDING", flush=True)
        with socket.socket() as sock:
            assert sock.connect_ex(("127.0.0.1", ports["worker"])) != 0
        print("SMOKE_WORKER_PORT_CLOSED", flush=True)
        for process in reversed(processes):
            process.send_signal(signal.SIGTERM)
            assert process.wait(timeout=90) == 0
        print("SMOKE_BOTH_SIGTERM_EXIT_0", flush=True)
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                try:
                    process.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        for log in logs:
            log.close()
        if "SMOKE_DATABASE_CREATED" in (scratch / "database.log").read_text():
            subprocess.run([str(bin_path), "eval", database_cleanup], env=env, cwd=scratch,
                           check=True, timeout=60)


if __name__ == "__main__":
    main()
