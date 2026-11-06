# Pact provider verification: selectors and attributes for the two jobs

The two verification jobs are **not** symmetric:

- **Job A — provider changed:** *pull* pacts from the broker using consumer version selectors.
- **Job B — pact changed (webhook):** *push* one pact URL into the verifier. It must **not** use selectors.

---

## Job A: `verify:pacts` — provider changed, pull from broker

This job asks the broker: "give me the pacts this provider is responsible for." The filter is called a **consumer version selector**.

### Selector properties

| Selector | Returns | Requires |
|---|---|---|
| `{ mainBranch: true }` | The latest pact from each consumer's configured main branch | Consumer publishes with branch + has `mainBranch` configured |
| `{ matchingBranch: true }` | The latest pact from any consumer branch with the same name as the provider's current branch | Provider branch is set |
| `{ deployedOrReleased: true }` | All consumer versions currently deployed or released in any environment | `record-deployment` / `record-release` used |
| `{ deployed: true }` | Consumer versions currently deployed to any environment | `record-deployment` |
| `{ released: true }` | Consumer versions currently released/supported | `record-release` |
| `{ deployed: true, environment: "prod" }` | Consumer versions deployed to a specific environment | `record-deployment` with that env |
| `{ released: true, environment: "prod" }` | Consumer versions released to a specific environment | `record-release` with that env |
| `{ environment: "prod" }` | Versions deployed or released in a specific environment | Deployment/release records |
| `{ branch: "feat-x" }` | Latest pact from a named consumer branch | Consumer branch published |
| `{ branch: "feat-x", fallbackBranch: "main" }` | Named branch, falling back to another branch | Consumer branches published; fallback is discouraged |
| `{ tag: "prod", latest: true }` | Latest pact with a tag — legacy | Tags |
| `{ tag: "prod" }` | All pacts with a tag — legacy | Tags |
| `{ tag: "prod", latest: true, fallbackTag: "main" }` | Latest tag with fallback — legacy | Tags; fallback is discouraged |
| `{ consumer: "my-consumer" }` | Narrows any selector to one consumer | — |
| `{ latest: true }` | Overall latest pact for each consumer | Not recommended — race conditions across branches |

### Recommended selector set

```json
[
  { "mainBranch": true },
  { "matchingBranch": true },
  { "deployedOrReleased": true }
]
```

- `mainBranch` covers normal development.
- `matchingBranch` supports coordinated feature-branch work.
- `deployedOrReleased` protects versions already live in environments.
- The broker **de-duplicates by pact content**, so overlapping selectors do not cause duplicate verification.

In pact-jvm:

```java
@PactBrokerConsumerVersionSelectors
public static SelectorBuilder consumerVersionSelectors() {
  return new SelectorBuilder()
      .mainBranch()
      .matchingBranch()
      .deployedOrReleased();
}
```

Or pass raw JSON via `pactbroker.consumerversionselectors.rawjson`.

### Job A on a feature branch vs main

The same job definition can serve both, but the effective selectors and pending/WIP settings are different.

| Provider context | Selectors | Pending | WIP | Publish branch |
|---|---|---|---|---|
| **Feature branch** | `mainBranch` + `matchingBranch` + `deployedOrReleased` | `false` | none | feature branch |
| **Main branch** | `mainBranch` + `matchingBranch` + `deployedOrReleased` | `true` | `includeWipPactsSince` | `main` |
| **Job B webhook** | none — `PACT_URL` only | n/a | n/a | webhook provider branch |

- `matchingBranch` is dynamic: on provider `feat-x` it selects consumer `feat-x`; on provider `main` it selects consumer `main`.
- If consumer and provider branch names differ, `matchingBranch` finds nothing. Use an explicit `{ "branch": "consumer-branch" }` selector or enforce a shared branch-naming convention.
- On a feature branch, set `enablePendingPacts=false` so the new consumer need fails the provider branch until it is implemented.
- Do **not** set `includeWipPactsSince` on a feature branch. WIP belongs to the main branch.
- Keep `deployedOrReleased` on the feature-branch job so the change is checked against consumers already running in environments.
- A success on the provider feature branch is early feedback only. It does **not** make the pact non-pending for `main`.
- The final gate is provider `main`: its WIP verification must succeed before consumer `can-i-deploy` passes.

