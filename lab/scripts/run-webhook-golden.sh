#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

PAUSE_BEFORE_CLEANUP=false
for arg in "$@"; do
  case "$arg" in
    --pause|-p)
      PAUSE_BEFORE_CLEANUP=true
      ;;
    --help|-h)
      cat <<'EOF'
Usage: run-webhook-golden.sh [--pause|-p]

  --pause, -p  Pause after the golden sequence and print the Pact Broker URL
               so the broker state can be inspected before cleanup.
EOF
      exit 0
      ;;
    *)
      fail "unknown argument: $arg (use --help)"
      ;;
  esac
done

info "Pact lab golden sequence"
info "run id: $RUN_ID"
info "consumer: $CONSUMER_NAME/$CONSUMER_VERSION"
info "provider: $PROVIDER_NAME/$PROVIDER_VERSION"

"$SCRIPT_DIR/00-install.sh"
"$SCRIPT_DIR/01-up.sh"

stop_worker
clear_runtime_state

"$SCRIPT_DIR/02-setup-broker.sh"
"$SCRIPT_DIR/03-start-worker.sh"
trap stop_worker EXIT

"$SCRIPT_DIR/04-consumer-test.sh"
"$SCRIPT_DIR/05-publish-pact.sh"
"$SCRIPT_DIR/06-wait-for-completion.sh"
"$SCRIPT_DIR/07-can-i-deploy.sh"
"$SCRIPT_DIR/08-record-deployment.sh"

EVENT_FILE="$(find "$EVENTS_DIR/processed" -name '*.json' -print -quit)"
RESULT_FILE="$(find "$EVENTS_DIR/results" -name '*.json' -print -quit)"

printf '\n===== golden sequence complete =====\n'
printf 'Broker:        %s\n' "$PACT_BROKER_BASE_URL"
printf 'Broker login:  %s / %s\n' "$PACT_BROKER_USERNAME" "$PACT_BROKER_PASSWORD"
printf 'Consumer:      %s/%s (%s)\n' "$CONSUMER_NAME" "$CONSUMER_VERSION" "$BRANCH"
printf 'Provider:      %s/%s (%s)\n' "$PROVIDER_NAME" "$PROVIDER_VERSION" "$BRANCH"
printf 'Webhook event: %s\n' "$EVENT_FILE"
printf 'Result:        %s\n' "$RESULT_FILE"
printf 'Worker log:    %s\n' "$WORKER_LOG"
printf '\nVerification result:\n'
cat "$RESULT_FILE"
printf '\n'

if [ "$PAUSE_BEFORE_CLEANUP" = true ]; then
  printf '\n===== paused before cleanup =====\n'
  printf 'Pact Broker:   %s\n' "$PACT_BROKER_BASE_URL"
  printf 'Broker login:  %s / %s\n' "$PACT_BROKER_USERNAME" "$PACT_BROKER_PASSWORD"
  printf 'Webhook API:   http://localhost:7070/events\n'
  printf 'Events dir:    %s\n' "$EVENTS_DIR"
  printf '\nInspect the broker at %s, then press Enter to stop the mock CI worker and exit.\n' "$PACT_BROKER_BASE_URL"
  printf '(The broker and webhook receiver containers remain running; use ./scripts/down.sh to stop them.)\n'
  read -r _ || true
fi
