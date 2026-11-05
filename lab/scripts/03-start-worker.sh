#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ -f "$WORKER_PID_FILE" ]; then
  pid="$(cat "$WORKER_PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    info "mock CI worker already running with pid $pid"
    exit 0
  fi
  rm -f "$WORKER_PID_FILE"
fi

info "starting mock CI worker in the background"
nohup "$SCRIPT_DIR/mock-ci-worker.sh" >>"$WORKER_LOG" 2>&1 &
echo "$!" >"$WORKER_PID_FILE"
info "mock CI worker pid $(cat "$WORKER_PID_FILE"), log: $WORKER_LOG"
