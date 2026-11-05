No live tool connected (or manual export chosen) — rendering the full backlog below as markdown. Copy the sections you need into your tool of choice.

Mode: CDCT      Stack: JVM      CI: GitLab CI      Broker: your Pact Broker or PactFlow tenant

> **Note:** this checkout's plugin has no `examples/` directory, so the `CLAUDE.md.*` snippets that Step 6.5 / the manual export should inline cannot be rendered. Phase 4 and 4b below flag the gap; the ticket prose still references the expected filenames.

---

# Contract Testing Onboarding: the team (the consumer ↔ the provider)

*Type: Epic · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

## Why this Epic exists

This Epic tracks the team's end-to-end onboarding to contract testing — from the first planning conversation through to a published consumer contract, a verified provider contract, and a `can-i-deploy` gate wired into CI. It exists so the team has a single place to triage and sequence the work, not a checklist of disconnected tasks.

The structure follows the Contract Testing Flywheel: Planning → Requirements → Design → Implementation → Testing → Deployment → Lessons-Learned (with an optional Management Dashboard). Every child Story / Task has its own AC, link bundle, and tooling suggestions.

## Scope of this onboarding

- **Consumer:** the consumer
- **Provider:** the provider
- **Stack:** JVM
- **CT mode:** CDCT
- **Broker:** your Pact Broker or PactFlow tenant
- **CI tool:** GitLab CI

Rerun `/contract-testing-flywheel` for additional consumer/provider pairs; one Epic per pair keeps each backlog cleanly scoped.

## Definition of done for the Epic

- Phases 1–7 complete; their acceptance criteria are all met.
- the consumer's contract is published to the broker and visible in the matrix.
- the provider's verification passes against the consumer's latest published contract.
- `can-i-deploy` runs in both deploy pipelines and gates merges to release branches.
- The team has captured lessons-learned and best practices in their internal wiki (Phase 7).
- (If opted-in) Phase 8's management dashboard is live and shared with engineering management.

## References

