#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

info "installing root, consumer, provider, and receiver dependencies"
npm --prefix "$LAB_ROOT" install --no-audit --no-fund
npm --prefix "$LAB_ROOT/consumer" install --no-audit --no-fund
npm --prefix "$LAB_ROOT/provider" install --no-audit --no-fund
npm --prefix "$LAB_ROOT/webhook-receiver" install --no-audit --no-fund
info "dependencies installed"
