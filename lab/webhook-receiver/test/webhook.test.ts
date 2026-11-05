import fs from 'fs';
import os from 'os';
import path from 'path';
import request from 'supertest';
import { ReceiverConfig, createApp } from '../src/server';

const secret = 'test-secret';

function payload(overrides: Record<string, unknown> = {}) {
  return {
    pactUrl:
      'http://localhost:9292/pacts/provider/the-provider/consumer/the-consumer/pact-version/abc',
    consumerName: 'the-consumer',
    consumerVersionNumber: 'consumer-1',
    consumerVersionBranch: 'main',
    providerName: 'the-provider',
    providerVersionNumber: 'provider-1',
    providerVersionBranch: 'main',
    ...overrides,
  };
}

function config(eventsDir: string): ReceiverConfig {
  return {
    webhookSecret: secret,
    eventsDir,
    pactUrlHostAllowlist: ['localhost', '127.0.0.1', 'pact-broker'],
    expectedConsumer: 'the-consumer',
    expectedProvider: 'the-provider',
  };
}

function tempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'pact-webhook-'));
}

describe('webhook receiver', () => {
  it('accepts a valid payload and stores one JSON file', async () => {
    const dir = tempDir();
    const app = createApp(config(dir));

    const response = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', secret)
      .send(payload());

    expect(response.status).toBe(202);
    expect(response.body.duplicate).toBe(false);

    const pending = fs.readdirSync(path.join(dir, 'pending'));
    expect(pending).toHaveLength(1);

    const stored = JSON.parse(
      fs.readFileSync(path.join(dir, 'pending', pending[0]), 'utf8'),
    );
    expect(stored.payload.providerVersionNumber).toBe('provider-1');
  });

  it('is idempotent for the same pact and provider version', async () => {
    const dir = tempDir();
    const app = createApp(config(dir));

    const first = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', secret)
      .send(payload());
    const second = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', secret)
      .send(payload());

    expect(first.status).toBe(202);
    expect(second.status).toBe(202);
    expect(second.body.duplicate).toBe(true);
    expect(fs.readdirSync(path.join(dir, 'pending'))).toHaveLength(1);
  });

  it('rejects a bad secret', async () => {
    const app = createApp(config(tempDir()));

    const response = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', 'wrong')
      .send(payload());

    expect(response.status).toBe(401);
  });

  it('rejects a missing provider version', async () => {
    const app = createApp(config(tempDir()));
    const body = payload();
    delete (body as Record<string, unknown>).providerVersionNumber;

    const response = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', secret)
      .send(body);

    expect(response.status).toBe(400);
  });

  it('rejects a pact URL with a host outside the allowlist', async () => {
    const app = createApp(config(tempDir()));

    const response = await request(app)
      .post('/webhooks/pact')
      .set('X-Pact-Webhook-Secret', secret)
      .send(payload({ pactUrl: 'http://evil.example/pact.json' }));

    expect(response.status).toBe(400);
  });
});
