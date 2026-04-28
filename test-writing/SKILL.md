---
name: test-writing
description: Infer a repo's testing conventions and write new or updated tests that match them closely. Use when the user asks for unit tests, integration tests, regression tests, test fixes, coverage for a change, or help understanding local test style.
---

# Test Writing

Write tests that look native to the repo, not generic.

## Inputs

You need the behavior, module, bug, or change that should be covered. If that is unclear, ask first.

## Workflow

### 1. Discover the repo's test style

Inspect the nearest relevant tests before writing anything:

- tests beside the changed code
- similar tests for the same layer or feature
- test config files and package/project manifests
- shared test helpers, builders, fixtures, factories, or base classes

If a missing answer can be recovered from nearby code, tests, config, or helpers, inspect those first. Ask the user only when the intended behavior, risk focus, or desired test level is still unclear.

Extract and mirror the local conventions:

- framework and runner (`pytest`, `Jest`, `Vitest`, `xUnit`, `JUnit`, etc.)
- where tests live and how files are named
- test naming style
- fixture/setup pattern
- mocking/substitution libraries
- assertion style
- structure style (`AAA`, `Given-When-Then`, or the local variant)

If the repo does not provide enough prior art, stop and ask instead of inventing a style.

### 2. Follow hard rules

- Match nearby tests first; repo conventions beat generic best practice.
- Prefer behavior-focused tests over implementation-detail tests.
- Keep tests small and specific.
- Do not add comments to unit tests.
- In .NET code, use `NSubstitute` and `Shouldly`, not `Moq` or `FluentAssertions`.
- Put new tests where the repo expects them unless the user asks otherwise.

### 3. Choose the right scope

Add the smallest test set that gives confidence:

- one focused regression test for a bug
- a narrow happy-path plus important edge cases for a new behavior
- integration coverage only when unit coverage would miss the real risk

Do not pad the change with low-value tests that only restate the implementation.

### 4. Write tests in the local style

Mirror nearby tests closely:

- reuse the same naming shape
- use the same helper/builders and fixture lifecycle
- follow the same arrange/act/assert rhythm
- use the same assertion vocabulary
- keep imports and file layout consistent with neighbors

When multiple conventions exist, follow the one nearest the code you are changing.

### 5. Validate safely

Run only the focused test command needed for the changed area. Do not run the full application. If broader runtime verification is needed, ask the user to run it and report back.

If a test fails because the local pattern is unclear, inspect more nearby tests before changing production code.

## Report Back

Briefly tell the user:

- what conventions you inferred
- which tests you added or changed
- what focused verification you ran
- any manual verification they still need to do
