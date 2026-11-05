#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

[ -d "$LAB_ROOT/consumer/pacts" ] || fail "consumer/pacts does not exist; run the consumer test first"

info "publishing pact as $CONSUMER_NAME/$CONSUMER_VERSION on branch $BRANCH"
cd "$LAB_ROOT/consumer"
pact_broker publish pacts \
  --consumer-app-version "$CONSUMER_VERSION" \
  --branch "$BRANCH" \
  --build-url "http://localhost/mock-ci/consumer/$CONSUMER_VERSION"
