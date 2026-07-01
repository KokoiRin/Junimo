#!/usr/bin/env python3
import datetime as dt
import os
import pathlib
import subprocess
import sys
import time


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, ""))
    except ValueError:
        return default


repo_root = pathlib.Path(__file__).resolve().parents[1]
installed_capture_script = pathlib.Path(__file__).resolve().with_name("capture_activity_snapshot.py")
repo_capture_script = repo_root / "scripts" / "capture_activity_snapshot.py"
capture_script = installed_capture_script if installed_capture_script.exists() else repo_capture_script
support_dir = pathlib.Path.home() / "Library" / "Application Support" / "Junimo" / "ActivityCapture"
support_dir.mkdir(parents=True, exist_ok=True)
pid_file = support_dir / "activity-capture-loop.pid"
log_file = support_dir / "activity-capture-loop.log"

interval = env_int("ACTIVITY_CAPTURE_INTERVAL_SECONDS", 60)
max_runs = env_int("ACTIVITY_CAPTURE_LOOP_MAX_RUNS", 0)


def log(message: str) -> None:
    timestamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{timestamp} {message}\n"
    with log_file.open("a") as handle:
        handle.write(line)
    print(line, end="", flush=True)


def sleep_until_next_tick() -> None:
    now = time.time()
    next_tick = now - (now % interval) + interval
    time.sleep(max(1, next_tick - now))


pid_file.write_text(str(os.getpid()))
log(f"loop-start pid={os.getpid()} interval={interval} script={capture_script}")

run_count = 0
while True:
    run_count += 1
    started = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    result = subprocess.run(
        ["/usr/bin/python3", str(capture_script)],
        text=True,
        capture_output=True,
        env=os.environ.copy(),
    )
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()
    if result.returncode == 0:
        log(f"capture-ok run={run_count} started={started} output={stdout}")
    else:
        log(f"capture-failed run={run_count} started={started} code={result.returncode} stderr={stderr}")

    if max_runs > 0 and run_count >= max_runs:
        log(f"loop-stop reason=max-runs run_count={run_count}")
        break
    sleep_until_next_tick()

try:
    if pid_file.read_text().strip() == str(os.getpid()):
        pid_file.unlink()
except Exception:
    pass
