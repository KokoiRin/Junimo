#!/usr/bin/env zsh
set -euo pipefail

CAPTURE_DIR="${ACTIVITY_CAPTURE_DIR:-$HOME/Documents/JunimoActivityCaptures}"
START_DATE="${ACTIVITY_CAPTURE_START_DATE:-2026-06-29}"
MAX_WIDTH="${ACTIVITY_CAPTURE_MAX_WIDTH:-960}"
JPEG_QUALITY="${ACTIVITY_CAPTURE_JPEG_QUALITY:-35}"
WINDOW_START="${ACTIVITY_CAPTURE_WINDOW_START:-1000}"
WINDOW_END="${ACTIVITY_CAPTURE_WINDOW_END:-2200}"
IGNORE_SCHEDULE="${ACTIVITY_CAPTURE_IGNORE_SCHEDULE:-0}"

today="$(date +%Y-%m-%d)"
hhmm="$(date +%H%M)"

# 业务边界：定时器可以全天唤醒，但只有指定日期和时间窗内才落盘截图。
if [[ "$IGNORE_SCHEDULE" != "1" ]]; then
  if [[ "$today" < "$START_DATE" ]]; then
    exit 0
  fi

  if (( 10#$hhmm < 10#$WINDOW_START || 10#$hhmm > 10#$WINDOW_END )); then
    exit 0
  fi
fi

day_dir="$CAPTURE_DIR/$today"
mkdir -p "$day_dir"

lock_dir="$day_dir/.capture.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
raw_file="$day_dir/$timestamp.raw.png"
out_file="$day_dir/$timestamp.jpg"
index_file="$day_dir/index.csv"

# 采样规则：先用系统截图拿原始画面，再压成 960 宽低清 JPG 用于后续大模型识别页面类别。
screencapture -x "$raw_file"
if [[ ! -f "$raw_file" ]]; then
  printf 'screencapture did not create %s\n' "$raw_file" >&2
  exit 1
fi
sips -s format jpeg -s formatOptions "$JPEG_QUALITY" -Z "$MAX_WIDTH" "$raw_file" --out "$out_file" >/dev/null
rm -f "$raw_file"

width="$(sips -g pixelWidth "$out_file" | awk '/pixelWidth:/ { print $2 }')"
height="$(sips -g pixelHeight "$out_file" | awk '/pixelHeight:/ { print $2 }')"
bytes="$(stat -f%z "$out_file")"

if [[ ! -f "$index_file" ]]; then
  printf 'timestamp,file,width,height,bytes\n' > "$index_file" 2>/dev/null || true
fi

# 索引只是辅助；某些 macOS provenance/TCC 状态会拒绝 launchd 追加旧索引文件，
# 但截图本体已经写入成功，不能因此制造持续错误噪声。
printf '%s,%s,%s,%s,%s\n' "$timestamp" "$(basename "$out_file")" "$width" "$height" "$bytes" >> "$index_file" 2>/dev/null || true
printf '%s\n' "$out_file"
