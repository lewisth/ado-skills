---
name: flaky-test-triage
description: Triage unstable test failures by gathering recent evidence, classifying flaky versus real versus environmental issues, inspecting code history, and proposing the right response. Use when the user asks about flaky tests, CI flakes, quarantining tests, recurring test failures, unstable pipelines, or failure triage workflows.
---

# Flaky Test Triage

Treat repeated test failures as an investigation workflow, not just a rerun problem.

## Inputs

You need the failing test, job, pipeline, or error evidence to investigate. If the relevant CI system, failure history, or quarantine policy is unclear, ask first.

Prefer evidence gathering over early questioning. Inspect failure logs, test history, recent changes, nearby tests, and environment signals before asking the user for more context. Ask only when access to CI history, quarantine policy, or environmental details is missing.

## Workflow

### 1. Gather failure evidence

Collect the most recent useful signals before deciding anything:

- failing test names
- failure messages and stack traces
- recent runs and pass-fail history
- branch, commit, and environment details
- whether reruns pass without code changes

Do not classify a failure from one isolated log line when broader run history is available.

If the repository or CI artifacts can answer a question, inspect them first. Do not ask the user to explain likely causes before you have gathered the available failure evidence yourself.

### 2. Classify the failure

Sort the issue into one of these buckets:

- real product or test regression
- flaky test with nondeterministic behavior
- environmental or infrastructure failure
- insufficient evidence yet

State why the classification fits. If confidence is low, say so.

### 3. Inspect change history

Check what changed around the failure:

- recent code changes near the test or system under test
- recent test edits
- ownership and `git blame` clues
- timing with dependency, config, or environment changes

Prefer evidence from history over guesses about flakiness.

### 4. Look for common flake patterns

Check for known causes such as:

- race conditions and timing assumptions
- shared mutable state
- order dependence
- clock or timezone sensitivity
- network, browser, or external service instability
- data collisions and cleanup leaks
- assertions on eventually consistent behavior

If the repo already has a flake taxonomy or retry policy, follow it.

### 5. Choose the response deliberately

Pick the smallest honest next action:

- fix the test
- fix the production bug
- improve setup or environment reliability
- quarantine or skip temporarily if policy allows
- open a follow-up issue when evidence is incomplete

Do not quarantine a real regression just to make CI green.

### 6. Record the outcome clearly

When reporting or updating tracking systems, include:

- classification
- supporting evidence
- suspected root cause
- chosen action
- whether more data is needed

If the test is quarantined, say why, for how long if known, and what would be required to restore it.

## Output

Unless the user asks for another format, provide:

1. the failure classification
2. the key evidence
3. the likely root cause
4. the recommended action
5. any follow-up needed

## Report Back

Briefly tell the user:

- whether the issue looks flaky, real, environmental, or still unclear
- what history or blame signals you used
- whether you recommend a fix, quarantine, or environment change
- what additional evidence would improve confidence
