# Consumer setup for Pact on GitLab (Node/TypeScript)

This guide covers the consumer side of a CDCT workflow:

```text
pact-test ──▶ publish-pact ──▶ can-i-merge        (MR gate)
                    │
                    └────────▶ can-i-deploy       (deploy gate)
                                     │
                                  deploy
                                     │
                              record-deployment
```

The provider verifier is **not** a consumer job. Publishing a pact triggers the Pact Broker webhook, which starts the provider verification; the consumer then waits on the result via `can-i-merge` or `can-i-deploy`.

---

## Jobs to add

| Job | When it runs | Purpose |
|---|---|---|
| `consumer:pact-test` | MR + default branch | Runs the Pact consumer tests and produces pact JSON |
| `consumer:publish-pact` | MR + default branch | Publishes the pact with consumer version + branch |
| `consumer:can-i-merge` | MR only | Waits for provider verification and blocks merge if incompatible |
| `consumer:can-i-deploy` | Deploy pipeline | Checks compatibility with the target environment |
| `consumer:record-deployment` | After successful deploy | Records which consumer version is live |

One-time setup is also needed: set the consumer's `mainBranch` in the broker.

---

## 1. Install the consumer dependencies

```bash
npm install --save-dev \
  @pact-foundation/pact \
  @pact-foundation/pact-cli \
  jest \
  ts-jest \
  typescript
```

- `@pact-foundation/pact` — consumer test DSL and mock server.
- `@pact-foundation/pact-cli` — provides the `pact-broker` CLI (publish, can-i-deploy, etc.).
- `jest` + `ts-jest` — test runner for the TypeScript example.

---

## 2. Write the Pact consumer test

Create a test such as `test/widget.pact.test.ts`:

```ts
import path from 'path';
import { PactV3, MatchersV3 } from '@pact-foundation/pact';
import { WidgetClient } from '../src/widgetClient';

const pact = new PactV3({
  consumer: 'the-consumer',
  provider: 'the-provider',
  dir: path.resolve(process.cwd(), 'pacts'),
});

describe('WidgetClient', () => {
  it('gets a widget by id', async () => {
    pact
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
      });

    await pact.executeTest(async (mockServer) => {
      const client = new WidgetClient(mockServer.url);
      const widget = await client.getWidget('123');

      expect(widget).toEqual({
        id: '123',
        name: 'Example widget',
      });
    });
  });
});
```

### What each part does

| Part | Meaning |
|---|---|
| `consumer` / `provider` | Names the contract pair |
| `dir: 'pacts'` | Where the generated pact JSON is written |
| `.given('widget 123 exists')` | The provider state the provider must set up. It must match the provider's state handler. |
| `.uponReceiving(...)` | Human-readable name for the interaction |
| `.withRequest(...)` | The exact request the consumer's client makes |
| `.willRespondWith(...)` | The response the provider must return |
| `MatchersV3.like(...)` | Type/shape matcher so the contract is not tied to one exact value |
| `executeTest((mockServer) => ...)` | Runs the real consumer client against the Pact mock server |
| `mockServer.url` | The dynamic mock server URL injected into the client |

The test must exercise the **real consumer HTTP client**, not raw `fetch`/`axios` calls, so the contract stays in sync with production code.

### Provider states

`given('widget 123 exists')` must match the provider's state handler name exactly. If the provider uses a state such as `"widget 123 exists"`, keep the strings identical on both sides.

### Avoid random data

Use fixed example values plus matchers. Random data creates a new pact content version on every run and defeats the broker's duplicate-content and pre-verification logic.

---

## 3. Jest configuration

Create `jest.config.js`:

```js
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/*.pact.test.ts'],
};
```

Pact files are written to `pacts/` by the `dir` option above.

Add the scripts to `package.json`:

```json
{
  "scripts": {
    "test:pact": "jest --runInBand"
  }
}
```

`--runInBand` avoids multiple Jest workers starting mock servers and writing pact files concurrently.

---

## 4. GitLab CI jobs

### `consumer:pact-test`

```yaml
consumer:pact-test:
  stage: test
  image: node:20
  script:
    - npm ci
    - npm run test:pact
  artifacts:
    when: always
    paths:
      - pacts/
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

This produces `pacts/the-consumer-the-provider.json` and keeps it as an artifact for the publish job.

### `consumer:publish-pact`

```yaml
consumer:publish-pact:
  stage: contract
  image: pactfoundation/pact-cli:latest
  needs:
    - job: consumer:pact-test
      artifacts: true
  script:
    - export PACT_BRANCH="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-$CI_COMMIT_REF_NAME}"
    - pact-broker publish pacts
        --consumer-app-version "$CI_COMMIT_SHA"
        --branch "$PACT_BRANCH"
        --build-url "$CI_PIPELINE_URL"
        --broker-base-url "$PACT_BROKER_BASE_URL"
        --broker-token "$PACT_BROKER_TOKEN"
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

The broker CLI jobs use the `pactfoundation/pact-cli` image, so they do not need `npm ci` or a Node install in the publish stage.

Key attributes:

- `--consumer-app-version` — deterministic version, normally the git SHA.
- `--branch` — the source branch on MRs, the default branch on main.
- `--build-url` — links the broker back to the GitLab pipeline.
- `PACT_BROKER_BASE_URL` / `PACT_BROKER_TOKEN` — masked/protected CI variables.

