# Pact Contract Testing Lab

A minimal, runnable Pact lab that demonstrates the full consumer-driven contract-testing loop locally:

```text
consumer test -> publish pact -> Pact Broker -> webhook
      -> receiver -> mock CI worker -> provider verification
      -> can-i-deploy -> record-deployment
```

It uses Node/TypeScript, a local Pact Broker in Docker, and a stateless webhook-driven mock CI worker.

## Quick start

```bash
cd lab
./scripts/run-webhook-golden.sh --pause
```

The `--pause` flag prints the broker URL and waits for Enter before cleanup.

| Service | URL |
|---|---|
| Pact Broker | http://192.168.1.39:9292 (`pact` / `pact`) |
| Webhook receiver | http://192.168.1.39:7070/health |
| Received webhook events | http://192.168.1.39:7070/events |

Reset everything:

```bash
cd lab
./scripts/down.sh
```

## What is in the lab

| Path | Purpose |
|---|---|
| `lab/consumer/` | Pact JS consumer test and HTTP client |
| `lab/provider/` | Express provider and Pact verification |
| `lab/webhook-receiver/` | Validates broker webhooks and stores JSON events |
| `lab/scripts/` | Golden sequence, stateless mock-CI worker, reset |
| `lab/docker-compose.yml` | Pact Broker, Postgres, webhook receiver |

Webhook events are stored as JSON files in `lab/webhook-events/`.

## Requirements

- Docker + Docker Compose
- Node.js 20 or later

## Configuration

The lab reads `lab/.env`. To use `gitlab.local` instead of the IP, set:

```dotenv
PACT_BROKER_PUBLIC_URL=http://gitlab.local:9292
PACT_BROKER_BASE_URL=http://gitlab.local:9292
```

Ensure `gitlab.local` resolves to `192.168.1.39` on the remote host, then run:

```bash
cd lab
docker compose up -d
```

## Documentation

- [Golden path](pact-golden-path.md)
- [Provider verifier placement on GitLab](pact-verifier-gitlab-research.md)
- [Provider selectors and attributes](pact-provider-selectors-attributes.md)
- [Consumer setup on GitLab](pact-consumer-setup-gitlab.md)
- [Contract-testing onboarding backlog](contract-testing-backlog.md)
