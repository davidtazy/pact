#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

info "checking can-i-deploy for $CONSUMER_NAME/$CONSUMER_VERSION to $TARGET_ENV"
pact_broker can-i-deploy \
  --pacticipant "$CONSUMER_NAME" \
  --version "$CONSUMER_VERSION" \
  --to-environment "$TARGET_ENV" \
  --retry-while-unknown 30 \
  --retry-interval 2