Publishing feature-branch pacts is what lets provider selectors such as `matchingBranch` and WIP verification see the branch.

### `consumer:can-i-merge` (MR gate)

```yaml
consumer:can-i-merge:
  stage: contract
  image: pactfoundation/pact-cli:latest
  needs: [consumer:publish-pact]
  script:
    - pact-broker can-i-merge
        --pacticipant "the-consumer"
        --version "$CI_COMMIT_SHA"
        --retry-while-unknown 30
        --retry-interval 10
        --broker-base-url "$PACT_BROKER_BASE_URL"
        --broker-token "$PACT_BROKER_TOKEN"
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

The provider verification is asynchronous. Without `--retry-while-unknown`, the consumer job can fail while the provider is still verifying.

### `consumer:can-i-deploy` (deploy gate)

```yaml
consumer:can-i-deploy:
  stage: deploy
  image: pactfoundation/pact-cli:latest
  script:
    - pact-broker can-i-deploy
        --pacticipant "the-consumer"
        --version "$CI_COMMIT_SHA"
        --to-environment "$TARGET_ENV"
        --retry-while-unknown 30
        --retry-interval 10
        --broker-base-url "$PACT_BROKER_BASE_URL"
        --broker-token "$PACT_BROKER_TOKEN"
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

- `--to-environment` is preferred over tag-based `--to`.
- `test` and `production` environments are pre-created in the broker.
- Create custom environments with `pact-broker create-environment`.
- Use `--dry-run` while first setting up the gate.

### `consumer:record-deployment`

```yaml
consumer:record-deployment:
  stage: post-deploy
  image: pactfoundation/pact-cli:latest
  script:
    - pact-broker record-deployment
        --pacticipant "the-consumer"
        --version "$CI_COMMIT_SHA"
        --environment "$TARGET_ENV"
        --broker-base-url "$PACT_BROKER_BASE_URL"
        --broker-token "$PACT_BROKER_TOKEN"
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

Without this, environment-aware `can-i-deploy` and the provider's `deployedOrReleased` selector cannot work correctly.

---

## 5. One-time broker setup

Set the consumer's main branch explicitly:

```bash
pact-broker create-or-update-pacticipant \
  --name "the-consumer" \
  --main-branch main \
  --broker-base-url "$PACT_BROKER_BASE_URL" \
  --broker-token "$PACT_BROKER_TOKEN"
```

Verify it:

```bash
pact-broker describe-pacticipant \
  --name "the-consumer" \
  --broker-base-url "$PACT_BROKER_BASE_URL" \
  --broker-token "$PACT_BROKER_TOKEN"
```

`pact-broker` is provided by `@pact-foundation/pact-cli` locally, or by the `pactfoundation/pact-cli` Docker image in CI.

This is not a per-pipeline job. Run it once when onboarding the consumer, or put it in a manual setup job.

---

## 6. What stays the same as the provider-side setup

- Consumer version = git SHA.
- Consumer branch = source branch on MR, default branch on main.
- Publish on MR and main.
- Provider verification is triggered by the broker webhook, not by a consumer job.
- `can-i-merge` / `can-i-deploy` wait for the provider result.
- `record-deployment` runs only after a successful deploy.
- Provider states must match between consumer `given(...)` and provider state handlers.

---

## 7. Common pitfalls

1. **Testing raw HTTP calls instead of the real client** — the contract can drift from production code.
2. **Random data in the pact** — creates unnecessary contract versions.
3. **Publishing without `--branch`** — provider `mainBranch` / `matchingBranch` selectors cannot find the pact.
4. **Publishing the wrong branch on MRs** — use `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME`, falling back to `CI_COMMIT_REF_NAME`.
5. **Skipping `--retry-while-unknown`** — the consumer gate fails before the provider finishes verifying.
6. **Forgetting `record-deployment`** — the broker does not know what is live in each environment.
7. **Using tags instead of branches** — tags still work but are legacy.
8. **Missing `mainBranch` on the consumer** — `{ mainBranch: true }` returns nothing.
9. **Publishing from untrusted fork MRs** — protected broker credentials are not available there.
10. **Running Jest in parallel against one pact directory** — use `--runInBand` or a per-worker output directory.

---

## 8. References

- [Pact JS consumer tests](https://docs.pact.io/implementation_guides/javascript/docs/consumer)
- [Pact JS overview](https://docs.pact.io/implementation_guides/javascript/readme)
- [Publishing and retrieving pacts](https://docs.pact.io/pact_broker/publishing_and_retrieving_pacts)
- [Versioning in the Pact Broker](https://docs.pact.io/getting_started/versioning_in_the_pact_broker)
- [Branches](https://docs.pact.io/pact_broker/branches)
- [Recording deployments and releases](https://docs.pact.io/pact_broker/recording_deployments_and_releases)
- [can-i-deploy](https://docs.pact.io/pact_broker/can_i_deploy)
- [Consumer recommended configuration](https://docs.pact.io/consumer/recommended_configuration)
- [Pact Broker CLI](https://docs.pact.io/pact_broker/client_cli/readme)