- [Pact docs](https://docs.pact.io)
- [PactFlow docs](https://docs.pactflow.io)
- [Pact Nirvana ladder](https://docs.pact.io/pact_nirvana)
- [pact-jvm](https://github.com/pact-foundation/pact-jvm)

---
*If you're using Claude Code: `/swagger-contract-testing` provides end-to-end help authoring + running contract tests. `smartbear-mcp` offers AI-assisted test generation + PactFlow operations.*

---

## Phase 1 — 1. Planning — agree scope, versioning, environments (the team)

*Type: Task · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

Contract testing only delivers value when both sides of an integration agree on what they're contracting about. Before a single Pact test gets written, the team needs a shared picture of which systems are in scope, which integrations have caused breaking changes recently, and how versioning + environments will be named in the broker. Skipping this conversation is the most common cause of stalled rollouts.

### What to do

- Run a 30-60 minute working session with the team and the owners of the consumer and the provider.
- List recent breaking changes between the consumer and the provider (or any integration partner — even if it's not the chosen pair, the patterns are informative).
- Confirm the consumer ↔ the provider is the right first pair: highest pain, most frequent integration, or most blocked by manual coordination.
- Agree the naming convention for **pacticipant versions** (recommended: git SHA, optionally suffixed with a build number).
- Agree the **environment names** that will appear in the broker matrix (e.g. `test`, `staging`, `production`).
- Identify who owns release decisions on each side (used in Phase 6 when `can-i-deploy` blocks a merge).

### Acceptance criteria

- A 1-page planning doc exists in the team's docs repo (or wiki) capturing: chosen consumer/provider pair, version-naming convention, environment names, and the recent-breaking-change history that motivated the choice.
- The doc is linked from this ticket.
- Both sides' release owners are named in the doc.

### References

- [Pact Nirvana — maturity ladder (start with Cloning + Versioning levels)](https://docs.pact.io/pact_nirvana)
- [Versioning in the Pact Broker](https://docs.pact.io/getting_started/versioning_in_the_pact_broker)
- [Environments in PactFlow](https://docs.pactflow.io/docs/permissions/environments)

---
*If you're using Claude Code: `/swagger-contract-testing` can help shape the planning doc; `smartbear-mcp` provides PactFlow context if you need to inspect existing pacticipants.*

---

## Phase 2 — 2. Requirements Analysis — baseline DORA metrics (the team)

*Type: Task · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

To prove contract testing was worth the rollout (Phase 7), the team needs a *before* picture. This phase captures the baseline numbers that will be re-measured later. Without a baseline, the team's leadership has to take the value on faith — which makes funding future rollouts to adjacent teams much harder.

### What to do

- Identify the metrics that matter most to the team and its leadership. Default set (DORA + contract-testing-specific):
  - Lead time — from code committed to deployed.
  - Deployment frequency — production deploys per week.
  - Change-failure rate — % of deploys that need a follow-up fix.
  - MTTR — mean time to restore after a failure.
  - Deployment rework rate — % of deploys in the last 6 months that were unplanned bug-fix deploys.
  - Services independently deployable — count of services the team can deploy without coordinating with another team.
  - Integration-test maintenance — % of the team's time spent maintaining E2E tests.
- For each chosen metric: identify the source of truth (CI, deploy tool, JIRA, manual estimate) and the owner who'll re-measure it in Phase 7.
- Capture the current numbers — even if rough — in the team's wiki or a tracking doc.

### Acceptance criteria

- A tracking doc exists with each chosen metric, its current baseline value, the data source, and the named owner.
- The doc is linked from this ticket.
- The Phase 7 lessons-learned ticket carries a follow-up to re-measure these.

### References

- [DORA — Four key metrics](https://dora.dev/research/2024/dora-report/)
- [Pact ROI thinking (qualitative)](https://docs.pact.io/pact_nirvana)
- [PactFlow audit log API (for measuring activity later)](https://docs.pactflow.io/docs/api/audit)

---
*If you're using Claude Code: `smartbear-mcp` exposes the PactFlow audit API; useful when re-measuring activity in Phase 7.*

---

## Phase 3a — 3a. Design — Knowledge ramp-up (the team)

*Type: Task · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

Before writing the first contract test, the team needs enough shared mental model of contract testing that conversations don't stall on terminology. This is a pure learning task — no code yet — modelled on the structure that has worked for prior teams adopting Pact / PactFlow / Drift.

### What to do

- Skim the **Pact docs** (you do not need to read everything — focus on the "Getting Started" + "Pact Nirvana" sections).
- Watch **one or two intro videos** on consumer-driven contract testing.
- Skim the **PactFlow product docs**, focused on the broker concepts (pacticipants, environments, deployments) and `can-i-deploy`.
- Clone a reference **example repo** in JVM (link below) and run its tests locally — even a 5-minute roundtrip helps the concepts land.

### Acceptance criteria

- Every engineer assigned to Phases 4 / 4b can articulate the difference between a consumer test, a provider verification, and a pact in 1–2 sentences.
- A short summary or comment on this ticket lists which materials were consumed and any gaps to follow up on.

### References

- [Pact docs (start here)](https://docs.pact.io)
- [Pact Nirvana — the maturity ladder](https://docs.pact.io/pact_nirvana)
- [Pact implementation guides (per language)](https://docs.pact.io/implementation_guides)
- [pact-jvm](https://github.com/pact-foundation/pact-jvm)
- [PactFlow docs](https://docs.pactflow.io)
- [Pact Foundation GitHub org (sample apps)](https://github.com/pact-foundation)

---
*If you're using Claude Code: `swagger-contract-testing:pactflow` skill answers conceptual questions and walks through Pact / PactFlow flows.*

---

## Phase 3b — 3b. Design — Local CT demo (the team)

*Type: Task · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

The fastest way for the team to internalise contract testing is to see one work end-to-end on their own laptop, in JVM. This phase is a throwaway demo — not production code — designed to make every concept from Phase 3a tangible before the team commits to the production implementation in Phases 4 / 4b.

### What to do

- Pick a single tiny interaction between a mock consumer and a mock provider (e.g. `GET /widgets/:id`).
- In a new throwaway repo, set up the JVM side of pact-jvm.
- Write a single consumer test that produces a pact file.
- Write a single provider verification that consumes the pact file from disk.
- Publish the pact to your Pact Broker or PactFlow tenant (use a test/sandbox tenant if available — don't publish demo pacts to the production broker).
- Show the team how the test failure mode looks when the provider's response shape no longer matches the consumer's expectation.

### Acceptance criteria

- The throwaway demo runs end-to-end on at least one engineer's laptop.
- The demo is checked in to a private throwaway repo (so the team can revisit it).
- the team has seen at least one **green** run and one **red** run (deliberately broken) of the demo.
- The team has flagged any open questions that came up during the demo and added them to the Phase 4 / 4b ticket as risks.

### References

- [Pact docs](https://docs.pact.io)
- [pact-jvm](https://github.com/pact-foundation/pact-jvm)
- [PactFlow docs](https://docs.pactflow.io)

---
*If you're using Claude Code: `swagger-contract-testing:pact-generator` skill can scaffold the consumer test from your example client code; `/swagger-contract-testing` walks through the end-to-end flow.*

---

## Phase 4 — 4. Consumer-side contract tests (the consumer → the provider)

*Type: Story · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

This is the team's first piece of *production* contract testing. the consumer records what it expects from the provider as executable tests; those tests produce a pact file; the pact file is published to your Pact Broker or PactFlow tenant. From this point on, breaking changes to the provider that the consumer depends on get caught before they reach production.

### Where the consumer tests live

Inside the consumer repository, alongside its existing unit and integration tests. Pact tests exercise the consumer's real HTTP client, so colocation keeps the client and its contract expectations in one PR, lets the pact file fall out as a build artefact of the consumer's own test suite, and — for BDCT — lets the contract record from real request/response traffic during the consumer's tests.

This matches every official Pact workshop and reference repo (`pactflow-example-consumer-*`).

### What to do

- Add a `pact/` test directory inside the consumer, next to its existing tests.
- Set up pact-jvm (see https://github.com/pact-foundation/pact-jvm).
- Write consumer tests that define each expected interaction with the provider chosen in Phase 1.
- Run the suite to generate the pact file.
- Configure publishing to your Pact Broker or PactFlow tenant. Consumer version tag = git SHA.
- Add a GitLab CI step to the consumer's existing pipeline that runs the tests on PRs and publishes the pact on merge to main.
- Route publish failures to the team's notification channel.

### Acceptance criteria

- Pact tests live in a `pact/` directory inside the consumer repository.
- pact-jvm is set up (CDCT) — or BDCT consumer-contract recording is configured (BDCT) — and produces a contract file on a local run.
- GitLab CI runs the tests on every PR and publishes on merge to main; the publish step is visible in the pipeline.
- Publish failures notify the team's chosen channel.
- `CLAUDE.md` from the plugin's `examples/CLAUDE.md.cdct-consumer.md` (or the BDCT-flavoured equivalent) is copied into the consumer with placeholders filled in.
- The first published contract appears in your Pact Broker or PactFlow tenant's matrix for the consumer ↔ the provider.

### References

- [Pact docs](https://docs.pact.io)
- [pact-jvm](https://github.com/pact-foundation/pact-jvm)
- [pactflow-example-consumer-js (colocated reference)](https://github.com/pactflow/example-consumer-js)
- [PactFlow docs](https://docs.pactflow.io)
- [Pact Nirvana](https://docs.pact.io/pact_nirvana)

---
*If you're using Claude Code:*
- *`/swagger-contract-testing` — end-to-end help authoring tests.*
- *`swagger-contract-testing:pact-generator` skill — scaffold tests from existing client code.*
- *`swagger-contract-testing:pact-reviewer` skill — audit tests for false positives, naming, and best-practice violations.*
- *`swagger-contract-testing:pactflow` skill — publish, can-i-deploy, matrix.*
- *`smartbear-mcp` server — AI-assisted test generation and PactFlow operations.*
- *Drop `examples/CLAUDE.md.cdct-consumer.md` from this plugin into the consumer's root.*

### CLAUDE.md template for the new consumer repo

> **Unavailable in this checkout.** The skill expects `examples/CLAUDE.md.cdct-consumer.md`, but that file is not present under `/home/david/pact/.agents/skills/contract-testing-flywheel/`. Nothing can be pasted into the consumer repo until it is added.

---

## Phase 4b — 4b. Provider-side verification (the provider ← the consumer)

*Type: Story · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

the provider now needs to prove it actually meets the expectations that the consumer published in Phase 4. This is the other half of the contract: a verification harness that pulls the published contract from your Pact Broker or PactFlow tenant, runs it against the provider's implementation (or its authoritative OpenAPI spec, for BDCT), and reports a pass/fail.

### What to do

- In the provider's repository, add a Pact provider verification harness using pact-jvm.
- Implement **provider states** for any consumer expectations that need specific fixture data (use the convention `"<resource> exists with <condition>"`, lower-case + present tense).
- Configure the harness to pull the latest pact for the consumer from your Pact Broker or PactFlow tenant and verify it against a locally-running the provider.
- Hook the verification into the team's GitLab CI pipeline: run on PRs, publish results back to the broker tagged with the provider version (git SHA).
- Wire failure notifications into the team's notification channel of choice.

### Acceptance criteria

- Provider verification harness lives in the provider's repo and runs locally green against a published consumer pact.
- Provider states are implemented for every consumer expectation that needs one.
- GitLab CI runs the verification on every PR; results are published back to your Pact Broker or PactFlow tenant.
- Failure notifications reach the team's chosen channel.
- **`CLAUDE.md` from the plugin's `examples/CLAUDE.md.cdct-provider.md` has been copied into the provider's repo root and customised** (provider name, OpenAPI path, broker URL, CI tool, paths).

### References

- [Pact docs](https://docs.pact.io)
- [pact-jvm](https://github.com/pact-foundation/pact-jvm)
- [PactFlow docs](https://docs.pactflow.io)
- [Pact Nirvana](https://docs.pact.io/pact_nirvana)

---
*If you're using Claude Code:*
- *`/swagger-contract-testing` — end-to-end help with provider verification and BDCT flows.*
- *`swagger-contract-testing:pactflow` skill — publish provider contracts, run `can-i-deploy`, inspect the matrix.*
- *`smartbear-mcp` server — AI-assisted operations on PactFlow.*
- *Drop the matching `CLAUDE.md` from this plugin's `examples/` into the provider's repo root.*

### CLAUDE.md template for the new provider repo

> **Unavailable in this checkout.** The skill expects `examples/CLAUDE.md.cdct-provider.md`, but that file is not present under `/home/david/pact/.agents/skills/contract-testing-flywheel/`. Nothing can be pasted into the provider repo until it is added.

---

## Phase 5 — 5. Testing — first CI trigger (the team)

*Type: Story · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

Up to now, the consumer tests + provider verification have run on developer laptops. This phase moves them into the team's shared GitLab CI pipeline, so contract regressions get caught at PR time, not at deploy time. This is the first phase where contract testing actually defends production.

### What to do

- Add a GitLab CI job to the consumer's pipeline that runs the consumer tests on every PR.
- Add a publish-pact step on merge to the main branch.
- Add a GitLab CI job to the provider's pipeline that pulls the latest consumer pact and runs provider verification on every PR.
- Wire the broker to trigger the provider's verification job whenever the consumer publishes a new pact (via webhook).
- Configure failure notifications: failing build alerts go to the team's chosen channel with a summary of the failure.

### Acceptance criteria

- GitLab CI runs contract tests on every PR to both the consumer and the provider repos.
- On merge to main, contracts are published to your Pact Broker or PactFlow tenant.
- Broker webhook triggers the provider verification when the consumer publishes a new pact.
- Failing builds notify the team's chosen channel with a summary of the failure.

### References

- [Pact in CI (GitLab CI)](https://docs.pact.io/getting_started/versioning_in_the_pact_broker#using-git-tags)
- [Pact Broker webhook setup](https://docs.pact.io/pact_broker/webhooks)
- [PactFlow webhooks](https://docs.pactflow.io/docs/workshops/ci-cd/webhooks/)

---
*If you're using Claude Code:*
- *`/swagger-contract-testing` — end-to-end help wiring CI.*
- *`swagger-contract-testing:pactflow` skill — webhook + broker config + matrix.*
- *`smartbear-mcp` server — manage broker webhooks programmatically.*

---

## Phase 6 — 6. Deployment — can-i-deploy + record-deployment (the team)

*Type: Story · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

Catching contract regressions at PR time (Phase 5) is half the value. The other half is using the broker's matrix as a *deploy-time gate*: before the team deploys a new version of the consumer or the provider, the broker should be able to answer the question "is this version compatible with every other version currently running in the target environment?" That's what `can-i-deploy` does. Pair it with `record-deployment` so the matrix stays accurate.

This is Pact Nirvana's "Diamond" level.

### What to do

- Add a **`can-i-deploy`** step to each repo's deploy pipeline. The step queries your Pact Broker or PactFlow tenant for the target environment and exits non-zero (blocking the deploy) if the new version is not compatible with the deployed versions of integration partners.
- Add a **`record-deployment`** step after a successful deploy, so the broker matrix knows which version is now live in which environment.
- If working with Dev-Ops on shared deploy infrastructure, set up a deployment gateway / approval step that calls `can-i-deploy` on the team's behalf.
- (Optional) Set up broker webhooks to alert on matrix changes (compatible → incompatible) so the team finds out before a deploy is attempted.

### Acceptance criteria

- `can-i-deploy` runs in both the consumer's and the provider's deploy pipelines and blocks incompatible deploys.
- `record-deployment` runs after every successful deploy to a tracked environment.
- The broker matrix accurately reflects what's currently deployed in each environment (verified by spot-checking the matrix UI after the next two deploys).
- (Optional) The team has documented its escalation path for a failed `can-i-deploy` query (who to talk to, where the conversation happens).

### References

- [can-i-deploy](https://docs.pact.io/pact_broker/can_i_deploy)
- [Recording deployments + releases](https://docs.pact.io/pact_broker/recording_deployments_and_releases)
- [Pact in GitLab CI](https://docs.pact.io/getting_started/versioning_in_the_pact_broker#using-git-tags)
- [Pact Nirvana "Diamond" level](https://docs.pact.io/pact_nirvana#level-5-diamond)

---
*If you're using Claude Code:*
- *`/swagger-contract-testing` — end-to-end help wiring can-i-deploy.*
- *`swagger-contract-testing:pactflow` skill — query and explain matrix state, debug can-i-deploy failures.*
- *`swagger-contract-testing:pact-maintainer` skill — manage environments, record deployments, audit broker state.*
- *`smartbear-mcp` server — call can-i-deploy, record-deployment, and matrix programmatically.*

---

## Phase 7 — 7. Internal docs — lessons learned + best practices (the team)

*Type: Task · Labels: contract-testing-flywheel, contract-testing-onboarding, cdct*

### Why this phase

The work is no good to anyone else if only the team knows what it took to get here. This phase captures the team's hard-won lessons — gotchas, conventions, broker URLs, CI snippets, escalation paths — into a single internal page that future the team engineers (and the next team adopting contract testing) can read in 15 minutes and skip half the rediscovery cost.

It also re-measures the Phase 2 baseline metrics so the team can demonstrate the value.

### What to do

- Create a single page in the team's internal wiki titled "Contract testing — how we do it" (or similar).
- Capture, at minimum:
  - The chosen consumer/provider pair and why it was first.
  - Naming conventions (pacticipant versions, provider states, environments).
  - Broker URL + how to authenticate.
  - GitLab CI snippets for consumer publish, provider verify, and `can-i-deploy`.
  - Gotchas the team hit during Phases 3–6 (provider-state fixture issues, flaky tests, webhook misconfigurations, anything else).
  - Who to talk to when contract testing blocks a deploy (the team's contract-testing point person).
- Re-measure the metrics chosen in Phase 2. Compare against the baseline.
- Link the page from the team's README so it's discoverable.
- Have one engineer who *didn't* write the page read it cold and flag anything unclear.

### Acceptance criteria

- A single page exists in the team's internal wiki capturing the items above.
- The page is linked from the team's README (or equivalent landing page).
- Phase 2 metrics have been re-measured and the delta is noted on the page.
- At least one engineer who did not author the page has reviewed it cold and confirmed it would let them get started on contract testing without further help.

### References

- [Pact Nirvana](https://docs.pact.io/pact_nirvana)
- [PactFlow audit log API (useful for "how active have we been?" measurements)](https://docs.pactflow.io/docs/api/audit)

---
*If you're using Claude Code: `smartbear-mcp` can pull audit-log activity from PactFlow when re-measuring usage in this phase.*

---

Next steps:
- Open the root Epic and triage into your sprint plan.
- When Phase 4 / 4b kicks off, drop the matching CLAUDE.md from this plugin's examples/ folder into the new consumer / provider repo:
    examples/CLAUDE.md.cdct-consumer.md
    examples/CLAUDE.md.cdct-provider.md
    examples/CLAUDE.md.bdct-drift-provider.md
- For end-to-end help authoring tests, see /swagger-contract-testing.
