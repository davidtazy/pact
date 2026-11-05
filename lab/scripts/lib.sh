#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$LAB_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$LAB_ROOT/.env"
  set +a
fi

export PACT_BROKER_PUBLIC_URL="${PACT_BROKER_PUBLIC_URL:-http://192.168.1.39:9292}"
export PACT_BROKER_BASE_URL="${PACT_BROKER_BASE_URL:-$PACT_BROKER_PUBLIC_URL}"
export PACT_BROKER_USERNAME="${PACT_BROKER_USERNAME:-pact}"
export PACT_BROKER_PASSWORD="${PACT_BROKER_PASSWORD:-pact}"
export CONSUMER_NAME="${CONSUMER_NAME:-the-consumer}"
export PROVIDER_NAME="${PROVIDER_NAME:-the-provider}"
export BRANCH="${BRANCH:-main}"
export TARGET_ENV="${TARGET_ENV:-test}"
export WEBHOOK_SECRET="${WEBHOOK_SECRET:-local-secret}"
export WEBHOOK_RECEIVER_INTERNAL_URL="${WEBHOOK_RECEIVER_INTERNAL_URL:-http://webhook-receiver:7070/webhooks/pact}"

RUN_ID="${RUN_ID:-$(date +%s)}"
export RUN_ID
export CONSUMER_VERSION="${CONSUMER_VERSION:-consumer-$RUN_ID}"
export PROVIDER_VERSION="${PROVIDER_VERSION:-provider-$RUN_ID}"

export LAB_ROOT
export EVENTS_DIR="$LAB_ROOT/webhook-events"
export LOGS_DIR="$LAB_ROOT/logs"
export PACT_BROKER_CLI="$LAB_ROOT/node_modules/.bin/pact"
export WORKER_PID_FILE="$EVENTS_DIR/.worker.pid"
export WORKER_LOG="$LOGS_DIR/mock-ci-worker.log"

mkdir -p "$EVENTS_DIR"/{pending,processing,processed,results} "$LOGS_DIR"

info() {
  printf '[lab] %s\n' "$*"
}

fail() {
  printf '[lab] ERROR: %s\n' "$*" >&2
  exit 1
}

pact_broker() {
  "$PACT_BROKER_CLI" broker "$@" \
    --broker-base-url "$PACT_BROKER_BASE_URL" \
    --broker-username "$PACT_BROKER_USERNAME" \
    --broker-password "$PACT_BROKER_PASSWORD"
}

wait_for_broker() {
  info "waiting for Pact Broker at $PACT_BROKER_BASE_URL"
  for _ in $(seq 1 120); do
    if curl -fsS -u "$PACT_BROKER_USERNAME:$PACT_BROKER_PASSWORD" \
      "$PACT_BROKER_BASE_URL/diagnostic/status/heartbeat" >/dev/null 2>&1; then
      info "Pact Broker is ready"
      return 0
    fi
    sleep 1
  done
  fail "Pact Broker did not become ready"
}

wait_for_receiver() {
  info "waiting for webhook receiver at http://localhost:7070"
  for _ in $(seq 1 60); do
    if curl -fsS "http://localhost:7070/health" >/dev/null 2>&1; then
      info "webhook receiver is ready"
      return 0
    fi
    sleep 1
  done
  fail "webhook receiver did not become ready"
}

stop_worker() {
  if [ -f "$WORKER_PID_FILE" ]; then
    local pid
    pid="$(cat "$WORKER_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$WORKER_PID_FILE"
  fi
}

clear_runtime_state() {
  rm -f "$EVENTS_DIR"/pending/*.json \
    "$EVENTS_DIR"/processing/*.json \
    "$EVENTS_DIR"/processed/*.json \
    "$EVENTS_DIR"/results/*.json 2>/dev/null || true
}
