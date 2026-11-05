# Research: where should the Pact provider verifier run on GitLab?

**Bottom line:** run it in the **provider's GitLab project, in the provider's pipeline**. Use two jobs:

1. `verify:pacts` — runs on the provider's MR/push pipeline, verifies the full supported pact set, and blocks the provider MR on failure.
2. `verify:changed-pact` — runs only when triggered by the Pact Broker webhook, verifies the one changed pact URL, and publishes the result against the exact provider version.

A **separate job or child pipeline in the same provider repo** is fine. A **separate GitLab project** is the exception, not the default — and only if it can solve the version-provenance and MR-blocking problems below.

Build the provider **once per commit** and reuse the resulting artifact/image in both jobs. Do not rebuild the provider for every consumer pact change; see [Optimising the cost](#optimising-the-cost-dont-rebuild-the-provider-per-pact).

---

## What the Pact docs actually prescribe

Pact's own CI guidance puts verification in the provider's CI:

- The [webhooks docs](https://docs.pact.io/pact_broker/webhooks) say the most common use case is to "trigger a provider build every time a pact changes."
- [Pact Nirvana Step 6](https://docs.pact.io/pact_nirvana/step_6) explicitly describes:
  - a normal **Provider test job** in the provider pipeline;
  - a separate **Changed pact verification job** called by a broker webhook, taking the pact URL, provider branch, and provider commit.
- Pact's [recommended provider configuration](https://docs.pact.io/provider/recommended_configuration) separates the two reasons to verify:
  - **provider changed** → full regression suite using consumer version selectors;
  - **pact changed** → verify only the changed pact.
- [`can-i-deploy`](https://docs.pact.io/pact_broker/can_i_deploy) works on the matrix of *consumer version ↔ provider version*. The provider version recorded must be the exact code that ran verification.

That last point is the deciding factor.

---

## Why provider-owned wins

| Concern | Provider pipeline | Separate verifier project |
|---|---|---|
| Correct provider version | Natural — the pipeline runs the provider commit | Must explicitly clone/checkout the provider SHA or use an immutable image |
| Block provider MR | Direct — job is in the MR pipeline | Needs commit-status API plumbing back to the provider commit |
| Provider build/fixtures/DB | Already available | Must duplicate or fetch them |
| Secrets | Broker token already lives in provider project | Must copy tokens, broker creds, DB creds |
| Ownership | Provider team owns the failure | Ambiguous; "platform team broke our build" |
| GitLab auth complexity | Low | Cross-project allowlists, job-token permissions, token rotation |
| Stale/incorrect matrix risk | Low | Higher if the checkout or image tag is wrong |

The provider repo is also where the verification harness, provider states, and fixtures naturally live. Moving only the verifier elsewhere splits the harness from the code it tests.

---

## When a separate GitLab project **is** justified

Use one only if at least one of these is true:

1. **Central platform ownership** — a platform team must run a standardised verification harness across many provider repos.
2. **Legacy/unmodifiable provider CI** — the provider team cannot add jobs to its `.gitlab-ci.yml`.
3. **Network segmentation** — provider runners cannot reach the Pact Broker, but a central verifier can.
4. **Deployed-environment verification** — you want to verify what is actually running in `test`/`staging`/`prod`, not just source.
5. **Cross-provider matrix/dashboard aggregation** — a scheduled central pipeline that calls `can-i-deploy` and reports health.

Even then, the separate project must:

- check out the **exact provider commit** or use an immutable image built from it;
- publish verification results with that exact **provider version** and **branch**;
- post a commit status back to the provider MR if you want to block merges;
- have broker credentials, provider fixtures, and network access.

Otherwise it verifies `main` while claiming a different version — the matrix becomes untrustworthy.

---

## GitLab-specific design and gotchas

### Pipeline sources

Use `rules` / `workflow:rules` on `CI_PIPELINE_SOURCE`:

- `merge_request_event` — provider MR verification.
- `push` + default branch — post-merge verification.
- `trigger` — Pact Broker webhook via a pipeline trigger token.
- `pipeline` — multi-project pipeline triggered with `trigger`/`CI_JOB_TOKEN` (not the same as a trigger token).

GitLab docs: [Trigger pipelines with the API](https://docs.gitlab.com/ci/triggers/), [Downstream pipelines](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/), [Merge request pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/).

### The big GitLab trap: trigger tokens take a `ref`, not a SHA

The GitLab pipeline-trigger API accepts `ref=<branch-or-tag>`, not a commit SHA. Pact's `contract_requiring_verification_published` webhook gives you:

- `${pactbroker.pactUrl}`
- `${pactbroker.providerVersionNumber}`
- `${pactbroker.providerVersionBranch}`

So do **not** assume `CI_COMMIT_SHA` is the provider version. Instead:

1. Trigger the pipeline on a trusted ref, preferably `ref=main`.
2. Pass `PACT_PROVIDER_VERSION` and `PACT_PROVIDER_BRANCH` as variables.
3. In the job, `git checkout --detach "$PACT_PROVIDER_VERSION"` (use `GIT_DEPTH: 0` or a reliable fetch).
4. Publish verification results with `$PACT_PROVIDER_VERSION`, not `$CI_COMMIT_SHA`.

This also avoids running the webhook pipeline from an arbitrary branch's `.gitlab-ci.yml` — trigger `main` so the CI config is trusted, then check out the historical SHA for verification.

### Recommended job shape

```yaml
workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - if: '$CI_PIPELINE_SOURCE == "trigger"'
    - when: never

verify:pacts:
  stage: test
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
  script:
    - ./mvnw verify \
        -Dpact.verifier.publishResults=true \
        -Dpact.provider.version="$CI_COMMIT_SHA" \
        -Dpact.provider.branch="$CI_COMMIT_REF_NAME"

verify:changed-pact:
  stage: test
  variables:
    GIT_DEPTH: "0"
  rules:
    - if: '$CI_PIPELINE_SOURCE == "trigger" && $PACT_URL'
  before_script:
    - git checkout --detach "$PACT_PROVIDER_VERSION"
  script:
    - ./mvnw verify \
        -Dpact.verifier.publishResults=true \
        -Dpact.provider.version="$PACT_PROVIDER_VERSION" \
        -Dpact.provider.branch="$PACT_PROVIDER_BRANCH"
        # configure pact-jvm to verify $PACT_URL only
```

Wire the actual pact-jvm task to `PACT_URL`; the snippet is the pipeline shape, not a full pact-jvm config. For the cost-optimised version, have `verify:changed-pact` pull a SHA-tagged provider image/artifact instead of running a fresh build — see [Optimising the cost](#optimising-the-cost-dont-rebuild-the-provider-per-pact).

### Broker webhook

Use the `contract_requiring_verification_published` event, not the deprecated `contract_content_changed`:

```text
POST https://gitlab.example.com/api/v4/projects/<PROVIDER_PROJECT_ID>/trigger/pipeline
  token=<TRIGGER_TOKEN>
  ref=main
  variables[PACT_URL]=${pactbroker.pactUrl}
  variables[PACT_PROVIDER_VERSION]=${pactbroker.providerVersionNumber}
  variables[PACT_PROVIDER_BRANCH]=${pactbroker.providerVersionBranch}
```

Pact's [GitLab webhook template](https://docs.pact.io/pact_broker/webhooks/template_library) uses the query-string form; a form-encoded POST is usually cleaner because `PACT_URL` contains special characters. Whichever you use, ensure the pact URL is URL-encoded.

Prerequisites for that event, per the [webhooks docs](https://docs.pact.io/pact_broker/webhooks):

- provider main branch configured in the broker;
- verification results published with the branch property;
- provider version number can be mapped to a commit;
- deployments/releases recorded if you want deployed versions verified.

### Security notes

- Create a dedicated **pipeline trigger token** per provider project; rotate it.
- Store the token in the Pact Broker webhook config, not in the repo.
- The GitLab docs warn that a leaked trigger token can force unscheduled deployments or access CI variables — restrict trigger pipelines so they only run verification, never deploy.
- Keep `PACT_BROKER_TOKEN` masked and protected.
- Add the GitLab host to the broker's webhook whitelist.
- Be careful with fork MRs: GitLab protected variables are not available to fork MR pipelines, so don't expect broker credentials in untrusted fork contexts.
- If you use a separate verifier project, cross-project access requires job-token allowlists and explicit permissions — more moving parts to secure.

### Consumer side

In the consumer pipeline:

- publish the pact with the consumer version and branch;
- run `can-i-deploy` in the consumer PR pipeline with `--retry-while-unknown` so it waits for the webhook-triggered provider verification.

That closes the loop: consumer publishes → broker webhook → provider verification → result published → consumer `can-i-deploy` unblocks.

---

## Optimising the cost: don't rebuild the provider per pact

A common objection is: "rebuilding the provider for every consumer pact change is expensive." Correct — so the recommended flow should not rebuild per pact. The unit of work is **per (provider version, pact content) pair**, not per consumer build.

### What the broker already de-duplicates

- `contract_requiring_verification_published` fires only when pact content actually changes.
- It fires only for provider versions that are missing a verification result for that pact content: the latest version from the provider's main branch, plus any version currently deployed/released. Those versions are de-duplicated.
- If the pact content is unchanged, it is "pre-verified" and no provider build is triggered.
- If a verification already exists for that provider version and pact content, the webhook does not trigger again.

So the trigger frequency is tied to real contract changes and missing provider results — not to every consumer pipeline run.

### How to make each verification cheap

1. **Build once per provider SHA.** On the normal provider pipeline, produce an artifact or container image tagged with `$CI_COMMIT_SHA` (e.g. `registry.example.com/provider:$CI_COMMIT_SHA`).
2. **Verify without rebuilding.** The webhook-triggered job checks out or pulls that exact artifact/image and runs only the pact verification task. It should not run the provider's full unit/integration suite again.
3. **Fall back only when necessary.** If the artifact/image for a historical or deployed SHA is missing, then build it — but retain images for deployed versions so this is rare.
4. **Serialise duplicate work.** Use a per-version resource group (e.g. `resource_group: pact-verify-$PACT_PROVIDER_VERSION`) and/or check the broker for an existing result before running, so multiple webhook triggers for the same provider version do not stampede.
5. **Batch when many consumers change pacts.** Instead of one pipeline per pact, a single provider verification job can pull all pacts requiring verification from the broker's "pacts for verification" API and verify them together. Keep publishing results per pact.
6. **Prefer an existing deployed instance when appropriate.** For deployed-environment verification, run the verifier against the running provider at that version instead of rebuilding from source — provided the deployed version maps reliably to the provider version recorded in the broker.
7. **Keep pending and WIP pacts enabled.** New consumer contracts can be verified without failing the provider's main build, while still producing the results `can-i-deploy` needs.

Conceptually, the changed-pact job becomes:

```yaml
verify:changed-pact:
  image: registry.example.com/provider:$PACT_PROVIDER_VERSION
  needs: []
  resource_group: pact-verify-$PACT_PROVIDER_VERSION
  rules:
    - if: '$CI_PIPELINE_SOURCE == "trigger" && $PACT_URL'
  script:
    # run only the pact-jvm verification task against $PACT_URL
    - ./mvnw verify \
        -Dpact.verifier.publishResults=true \
        -Dpact.provider.version="$PACT_PROVIDER_VERSION" \
        -Dpact.provider.branch="$PACT_PROVIDER_BRANCH"
```

This is the key architectural point: **a separate verifier project only wins on cost if it reuses a shared, prebuilt provider image/artifact.** If it still clones and rebuilds the provider for every pact, it has the same cost plus cross-project auth and MR-status plumbing. A provider-owned verify job that pulls a SHA-tagged image gets the same optimisation with less operational overhead.

### Cost comparison

| Approach | Build cost | Verification cost | Notes |
|---|---|---|---|
| Rebuild provider per pact | High — repeated builds of the same SHA | Low | Wasteful; avoid |
| Build once per SHA, verify from image/artifact | One build per provider commit | Low | Recommended default |
| Batch verify all pending pacts per provider version | One build per provider commit | Amortised across pacts | Good for many consumers |
| Verify a deployed instance | No build | Network + fixture cost | Good for deployed-version checks; requires reliable version mapping |

---

## Decision guide

| Option | Use when |
|---|---|
| **Job in provider pipeline** (recommended) | Normal provider repo, you own the CI, you want MR blocking |
| **Child/triggered pipeline in provider repo** | You want the verification config separate or the MR pipeline lean, but still same repo/version |
| **Separate GitLab project** | Central platform harness, unmodifiable legacy CI, network isolation, or deployed-environment verification |
| **Scheduled-only verifier** | Complementary safety net for stale/deployed versions — **not** a replacement for PR/webhook verification |
| **Verifier in consumer pipeline** | Only the "webhookless" fallback when the broker cannot reach provider CI; version provenance is harder |

---

## Recommended plan for your case

Assuming a normal JVM provider repo whose CI you can edit:

1. Build the provider once per SHA and publish an immutable artifact or container image tagged with `$CI_COMMIT_SHA`.
2. Add `verify:pacts` to the provider pipeline for MRs and main, using the built artifact/image.
3. Add `verify:changed-pact` for `CI_PIPELINE_SOURCE == "trigger"`, pulling the image/artifact for `$PACT_PROVIDER_VERSION` rather than rebuilding; fall back to a build only if it is missing.
4. Add a per-version resource group and/or an existing-result check to avoid duplicate verification work.
5. Configure the Pact Broker webhook with `contract_requiring_verification_published` pointing at the provider project trigger token.
6. Add `can-i-deploy` before provider deploys and `record-deployment` after.
7. Add a consumer-side `can-i-deploy --retry-while-unknown` gate.
8. If contract volume is high, batch verification of pending pacts; otherwise keep one webhook-triggered verification per changed contract.
9. Optionally add a centralised deploy/verify project later for deployed-version checks — but only if it reuses the same provider images rather than rebuilding them.

To turn this into a concrete `.gitlab-ci.yml` and Pact Broker webhook config, the following details are needed: provider project path, default branch, the pact-jvm verification command, whether the broker can reach your GitLab instance, and whether you need to verify deployed/released provider versions.

---

## Sources

- [Pact Broker webhooks](https://docs.pact.io/pact_broker/webhooks)
- [Pact webhook template library](https://docs.pact.io/pact_broker/webhooks/template_library)
- [Pact Nirvana Step 6 — provider verification job called by webhook](https://docs.pact.io/pact_nirvana/step_6)
- [Recommended configuration for verifying pacts](https://docs.pact.io/provider/recommended_configuration)
- [can-i-deploy](https://docs.pact.io/pact_broker/can_i_deploy)
- [GitLab — trigger pipelines with the API](https://docs.gitlab.com/ci/triggers/)
- [GitLab — downstream pipelines](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/)
- [GitLab — CI/CD job token](https://docs.gitlab.com/ci/jobs/ci_job_token/)
- [GitLab — merge request pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/)
