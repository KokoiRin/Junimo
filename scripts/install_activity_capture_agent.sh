#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LABEL="com.bytedance.junimo.activity-capture"
SOURCE_PLIST="$REPO_ROOT/launchd/$LABEL.plist"
SOURCE_CAPTURE_SCRIPT="$REPO_ROOT/scripts/capture_activity_snapshot.py"
SOURCE_LOOP_SCRIPT="$REPO_ROOT/scripts/run_activity_capture_loop.py"
SUPPORT_DIR="$HOME/Library/Application Support/Junimo/ActivityCapture"
CAPTURE_DIR="$HOME/Documents/JunimoActivityCaptures"
START_DATE="${ACTIVITY_CAPTURE_START_DATE:-$(date +%Y-%m-%d)}"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/$LABEL.plist"
INSTALLED_CAPTURE_SCRIPT="$SUPPORT_DIR/capture_activity_snapshot.py"
INSTALLED_LOOP_SCRIPT="$SUPPORT_DIR/run_activity_capture_loop.py"
OUT_LOG="$SUPPORT_DIR/activity-capture.out.log"
ERR_LOG="$SUPPORT_DIR/activity-capture.err.log"

# 模板替换规则：路径写进 plist 前先转义 sed replacement 的特殊字符。
escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[#&\\]/\\&/g'
}

escaped_capture_script="$(escape_sed_replacement "$INSTALLED_CAPTURE_SCRIPT")"
escaped_loop_script="$(escape_sed_replacement "$INSTALLED_LOOP_SCRIPT")"
escaped_capture_dir="$(escape_sed_replacement "$CAPTURE_DIR")"
escaped_start_date="$(escape_sed_replacement "$START_DATE")"
escaped_out_log="$(escape_sed_replacement "$OUT_LOG")"
escaped_err_log="$(escape_sed_replacement "$ERR_LOG")"

mkdir -p "$SUPPORT_DIR"
mkdir -p "$CAPTURE_DIR"
mkdir -p "$TARGET_DIR"
cp "$SOURCE_CAPTURE_SCRIPT" "$INSTALLED_CAPTURE_SCRIPT"
cp "$SOURCE_LOOP_SCRIPT" "$INSTALLED_LOOP_SCRIPT"
chmod +x "$INSTALLED_CAPTURE_SCRIPT"
chmod +x "$INSTALLED_LOOP_SCRIPT"

# 安装边界：repo 内 plist 只保留占位符，安装时再写入当前机器的用户目录。
sed \
  -e "s#__CAPTURE_SCRIPT__#$escaped_capture_script#g" \
  -e "s#__LOOP_SCRIPT__#$escaped_loop_script#g" \
  -e "s#__CAPTURE_DIR__#$escaped_capture_dir#g" \
  -e "s#__START_DATE__#$escaped_start_date#g" \
  -e "s#__OUT_LOG__#$escaped_out_log#g" \
  -e "s#__ERR_LOG__#$escaped_err_log#g" \
  "$SOURCE_PLIST" > "$TARGET_PLIST"

launchctl bootout "gui/$UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$TARGET_PLIST"
launchctl enable "gui/$UID/$LABEL"

launchctl print "gui/$UID/$LABEL" >/dev/null
printf 'Installed %s\n' "$TARGET_PLIST"
printf 'Captures start on %s in %s\n' "$START_DATE" "$CAPTURE_DIR"
