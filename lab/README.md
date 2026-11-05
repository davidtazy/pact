# Pact lab

A minimal local Pact lab:

- **consumer** — Node/TypeScript Pact consumer test.
- **provider** — Node/TypeScript Express provider and Pact verification.
- **Pact Broker** — local OSS broker + Postgres in Docker Compose.
- **webhook-receiver** — validates broker webhooks and stores them as JSON files.
- **mock CI worker** — stateless background loop that consumes webhook events and runs provider verification.

## Quick start

```bash
cd lab
./scripts/run-webhook-golden.sh
```

To pause after the sequence and inspect the broker before cleanup:

```bash
./scripts/run-webhook-golden.sh --pause
```

The pause prints the broker URL and login, then waits for Enter before stopping the mock CI worker.

Then open:

- Broker UI: <http://localhost:9292> (`pact` / `pact`)
- Webhook receiver: <http://localhost:7070/health>
- Webhook events API: <http://localhost:7070/events>

Inspect the generated files:

```bash
find webhook-events -type f | sort
```

## What the golden sequence does

1. Starts Postgres, Pact Broker, and the webhook receiver.
2. Configures consumer/provider main branches and a provider version.
3. Creates the `contract_requiring_verification_published` webhook.
4. Starts the stateless mock CI worker.
5. Runs the consumer Pact test.
6. Publishes the pact.
7. Waits for the broker webhook to reach the receiver.
8. Waits for the worker to verify the provider and publish the result.
9. Runs `can-i-deploy`.
10. Records the consumer deployment.

## Useful scripts

```bash
./scripts/00-install.sh        # install all dependencies
./scripts/01-up.sh             # start Postgres, broker, receiver
./scripts/02-setup-broker.sh   # pacticipants, env, provider version, webhook
./scripts/03-start-worker.sh   # start background worker
./scripts/04-consumer-test.sh  # generate the pact
./scripts/05-publish-pact.sh   # publish the pact
./scripts/06-wait-for-completion.sh
./scripts/07-can-i-deploy.sh
./scripts/08-record-deployment.sh
./scripts/down.sh              # stop and reset everything
```

`run-webhook-golden.sh` orchestrates the above and stops the worker on exit.

## Webhook receiver

`POST /webhooks/pact` validates:

- `X-Pact-Webhook-Secret`
- required fields and types
- `pactUrl` host against `PACT_URL_HOST_ALLOWLIST`
- expected consumer/provider names

Valid events are written atomically to:

```text
webhook-events/pending/<sha256>.json
```

The idempotency key is `sha256(pactUrl + "|" + providerVersionNumber)`, so broker retries do not create duplicates.

## Stateless worker

The worker uses the filesystem as its queue:

```text
pending/     work to do
processing/  claimed by the worker
processed/   completed events
results/     verification result metadata
```

It recovers `processing/` files on startup, claims events with an atomic `mv`, runs provider verification, writes a result JSON, and moves the event to `processed/`.

## Configuration

Copy `.env.example` to `.env` to override defaults:

```bash
cp .env.example .env
```

Important variables:

| Variable | Default |
|---|---|
| `PACT_BROKER_BASE_URL` | `http://192.168.1.39:9292` |
| `PACT_BROKER_PUBLIC_URL` | `http://192.168.1.39:9292` |
| `PACT_URL_HOST_ALLOWLIST` | `localhost,127.0.0.1,pact-broker,192.168.1.39,gitlab.local` |
| `PACT_BROKER_USERNAME` | `pact` |
| `PACT_BROKER_PASSWORD` | `pact` |
| `WEBHOOK_SECRET` | `local-secret` |
| `BRANCH` | `main` |
| `TARGET_ENV` | `test` |

## Remote access

The default lab URL is `http://192.168.1.39:9292`. The broker advertises this URL in generated links and pact URLs, so remote browsers and the provider verifier can use them directly.

To use `gitlab.local` instead, set both:

```dotenv
PACT_BROKER_PUBLIC_URL=http://gitlab.local:9292
PACT_BROKER_BASE_URL=http://gitlab.local:9292
```

`gitlab.local` must resolve to `192.168.1.39` on the remote host (DNS or `/etc/hosts`). When changing `PACT_BROKER_PUBLIC_URL`, restart the stack:

```bash
docker compose up -d
```


Versions default to `consumer-<epoch>` and `provider-<epoch>`.

## Notes

- This is a local lab; webhooks use plain HTTP and a shared-secret header.
- The provider version is seeded before the consumer publishes so `contract_requiring_verification_published` has a target.
- `down.sh` removes the Postgres volume, so the broker starts clean next time.
