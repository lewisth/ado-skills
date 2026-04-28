---
name: release-readiness
description: Assess whether a change set is ready to release using smoke results, known issues, regression coverage, and deployment-risk checks. Use when the user asks for release sign-off, go/no-go support, launch readiness, deployment risk assessment, or a release validation checklist.
---

# Release Readiness

Evaluate release readiness with evidence, not optimism.

## Inputs

You need the release candidate, change set, build, or deployment scope to assess. If the target environment, release window, or sign-off expectations are unclear, ask first.

Recover as much release context as possible from the repository first, including deployment docs, migrations, feature flags, smoke suites, and monitoring references. Ask the user only for decisions or context the repo cannot answer, such as release window, sign-off expectations, accepted risks, or environment-specific constraints.

## Workflow

### 1. Establish release scope

Identify what is actually shipping:

- included features and fixes
- excluded items and known deferred work
- environment-specific changes
- dependencies on config, schema, or third-party systems

If the scope is fuzzy, call that out because sign-off quality depends on it.

### 2. Gather readiness evidence

Collect the current signals that matter:

- smoke test results
- regression coverage completed or missing
- known issues and accepted risks
- deployment steps and rollback plan
- monitoring, alerting, and post-release checks

Do not give release confidence without concrete evidence.

Explore the codebase and delivery artifacts before questioning the user. Check for release notes, deployment steps, rollback guidance, smoke coverage, alerting hooks, dashboards, and recent changes that affect operational risk.

### 3. Assess deployment risk

Review risk in terms of operational impact:

- irreversible data or schema changes
- dependency and integration fragility
- auth, permissions, or configuration changes
- traffic sensitivity and scale concerns
- blast radius if the release fails

State what makes the release low, medium, or high risk.

### 4. Check quality gates honestly

Confirm whether the release has enough confidence across:

- core workflow smoke coverage
- high-risk regression areas
- unresolved defects and workarounds
- support readiness and stakeholder awareness

If sign-off depends on unverified assumptions, say so plainly.

### 5. Recommend a go/no-go posture

Choose the clearest honest recommendation:

- go
- go with explicit risks
- hold pending specific validation
- no-go

Tie the recommendation to evidence, not intuition.

## Output

Unless the user asks for another format, provide:

1. release scope
2. readiness evidence
3. known risks and blockers
4. deployment and rollback concerns
5. go/no-go recommendation

## Report Back

Briefly tell the user:

- how ready the release appears
- which evidence supports that judgment
- what unresolved risks remain
- what still needs to happen before sign-off
