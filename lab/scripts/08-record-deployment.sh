#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

info "recording deployment of $CONSUMER_NAME/$CONSUMER_VERSION to $TARGET_ENV"
pact_broker record-deployment \
  --pacticipant "$CONSUMER_NAME" \
  --version "$CONSUMER_VERSION" \
  --environment "$TARGET_ENV"
