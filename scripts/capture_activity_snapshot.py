#!/usr/bin/env python3
import csv
import datetime as dt
import os
import pathlib
import shutil
import subprocess
import sys


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, ""))
    except ValueError:
        return default


home = pathlib.Path.home()
capture_dir = pathlib.Path(os.environ.get("ACTIVITY_CAPTURE_DIR", str(home / "Documents" / "JunimoActivityCaptures")))
start_date = os.environ.get("ACTIVITY_CAPTURE_START_DATE", dt.date.today().isoformat())
max_width = env_int("ACTIVITY_CAPTURE_MAX_WIDTH", 960)
jpeg_quality = env_int("ACTIVITY_CAPTURE_JPEG_QUALITY", 35)
window_start = env_int("ACTIVITY_CAPTURE_WINDOW_START", 1000)
window_end = env_int("ACTIVITY_CAPTURE_WINDOW_END", 2200)
ignore_schedule = os.environ.get("ACTIVITY_CAPTURE_IGNORE_SCHEDULE") == "1"

now = dt.datetime.now()
today = now.date().isoformat()
hhmm = now.hour * 100 + now.minute

if not ignore_schedule:
    if today < start_date:
        sys.exit(0)
    if hhmm < window_start or hhmm > window_end:
        sys.exit(0)

day_dir = capture_dir / today
day_dir.mkdir(parents=True, exist_ok=True)

timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
raw_file = day_dir / f"{timestamp}.raw.png"
out_file = day_dir / f"{timestamp}.jpg"

try:
    subprocess.run(
        ["/usr/sbin/screencapture", "-x", str(raw_file)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
except subprocess.CalledProcessError as error:
    print(error.stderr.strip(), file=sys.stderr)
    sys.exit(error.returncode or 1)
except subprocess.TimeoutExpired:
    print("screencapture timed out", file=sys.stderr)
    sys.exit(1)

if not raw_file.exists():
    print(f"screencapture did not create {raw_file}", file=sys.stderr)
    sys.exit(1)

try:
    subprocess.run(
        [
            "/usr/bin/sips",
            "-s",
            "format",
            "jpeg",
            "-s",
            "formatOptions",
            str(jpeg_quality),
            "-Z",
            str(max_width),
            str(raw_file),
            "--out",
            str(out_file),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
finally:
    raw_file.unlink(missing_ok=True)

if not out_file.exists():
    print(f"sips did not create {out_file}", file=sys.stderr)
    sys.exit(1)

width = ""
height = ""
try:
    result = subprocess.run(
        ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(out_file)],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = line.split(":", 1)[1].strip()
        elif line.startswith("pixelHeight:"):
            height = line.split(":", 1)[1].strip()
except Exception:
    pass

index_file = day_dir / "index.csv"
try:
    needs_header = not index_file.exists()
    with index_file.open("a", newline="") as handle:
        writer = csv.writer(handle)
        if needs_header:
            writer.writerow(["timestamp", "file", "width", "height", "bytes"])
        writer.writerow([timestamp, out_file.name, width, height, out_file.stat().st_size])
except Exception:
    pass

print(out_file)
