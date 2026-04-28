---
name: pr-review-qa-lens
description: Review a pull request from a QA perspective by identifying break risk, missing coverage, edge cases, and rollback concerns. Use when the user asks for QA review of a PR, test-risk review, what could break, missing regression coverage, or release concerns in a code review.
---

# PR Review QA Lens

Review pull requests as a QA partner, not just as a code reader.

## Inputs

You need the PR, diff, or change summary to review. If the release context, affected workflows, or expected rollback path is unclear, ask first.

## Workflow

### 1. Understand the change surface

Read the PR, changed files, and any linked requirements first.

Identify:

- affected user journeys
- touched integrations and data flows
- permissions, configuration, or schema impacts
- changed assumptions in validation, state, or timing

Do not stay at file-level detail only; translate the change into product risk.

### 2. Review through a QA lens

Ask:

- what could break directly
- what nearby behavior could regress indirectly
- what environments or data states matter
- what negative paths and edge cases are newly exposed
- what happens if deployment must be rolled back

Prefer risk discovery over style commentary.

### 3. Evaluate test coverage honestly

Check whether the change is covered at the right levels:

- unit or component tests
- API or integration tests
- end-to-end or workflow tests
- manual validation where automation is weak

Call out both missing tests and misleading tests that do not really cover the risk.

### 4. Look for edge-case gaps

Probe for:

- empty, null, malformed, and boundary inputs
- authorization and role differences
- concurrency, timing, and retries
- partial failures and downstream dependency issues
- data migration or backward-compatibility risks

If the change affects user-visible behavior, include accessibility and localization considerations when relevant.

### 5. Check the rollback story

Assess whether the change can fail safely:

- reversible deployment steps
- schema or data compatibility concerns
- feature flag or kill switch options
- monitoring or smoke checks needed after release

If rollback looks risky, say so explicitly.

## Output

Unless the user asks for another format, provide:

1. key QA risks
2. missing or weak coverage
3. edge cases worth testing
4. rollback or release concerns
5. recommended follow-up

## Report Back

Briefly tell the user:

- what looks most breakable
- what feels under-tested
- which edge cases deserve immediate attention
- whether the rollback story looks safe enough