Feature-branch flow:

1. Consumer publishes a feature-branch pact.
2. Provider feature branch verifies it via `matchingBranch`; success is branch-local.
3. Provider merges the implementation to `main`.
4. Provider `main` pipeline verifies the consumer feature pact via WIP and publishes success against the provider `main` version.
5. Consumer `can-i-deploy` / `can-i-merge` now passes.

If you want separate behaviour without duplicating the whole job, use CI rules to set:

```text
feature branch: PENDING=false, WIP_SINCE unset
main branch:    PENDING=true,  WIP_SINCE=<date>
```

### Other attributes to handle for Job A

| Attribute | What to set | Why |
|---|---|---|
| `enablePendingPacts` | `true` on main, `false` on feature branches | New consumer expectations should not break the provider main build. On a feature branch, disable pending so the change must actually pass. Failures are still published to the broker. |
| `includeWipPactsSince` | e.g. `2025-01-01` on main only | Automatically verify new consumer feature-branch pacts not explicitly selected. Pair with pending. Use a ~30-day window. Do not set it on a feature branch. |
| `providerVersion` | `$CI_COMMIT_SHA` | Must match the code being verified. |
| `providerVersionBranch` | `$CI_COMMIT_REF_NAME` | Needed for pending/WIP calculations and matrix correctness. |
| `publishVerificationResult` | `true` | Writes the pass/fail result back to the broker. |
| `providerTags` | optional | Only if you still use the tag workflow; branches are preferred. |
| `@IgnoreNoPactsToVerify` | optional | Prevents failure when a provider genuinely has no consumer pacts yet. Default is to fail. |
| `@Consumer` | optional | Limits the test class to one consumer. |
| `@PactFilter` / `pact.filter.description` | optional | Filters **interactions**, not pacts. Useful for path or state-based subsets. |
| `pact.verifier.buildUrl` | optional | Links the broker result back to the CI build. |

Important: `enablePendingPacts` and `includeWipPactsSince` belong **only to Job A**, and their values are context-specific: pending on main, non-pending on feature branches, WIP on main only. They are calculated against the provider branch.

### What pending does and does not do

- A **pending** pact failure is still published to the broker as a failure.
- Pending only changes whether the provider build exits non-zero.
- The consumer still cannot deploy if the verification failed — its `can-i-deploy` will fail.
- Pending is calculated per provider **branch**, so publish the provider branch correctly.

### What WIP does

- WIP picks up consumer branch pacts that are **not** explicitly selected but are the latest for their branch.
- WIP pacts are always pending, so failures do not break the provider build.
- It requires a provider branch and a `includeWipPactsSince` date.
- Start with a ~30-day window; longer windows increase broker query load.

---

## Job B: `verify:changed-pact` — pact changed via webhook

This job receives one contract and must verify exactly that contract. Do **not** configure consumer version selectors here.

| Attribute | What to set | Why |
|---|---|---|
| Pact source | `PACT_URL` only | Verifies the changed contract, not the full suite |
| `providerVersion` | `$PACT_PROVIDER_VERSION` | The exact provider version from the webhook, not the pipeline's `CI_COMMIT_SHA` |
| `providerVersionBranch` | `$PACT_PROVIDER_BRANCH` | The provider branch from the webhook, not necessarily the branch the pipeline was triggered on |
| `publishVerificationResult` | `true` | Publishes the result against that exact provider version |
| Consumer version selectors | **none** | Setting them would verify more than the changed pact |
| `enablePendingPacts` | **none / irrelevant** | Pending is not applied to webhook-triggered verification |
| `includeWipPactsSince` | **none / irrelevant** | WIP is a provider-change feature |
| `pactBrokerUrl` | **not needed for pact selection** | The pact URL already identifies the contract |
| Broker auth | Still required for publishing | Supply auth on the pact URL source or broker config |
| `@Consumer` + `@IgnoreNoPactsToVerify` | Use if you have multiple consumer test classes | Prevents the wrong test class picking up the pact URL |
| `pact.filter.consumers` | Set if not using `@Consumer` | Required when overriding the pact URL in pact-jvm |

