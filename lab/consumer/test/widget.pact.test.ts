import path from 'path';
import { MatchersV3, PactV3 } from '@pact-foundation/pact';
import { WidgetClient } from '../src/widgetClient';

const pact = new PactV3({
  consumer: 'the-consumer',
  provider: 'the-provider',
  dir: path.resolve(process.cwd(), 'pacts'),
});

describe('WidgetClient', () => {
  it('gets a widget by id', async () => {
    await pact
      .given('widget 123 exists')
      .uponReceiving('a request for widget 123')
      .withRequest({
        method: 'GET',
        path: '/widgets/123',
      })
      .willRespondWith({
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: MatchersV3.like({
          id: '123',
          name: 'Example widget',
        }),
      })
      .executeTest(async (mockServer) => {
        const client = new WidgetClient(mockServer.url);
        const widget = await client.getWidget('123');

        expect(widget).toEqual({
          id: '123',
          name: 'Example widget',
        });
      });
  });
});
