---
name: api-testing
description: Write API tests that match the repo's conventions for REST or GraphQL validation, auth handling, contract testing, and dependency strategy. Use when the user asks for endpoint tests, API integration tests, contract tests, Pact, Spring Cloud Contract, GraphQL coverage, or request/response validation.
---

# API Testing

Write API tests that validate real behavior and match the repo's service-testing style.

## Inputs

You need the endpoint, schema, query, mutation, contract, or integration behavior to cover. If the intended level is unclear, ask whether this should be a unit, contract, integration, or end-to-end API test.

## Workflow

### 1. Discover the local API test style

Inspect nearby API tests, shared helpers, test hosts, config, auth setup, fixtures, and service boundaries first. Ask the user only if the intended test level or contract expectations are still unclear.

Capture:

- REST, GraphQL, or mixed suite structure
- request-building helpers
- auth and identity setup
- assertion style
- schema or contract validation approach
- whether tests use real services, test containers, stubs, or mocks

Follow the repo's preferred API test level when it has one.

### 2. Validate the right things

Cover behavior that matters externally:

- status codes or GraphQL error shape
- response body and schema
- required headers and content types
- auth and permission behavior
- validation failures
- important side effects and persistence outcomes

Prefer contract and schema confidence over internal implementation assertions.

### 3. Respect dependency strategy

Match the team's existing choice between:

- integration tests against real services or local test instances
- contract tests such as `Pact` or `Spring Cloud Contract`
- mocked downstream dependencies

Do not switch test levels casually. If the right level is ambiguous, ask and explain the tradeoff.

### 4. Handle auth and data setup carefully

- Reuse existing token, session, or client setup helpers.
- Follow local fixture and test data patterns.
- Avoid embedding secrets or production credentials.
- Keep test data scoped to the scenario under test.

For GraphQL, mirror the repo's query structure, variable setup, and error assertions.

### 5. Keep suites readable

Structure new tests like neighboring files:

- group by resource, route, or resolver if that is the local pattern
- keep one behavioral concern per test
- name tests after the external contract they validate

Do not mix unrelated endpoints or behaviors in one test file without prior art.

### 6. Validate safely

Run only the focused API test command needed for the changed area. Do not run the whole application. If external services must be started, ask the user to do that and report back.

## Report Back

Briefly tell the user:

- which API testing style you followed
- whether the coverage is mocked, contract-based, or against real services
- which schema, auth, or behavior checks you added
- any environment setup they still need to run