In pact-jvm, the common pattern is:

```java
@AllowOverridePactUrl
// plus JVM properties:
// -Dpact.filter.pacturl=$PACT_URL
// -Dpact.filter.consumers=<consumer-name>
```

or use `@PactUrl` / `@PactUrl(urls = "${PACT_URL}")` if your harness is structured that way.

### Critical Job B differences

- **It is expected to fail on a mismatch.** There is no pending safety net.
- **Publish against the webhook's provider version and branch**, not the pipeline's ref.
- **Keep the provider states working.** The changed pact may require fixtures just like the full-suite job.
- **Do not run the full provider test suite again.** Run only the pact verification task.
- **Do not attach downstream deploy jobs to this pipeline.** It is an "out of band" verification build.
- **Do not rebuild the provider per pact.** Pull the SHA-tagged image/artifact instead.

---

## Side-by-side summary

| Concern | Job A: provider changed | Job B: pact changed |
|---|---|---|
| Pact selection | Consumer version selectors | Single `PACT_URL` |
| Selector set | `mainBranch`, `matchingBranch`, `deployedOrReleased` | None |
| Feature branch behaviour | `matchingBranch` selects consumer branch of the same name; pending disabled; no WIP | n/a |
| Main branch behaviour | pending enabled; WIP verifies recent consumer feature-branch pacts | n/a |
| Pending pacts | Enabled on main, disabled on feature branches | Not applicable |
| WIP pacts | Optional, main branch | Not applicable |
| Provider version | `$CI_COMMIT_SHA` | `$PACT_PROVIDER_VERSION` |
| Provider branch | `$CI_COMMIT_REF_NAME` | `$PACT_PROVIDER_BRANCH` |
| Missed expectation fails build? | Only if not pending | Yes, always |
| Purpose | Full regression against all supported consumer versions | Fast feedback on one changed contract |
| Typical trigger | MR/push to provider | Broker webhook |

---

## Common pitfalls

1. **Using `latest: true` without a tag** — race conditions across consumer branches. Prefer `mainBranch`.
2. **Forgetting to publish the consumer branch** — `mainBranch` and `matchingBranch` selectors return nothing.
3. **Forgetting `record-deployment`** — `deployedOrReleased` returns nothing useful.
4. **Setting pending on Job B** — it has no effect; the webhook build is meant to fail.
5. **Publishing Job B with `CI_COMMIT_SHA`** — you will record the wrong provider version unless the pipeline ref actually equals the verified version.
6. **Setting system properties only on the Maven/Gradle command line** — pact-jvm reads them in the **test JVM**, so configure Surefire/Gradle `systemPropertyVariables`.
7. **Using selectors in Job B** — you lose the "verify only the changed pact" guarantee.
8. **Filtering interactions and expecting pacts to be filtered** — `@PactFilter` filters interactions; consumer version selectors filter pacts.
9. **No provider branch set** — pending/WIP calculations and matrix results become unreliable.
10. **Too wide a WIP window** — broker query load and timeouts grow with the date range.
11. **Using main-branch WIP/pending settings on a feature branch** — feature branches should disable pending and not enable WIP.
12. **Expecting a feature-branch success to unblock main** — pending/verification is per provider branch; provider `main` must verify the pact too.

---

## References

- [Consumer Version Selectors](https://docs.pact.io/pact_broker/advanced_topics/consumer_version_selectors)
- [Pending pacts](https://docs.pact.io/pact_broker/advanced_topics/pending_pacts)
- [Work In Progress pacts](https://docs.pact.io/pact_broker/advanced_topics/wip_pacts)
- [Recommended configuration for verifying pacts](https://docs.pact.io/provider/recommended_configuration)
- [Provider verification results](https://docs.pact.io/pact_broker/advanced_topics/provider_verification_results)
- [Pact JVM JUnit provider runner](https://docs.pact.io/implementation_guides/jvm/provider/junit)
