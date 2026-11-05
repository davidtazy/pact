#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

TIMEOUT="${WAIT_TIMEOUT:-120}"
deadline=$((SECONDS + TIMEOUT))

info "waiting up to ${TIMEOUT}s for provider verification of $CONSUMER_NAME/$CONSUMER_VERSION"
while [ "$SECONDS" -lt "$deadline" ]; do
  for file in "$EVENTS_DIR"/results/*.json; do
    [ -e "$file" ] || continue

    if ! jq -e --arg version "$CONSUMER_VERSION" \
      '.consumerVersionNumber == $version' "$file" >/dev/null 2>&1; then
      continue
    fi

    status="$(jq -r '.status' "$file")"
    if [ "$status" = "passed" ]; then
      info "provider verification passed: $file"
      exit 0
    fi

    if [ "$status" = "failed" ]; then
      printf '[lab] provider verification failed:\n' >&2
      cat "$file" >&2
      exit 1
    fi
  done

  sleep 1
done

printf '[lab] timed out waiting for provider verification\n' >&2
printf '[lab] pending events:\n' >&2
ls -1 "$EVENTS_DIR/pending" 2>/dev/null >&2 || true
printf '[lab] worker log:\n' >&2
tail -n 50 "$WORKER_LOG" >&2 || true
exit 1
