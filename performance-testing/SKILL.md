---
name: performance-testing
description: Write performance test plans and scripts that match the repository's tooling, workload models, SLOs, and threshold assertions. Use when the user asks for k6, Locust, JMeter, load testing, stress testing, baseline thresholds, ramp profiles, or performance regression coverage.
---

# Performance Testing

Write performance tests that reflect realistic load and assert against meaningful thresholds.

## Inputs

You need the target system, critical user journey or API, environment, and performance question to answer. If the SLOs, traffic shape, or baseline expectations are unclear, ask first.

First inspect the repository for existing performance scripts, thresholds, SLO references, dashboards, and environment guidance. Ask the user only for the performance question to answer, safe execution constraints, or targets that are not documented locally.

## Workflow

### 1. Discover the local performance approach

Inspect existing performance scripts, dashboards, docs, and CI hooks before writing anything.

Capture:

- tool choice (`k6`, `Locust`, `JMeter`, etc.)
- script layout and shared helpers
- existing thresholds and pass criteria
- environment assumptions
- data seeding and auth setup
- workload patterns already used by the team

If the repo has no usable prior art, ask rather than inventing arbitrary thresholds.

### 2. Model realistic traffic

Build the workload around real usage risks:

- steady-state load
- ramp-up and ramp-down
- bursts and spikes
- concurrency-sensitive behavior
- long-running soak behavior when relevant

Do not use a default load profile unless it matches the stated goal.

### 3. Assert on meaningful outcomes

Prefer thresholds tied to user or system outcomes:

- latency percentiles
- error rate
- throughput
- saturation indicators the team already tracks
- success criteria aligned to stated SLOs

Avoid pass criteria that only assert the script completed.

### 4. Keep data and environments controlled

- Reuse the repo's auth and seed-data patterns.
- Avoid polluting shared environments with unrealistic load unless the user explicitly wants that.
- Call out when a chosen environment makes results less trustworthy.

If the team has baseline thresholds, use them instead of inventing new ones.

### 5. Right-size the script

Choose the lightest script that answers the question:

- smoke baseline for quick regression checks
- targeted load profile for a risky endpoint or workflow
- broader scenario mix for release or capacity validation

Do not build a huge suite when one focused scenario would answer the question.

### 6. Validate carefully

Run only the focused performance script needed for the change, and only when safe for the target environment. If execution could disrupt shared systems, stop and ask the user to run it instead.

## Report Back

Briefly tell the user:

- which tool and local patterns you followed
- what workload profile and thresholds you used
- what the script is intended to prove
- what environment or execution steps still need user confirmation
