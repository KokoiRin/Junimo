#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/runtime.sh"

main() {
  local app_dir attempt
  app_dir="$("$ROOT_DIR/scripts/build_app.sh")"

  stop_junimo_instances || return 1
  if [[ -n "$(backend_listeners)" ]]; then
    echo "Port 44832 is still occupied; refusing to reuse an unknown backend." >&2
    return 1
  fi

  open -n "$app_dir"
  for ((attempt = 0; attempt < 100; attempt++)); do
    if verify_junimo_runtime "$app_dir"; then
      echo "Junimo restarted:"
      junimo_processes
      return 0
    fi
    sleep 0.1
  done
  echo "Junimo restart failed: expected one app and its bundled backend on port 44832." >&2
  junimo_processes >&2
  return 1
}

main "$@"
