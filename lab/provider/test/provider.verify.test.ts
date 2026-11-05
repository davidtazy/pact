import http from 'http';
import { AddressInfo } from 'net';
import { Verifier } from '@pact-foundation/pact';
import { createApp } from '../src/app';

let server: http.Server;
let providerBaseUrl: string;

beforeAll(async () => {
  server = http.createServer(createApp());
  await new Promise<void>((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address() as AddressInfo;
  providerBaseUrl = `http://127.0.0.1:${address.port}`;
});

afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
});

test('provider honours the consumer contract', async () => {
  const pactUrl = process.env.PACT_URL;

  const options: Record<string, unknown> = {
    providerBaseUrl,
    provider: process.env.PROVIDER_NAME ?? 'the-provider',
    providerVersion: process.env.PROVIDER_VERSION ?? 'provider-local',
    providerVersionBranch: process.env.PROVIDER_BRANCH ?? 'main',
    publishVerificationResult:
      process.env.PUBLISH_VERIFICATION_RESULTS === 'true',
    pactBrokerUrl:
      process.env.PACT_BROKER_BASE_URL ?? 'http://localhost:9292',
    pactBrokerUsername: process.env.PACT_BROKER_USERNAME ?? 'pact',
    pactBrokerPassword: process.env.PACT_BROKER_PASSWORD ?? 'pact',
    stateHandlers: {
      'widget 123 exists': async () => ({
        description: 'widget 123 is available',
      }),
    },
  };

  if (pactUrl) {
    options.pactUrls = [pactUrl];
  } else {
    options.consumerVersionSelectors = [{ mainBranch: true }];
  }

  await new Verifier(options as never).verifyProvider();
}, 60_000);
