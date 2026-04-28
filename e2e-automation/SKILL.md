---
name: e2e-automation
description: Write end-to-end tests that match the repository's browser automation patterns, including page objects, locator strategy, waits, retries, and spec layout. Use when the user asks for Playwright, Cypress, Selenium, browser E2E, UI automation, flaky spec fixes, or new end-to-end coverage.
---

# E2E Automation

Write browser automation that looks native to the repo and stays stable under change.

## Inputs

You need the user flow, feature, bug, or page behavior to automate. If the target browser matrix, environment, or auth setup is unclear, ask first.

## Workflow

### 1. Discover the local E2E style

Inspect the nearest existing specs, support files, fixtures, and config before writing anything.

Explore the existing suite before asking questions. Inspect framework config, page objects, auth flows, fixtures, and locator patterns first. Ask the user only when environment setup, browser matrix, or intended coverage is still unclear.

Capture:

- tool and runner (`Playwright`, `Cypress`, `Selenium`, etc.)
- file layout and naming
- page object or helper patterns
- locator preferences
- auth and test setup flow
- waits, retries, and flake-handling conventions

If the repo has no usable prior art, stop and ask instead of inventing a framework style.

### 2. Follow stable locator rules

- Prefer test IDs when the repo supports them.
- Use accessible roles or labels before brittle CSS or DOM-order selectors.
- Avoid selectors tied to styling, layout, or transient text unless that is the explicit behavior under test.
- Match the repo's page object pattern when one exists.

If a page object layer exists, extend it instead of bypassing it in a new spec.

### 3. Use resilient timing strategies

- Prefer condition-based waiting over sleeps.
- Reuse the framework's built-in auto-wait behavior where applicable.
- Match the repo's retry policy instead of adding ad hoc loops.
- Treat flake fixes as a signal to inspect root cause, not to stack more waiting.

Do not add arbitrary timeouts just to make a spec pass.

### 4. Structure the spec like nearby tests

Mirror local patterns for:

- describe or test grouping
- fixture setup and teardown
- page object construction
- data setup
- assertion style
- cleanup responsibilities

When multiple styles exist, follow the one nearest the feature under test.

### 5. Keep the coverage intentional

Automate the smallest high-value flow set:

- critical user journeys
- risky regressions
- cross-page flows that unit or integration tests cannot cover well

Do not overload one spec with many unrelated assertions.

### 6. Validate carefully

Run only the focused E2E spec or project slice needed for the change. Do not run the whole application. If runtime setup or app startup is required, ask the user to run it and report back.

## Report Back

Briefly tell the user:

- which local E2E patterns you followed
- how you handled locators, waits, and retries
- which focused specs you added or changed
- any runtime steps they still need to execute
