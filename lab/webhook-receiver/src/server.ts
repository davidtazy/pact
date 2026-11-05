import express, { Express } from 'express';
import { EventStore } from './storage';
import {
  ValidationError,
  ValidationConfig,
  validateWebhookPayload,
} from './validate';

export interface ReceiverConfig extends ValidationConfig {
  webhookSecret: string;
  eventsDir: string;
}

export function configFromEnv(): ReceiverConfig {
  return {
    webhookSecret: process.env.WEBHOOK_SECRET ?? 'local-secret',
    eventsDir: process.env.EVENTS_DIR ?? '/app/events',
    pactUrlHostAllowlist: (
      process.env.PACT_URL_HOST_ALLOWLIST ??
      'localhost,127.0.0.1,pact-broker'
    )
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    expectedConsumer: process.env.EXPECTED_CONSUMER,
    expectedProvider: process.env.EXPECTED_PROVIDER,
  };
}

export function createApp(
  config: ReceiverConfig = configFromEnv(),
  store: EventStore = new EventStore(config.eventsDir),
): Express {
  const app = express();

  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.post('/webhooks/pact', (req, res) => {
    const secret = req.header('x-pact-webhook-secret');

    if (secret !== config.webhookSecret) {
      res.status(401).json({ error: 'invalid webhook secret' });
      return;
    }

    try {
      const payload = validateWebhookPayload(req.body, config);
      const result = store.write(payload);
      res.status(202).json(result);
    } catch (error) {
      if (error instanceof ValidationError) {
        res.status(400).json({ error: error.message });
        return;
      }

      console.error('failed to store webhook', error);
      res.status(500).json({ error: 'failed to store webhook' });
    }
  });

  app.get('/events', (_req, res) => {
    res.status(200).json(store.list());
  });

  app.get('/events/:id', (req, res) => {
    const event = store.read(req.params.id);

    if (!event) {
      res.status(404).json({ error: 'event not found' });
      return;
    }

    res.status(200).json(event);
  });

  return app;
}
