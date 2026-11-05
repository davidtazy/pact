#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

info "stopping mock CI worker"
stop_worker

info "stopping Docker Compose stack and clearing the database volume"
docker compose -f "$LAB_ROOT/docker-compose.yml" down -v

info "clearing generated events, pacts, and logs"
rm -rf "$EVENTS_DIR"/pending/*.json \
  "$EVENTS_DIR"/processing/*.json \
  "$EVENTS_DIR"/processed/*.json \
  "$EVENTS_DIR"/results/*.json \
  "$EVENTS_DIR"/.worker.lock \
  "$LAB_ROOT/consumer/pacts" \
  "$LOGS_DIR"/*.log

info "lab is reset"
