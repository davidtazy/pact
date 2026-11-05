#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

info "configuring broker pacticipants, environment, provider version, and webhook"

pact_broker create-or-update-pacticipant \
  --name "$CONSUMER_NAME" \
  --main-branch "$BRANCH" >/dev/null

pact_broker create-or-update-pacticipant \
  --name "$PROVIDER_NAME" \
  --main-branch "$BRANCH" >/dev/null

if ! pact_broker list-environments --output json 2>/dev/null |
  jq -e --arg name "$TARGET_ENV" '._embedded.environments[] | select(.name == $name)' >/dev/null; then
  pact_broker create-environment \
    --name "$TARGET_ENV" \
    --display-name "$TARGET_ENV" >/dev/null
fi

# Seed the provider version so contract_requiring_verification_published has
# a target (the head of the provider's main branch).
pact_broker create-or-update-version \
  --pacticipant "$PROVIDER_NAME" \
  --version "$PROVIDER_VERSION" \
  --branch "$BRANCH" >/dev/null

# Simulate the provider already running in the target environment so that
# can-i-deploy has an environment version to compare the consumer against.
pact_broker record-deployment \
  --pacticipant "$PROVIDER_NAME" \
  --version "$PROVIDER_VERSION" \
  --environment "$TARGET_ENV" >/dev/null

WEBHOOK_BODY=$(cat <<'JSON'
{
  "pactUrl": "${pactbroker.pactUrl}",
  "consumerName": "${pactbroker.consumerName}",
  "consumerVersionNumber": "${pactbroker.consumerVersionNumber}",
  "consumerVersionBranch": "${pactbroker.consumerVersionBranch}",
  "providerName": "${pactbroker.providerName}",
  "providerVersionNumber": "${pactbroker.providerVersionNumber}",
  "providerVersionBranch": "${pactbroker.providerVersionBranch}"
}
JSON
)

pact_broker create-or-update-webhook \
  "$WEBHOOK_RECEIVER_INTERNAL_URL" \
  --uuid 00000000-0000-0000-0000-000000000001 \
  --request POST \
  --header "Content-Type: application/json" "X-Pact-Webhook-Secret: $WEBHOOK_SECRET" \
  --data "$WEBHOOK_BODY" \
  --consumer "$CONSUMER_NAME" \
  --provider "$PROVIDER_NAME" \
  --contract-requiring-verification-published >/dev/null

info "broker configured; webhook -> $WEBHOOK_RECEIVER_INTERNAL_URL"
