#!/usr/bin/env bash

# 使用可执行文件路径和 Bundle ID 识别当前用户的实例，避免按命令行子串误杀其他程序。
junimo_processes() {
  local owner pid parent executable bundle identifier
  while read -r owner pid parent executable; do
    [[ "$owner" == "$UID" ]] || continue
    case "$executable" in
      */Contents/MacOS/Junimo|*/Contents/MacOS/junimo-backend)
        bundle="${executable%/Contents/MacOS/*}"
        identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null)" || continue
        [[ "$identifier" == "local.junimo.shell" ]] || continue
        ;;
      "$ROOT_DIR/.build/direct/junimo-backend") ;;
      *) continue ;;
    esac
    printf '%s %s %s\n' "$pid" "$parent" "$executable"
  done < <(ps -axo uid=,pid=,ppid=,comm=)
}

stop_junimo_instances() {
  local instances pid parent executable current_pid current_parent current_executable attempt
  instances="$(junimo_processes)"
  while read -r pid parent executable; do
    [[ -n "$pid" ]] || continue
    # 发信号前重新确认 PID 仍属于同一路径；已退出的实例直接跳过。
    while read -r current_pid current_parent current_executable; do
      if [[ "$current_pid" == "$pid" && "$current_executable" == "$executable" ]]; then
        echo "Stopping Junimo: $pid $executable"
        kill -TERM "$pid" 2>/dev/null || true
        break
      fi
    done < <(junimo_processes)
  done <<< "$instances"

  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -n "$(junimo_processes)" ]] || return 0
    sleep 0.1
  done
  echo "Old Junimo processes did not exit; restart aborted." >&2
  junimo_processes >&2
  return 1
}

backend_listeners() {
  lsof -nP -t -iTCP:44832 -sTCP:LISTEN 2>/dev/null | sort -u || true
}

verify_junimo_runtime() {
  local app_dir="$1" pid parent executable app_pid="" backend_pid="" backend_parent="" count=0 health state
  while read -r pid parent executable; do
    [[ -n "$pid" ]] || continue
    count=$((count + 1))
    case "$executable" in
      "$app_dir/Contents/MacOS/Junimo") app_pid="$pid" ;;
      "$app_dir/Contents/MacOS/junimo-backend") backend_pid="$pid"; backend_parent="$parent" ;;
      *) return 1 ;;
    esac
  done < <(junimo_processes)
  [[ "$count" == 2 && -n "$app_pid" && -n "$backend_pid" && "$backend_parent" == "$app_pid" ]] || return 1
  [[ "$(backend_listeners)" == "$backend_pid" ]] || return 1
  health="$(curl --fail --silent --max-time 1 http://127.0.0.1:44832/health)" || return 1
  [[ "$(printf '%s' "$health" | plutil -extract status raw -o - - 2>/dev/null)" == ok ]] || return 1
  state="$(curl --fail --silent --max-time 1 http://127.0.0.1:44832/state)" || return 1
  printf '%s' "$state" | plutil -extract revision raw -o - - >/dev/null 2>&1
}
