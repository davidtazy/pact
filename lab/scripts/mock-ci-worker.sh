#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

mkdir -p "$EVENTS_DIR"/{pending,processing,processed,results}

exec 9>"$EVENTS_DIR/.worker.lock"
if ! flock -n 9; then
  info "another mock CI worker already holds the lock"
  exit 0
fi

# Crash recovery: anything left in processing is put back on the queue.
for file in "$EVENTS_DIR"/processing/*.json; do
  [ -e "$file" ] || continue
  mv "$file" "$EVENTS_DIR/pending/" 2>/dev/null || true
done

process_event() {
  local event_file="$1"
  local id
  id="$(basename "$event_file" .json)"

  local pact_url consumer_name consumer_version consumer_branch
  local provider_name provider_version provider_branch
  pact_url="$(jq -r '.payload.pactUrl' "$event_file")"
  consumer_name="$(jq -r '.payload.consumerName' "$event_file")"
  consumer_version="$(jq -r '.payload.consumerVersionNumber' "$event_file")"
  consumer_branch="$(jq -r '.payload.consumerVersionBranch // ""' "$event_file")"
  provider_name="$(jq -r '.payload.providerName' "$event_file")"
  provider_version="$(jq -r '.payload.providerVersionNumber' "$event_file")"
  provider_branch="$(jq -r '.payload.providerVersionBranch' "$event_file")"

  local started_at finished_at log_file result_file
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log_file="$LOGS_DIR/provider-verify-$id.log"
  result_file="$EVENTS_DIR/results/$id.json"

  info "processing webhook event $id: $consumer_name/$consumer_version -> $provider_name/$provider_version"

  local exit_code=0
  set +e
  (
    cd "$LAB_ROOT/provider"
    PACT_URL="$pact_url" \
      PROVIDER_NAME="$provider_name" \
      PROVIDER_VERSION="$provider_version" \
      PROVIDER_BRANCH="$provider_branch" \
      PUBLISH_VERIFICATION_RESULTS=true \
      PACT_BROKER_BASE_URL="$PACT_BROKER_BASE_URL" \
      PACT_BROKER_USERNAME="$PACT_BROKER_USERNAME" \
      PACT_BROKER_PASSWORD="$PACT_BROKER_PASSWORD" \
      npm run verify:pact
  ) >"$log_file" 2>&1
  exit_code=$?
  set -e

  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local status="failed"
  if [ "$exit_code" -eq 0 ]; then
    status="passed"
  fi

  jq -n \
    --arg id "$id" \
    --arg status "$status" \
    --argjson exitCode "$exit_code" \
    --arg consumerName "$consumer_name" \
    --arg consumerVersionNumber "$consumer_version" \
    --arg consumerVersionBranch "$consumer_branch" \
    --arg providerName "$provider_name" \
    --arg providerVersionNumber "$provider_version" \
    --arg providerVersionBranch "$provider_branch" \
    --arg pactUrl "$pact_url" \
    --arg startedAt "$started_at" \
    --arg finishedAt "$finished_at" \
    --arg logFile "$log_file" \
    '{
      id: $id,
      status: $status,
      exitCode: $exitCode,
      consumerName: $consumerName,
      consumerVersionNumber: $consumerVersionNumber,
      consumerVersionBranch: $consumerVersionBranch,
      providerName: $providerName,
      providerVersionNumber: $providerVersionNumber,
      providerVersionBranch: $providerVersionBranch,
      pactUrl: $pactUrl,
      startedAt: $startedAt,
      finishedAt: $finishedAt,
      logFile: $logFile
    }' >"$result_file"

  mv "$event_file" "$EVENTS_DIR/processed/$id.json"

  if [ "$status" = "passed" ]; then
    info "provider verification passed for event $id"
  else
    info "provider verification failed for event $id (exit $exit_code); see $log_file"
  fi
}

info "mock CI worker started; polling $EVENTS_DIR/pending"

while true; do
  processed_any=0

  for file in "$EVENTS_DIR"/pending/*.json; do
    [ -e "$file" ] || continue
    id="$(basename "$file" .json)"
    claimed="$EVENTS_DIR/processing/$id.json"

    if ! mv "$file" "$claimed" 2>/dev/null; then
      continue
    fi

    processed_any=1
    process_event "$claimed"

    if [ "${WORKER_ONCE:-0}" = "1" ]; then
      exit 0
    fi
  done

  if [ "${WORKER_ONCE:-0}" = "1" ] && [ "$processed_any" -eq 0 ]; then
    exit 0
  fi

  sleep "${WORKER_POLL_INTERVAL:-1}"
done
