# The Pact golden path (CDCT + Pact Broker + GitLab)

```text
consumer CI ──publish pact──▶ Pact Broker ──webhook──▶ provider CI
      ▲                            │                       │
      │                            │◀──verification result─┘
      │                            │
      └────── can-i-deploy ────────┘
                   │
                deploy
                   │
          record-deployment ──────▶ Pact Broker
```

## Step-by-step

1. **Consumer publishes a pact.**
   Consumer CI runs its contract tests against a mock provider, generates the pact, and publishes it to the broker with:
   - consumer version (usually the git SHA),
   - consumer branch (e.g. `main`).

   Tags are optional; branch + version is the modern flow.

2. **Broker detects a changed contract and fires a webhook.**
   The event to use is `contract_requiring_verification_published`. It fires only when the pact **content changes**, and only for provider versions that are missing a verification result for that content. Those versions are:
   - the latest provider version on its main branch,
   - any provider version currently deployed/released,
   - de-duplicated.

   If the pact content is unchanged, it is already "pre-verified" and no provider build is triggered.

3. **Broker calls the provider's GitLab pipeline trigger API.**
   The webhook passes:
   - `${pactbroker.pactUrl}` — the exact pact to verify,
   - `${pactbroker.providerVersionNumber}` — the provider version to verify (normally the provider git SHA),
   - `${pactbroker.providerVersionBranch}` — the provider branch.

   The provider version number is **the provider's own version**, not the consumer's version. The consumer version is already recorded inside the pact/broker.

4. **Provider CI checks out the exact provider version.**
   On GitLab, the trigger API takes a `ref` (branch/tag), not a SHA. So the usual pattern is:
   - trigger `ref=main` so the pipeline definition comes from trusted main,
   - pass `PACT_PROVIDER_VERSION` as a variable,
   - in the job, `git checkout --detach "$PACT_PROVIDER_VERSION"` (or pull a prebuilt image tagged with that SHA).

   This is where you avoid rebuilding per pact: build once per provider commit, then have the verification job reuse that image/artifact.

5. **Provider runs verification against the pact URL.**
   The provider verifier:
   - fetches the pact from `PACT_URL`,
   - exercises the real provider (in-process test server or deployed instance),
   - asserts the responses match the consumer's expectations,
   - honours provider states/fixtures.

6. **Provider publishes the verification result back to the broker.**
   The result is published against:
   - the exact provider version it just tested,
   - the provider branch.

   This creates/updates the matrix row: **consumer version ↔ provider version = pass/fail**.

7. **`can-i-deploy` can now answer the deploy question.**
   In the consumer's deploy pipeline (and optionally the provider's):

   ```bash
   pact-broker can-i-deploy \
     --pacticipant <app> \
     --version <git-sha> \
     --to-environment <env>
   ```

   It checks the matrix against the versions already deployed in that environment.
   If the webhook-triggered verification is still running, use `--retry-while-unknown` so the job waits for the result instead of failing immediately.

8. **Deploy, then record the deployment.**
   After a successful deploy:

   ```bash
   pact-broker record-deployment \
     --pacticipant <app> \
     --version <git-sha> \
     --environment <env>
   ```

   This is what makes future `can-i-deploy` checks environment-aware: the broker now knows which version is live in each environment.

## Important nuances

- The webhook is **not** fired on every consumer pipeline. It is fired on **contract content change** and for **provider versions missing a result**.
- The provider does not "take" the consumer's version. It verifies a **pact URL** and publishes against its **own provider version + branch**.
- If you only run `can-i-deploy` before the provider verification exists, you get "unknown". `--retry-while-unknown` is the bridge.
- `record-deployment` is not optional if you want meaningful environment gates; without it the broker only knows about pacts and verifications, not what is actually running.
- Provider-side changes follow the same matrix logic but start from the provider pipeline: it runs the full verification suite using consumer selectors (`mainBranch`, `matchingBranch`, `deployedOrReleased`) and publishes results, then `can-i-deploy` gates the provider deploy.

## References

- [Pact Broker webhooks](https://docs.pact.io/pact_broker/webhooks)
- [Pact Nirvana Step 6](https://docs.pact.io/pact_nirvana/step_6)
- [Recommended configuration for verifying pacts](https://docs.pact.io/provider/recommended_configuration)
- [can-i-deploy](https://docs.pact.io/pact_broker/can_i_deploy)
- [Recording deployments and releases](https://docs.pact.io/pact_broker/recording_deployments_and_releases)
- [GitLab — trigger pipelines with the API](https://docs.gitlab.com/ci/triggers/)
