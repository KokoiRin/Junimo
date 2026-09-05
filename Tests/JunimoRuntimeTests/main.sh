#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/runtime.sh"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/junimo-runtime.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
new_app="$fixture_dir/Development Build/Junimo.app"
old_app="$fixture_dir/Applications/Junimo.app"
other_app="$fixture_dir/Other.app"
for bundle in "$new_app" "$old_app" "$other_app"; do
  mkdir -p "$bundle/Contents"
  identifier="local.junimo.shell"
  [[ "$bundle" != "$other_app" ]] || identifier="other.app"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $identifier" "$bundle/Contents/Info.plist" >/dev/null
done

# 系统操作替身只读取临时进程表，测试不会关闭或启动真实应用。
ps() { cat "$fixture_dir/processes"; }
lsof() { cat "$fixture_dir/listeners"; }
sleep() { :; }
curl() {
  [[ "${http_failure:-false}" == false ]] || return 1
  case "$*" in
    */health) printf '{"status":"ok","protocolVersion":5}' ;;
    */state) printf '{"revision":1}' ;;
  esac
}
kill() {
  printf '%s\n' "$2" >> "$fixture_dir/signals"
  [[ "${ignore_termination:-false}" == false ]] || return 0
  # 父进程退出后，仍存活的子进程会被重新托管给 PID 1。
  awk -v pid="$2" '$2 == pid { next } $3 == pid { $3 = 1 } { print }' "$fixture_dir/processes" > "$fixture_dir/next"
  mv "$fixture_dir/next" "$fixture_dir/processes"
}
new_pair() {
  printf '%s\n' "$UID 101 1 $new_app/Contents/MacOS/Junimo" "$UID 102 101 $new_app/Contents/MacOS/junimo-backend" > "$fixture_dir/processes"
  echo 102 > "$fixture_dir/listeners"
}
reject_runtime() {
  if verify_junimo_runtime "$new_app"; then
    echo "Unexpectedly accepted invalid Junimo runtime" >&2
    exit 1
  fi
}

# 同一用户的新旧 Bundle 和本仓库直接运行的后端应全部退出，其他应用及其他用户的同名进程保留。
new_pair
printf '%s\n' "$UID 201 1 $old_app/Contents/MacOS/Junimo" "$UID 202 201 $old_app/Contents/MacOS/junimo-backend" "$UID 203 1 $ROOT_DIR/.build/direct/junimo-backend" "$UID 301 1 $other_app/Contents/MacOS/Junimo" "$((UID + 1)) 401 1 $old_app/Contents/MacOS/Junimo" >> "$fixture_dir/processes"
stop_junimo_instances
[[ -z "$(junimo_processes)" ]]
[[ "$(wc -l < "$fixture_dir/processes" | tr -d ' ')" == 2 ]]
[[ "$(sort -n "$fixture_dir/signals")" == $'101\n102\n201\n202\n203' ]]

# 旧实例忽略退出信号时，重启必须失败，不能继续启动第二个实例。
new_pair
ignore_termination=true
if stop_junimo_instances >/dev/null 2>&1; then exit 1; fi
ignore_termination=false

# 只有一组来自指定 Bundle 的前后端、父子关系匹配且接口可用时，重启验证才成功，路径中的空格不影响识别。
new_pair
verify_junimo_runtime "$new_app"

# 新前端连接旧 Bundle 的健康后端时，即使端口有响应也不能判为重启成功。
printf '%s\n' "$UID 101 1 $new_app/Contents/MacOS/Junimo" "$UID 202 1 $old_app/Contents/MacOS/junimo-backend" > "$fixture_dir/processes"
echo 202 > "$fixture_dir/listeners"
reject_runtime

# 新版前后端正常但另一个旧前端仍然存活时，必须识别为实例共存。
new_pair
echo "$UID 201 1 $old_app/Contents/MacOS/Junimo" >> "$fixture_dir/processes"
reject_runtime

# 同一路径的孤儿后端、重复前端、其他进程占用端口和 HTTP 不可用都不能通过重启验证。
new_pair
sed 's/102 101/102 1/' "$fixture_dir/processes" > "$fixture_dir/next"
mv "$fixture_dir/next" "$fixture_dir/processes"
reject_runtime
new_pair
echo "$UID 103 1 $new_app/Contents/MacOS/Junimo" >> "$fixture_dir/processes"
reject_runtime
new_pair
echo 999 > "$fixture_dir/listeners"
reject_runtime
new_pair
http_failure=true
reject_runtime

echo "Junimo runtime regression tests passed"
