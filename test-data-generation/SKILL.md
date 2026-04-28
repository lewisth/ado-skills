---
name: test-data-generation
description: Generate realistic, policy-safe test data for automated and manual testing, including edge cases, malformed inputs, and internationalized content. Use when the user asks for test fixtures, sample payloads, factories, seed data, boundary-value cases, fake users, or guidance on synthetic versus anonymized production data.
---

# Test Data Generation

Generate test data that is realistic enough to find bugs and safe enough to use.

## Inputs

You need the target behavior, schema, or workflow the data is meant to exercise. If the allowed data sources are unclear, ask whether the team permits only synthetic data or also allows anonymized production-derived data.

## Workflow

### 1. Understand the data shape

Inspect the code, schema, validators, and nearby tests first.

Identify:

- required and optional fields
- valid ranges and formats
- relationships between fields
- domain invariants
- locale, encoding, and timezone assumptions
- known failure modes and validation rules

Do not generate random-looking data until you understand what "valid" means in this repo.

### 2. Match the repo's existing patterns

Reuse the local approach when it exists:

- faker libraries already used in the repo
- test builders, factories, mothers, or fixtures
- seeded random helpers
- snapshot/sample payload conventions
- data setup helpers for integration tests

If the repo already has a shared data-generation pattern, extend it instead of introducing a new one.

### 3. Cover realistic and risky cases

Generate both representative happy-path data and targeted stress cases:

- boundary values
- empty and null cases where allowed
- malformed formats
- oversized inputs
- duplicate values where uniqueness matters
- international characters and non-English strings
- whitespace, punctuation, emoji, and normalization-sensitive text
- time and timezone edge cases

Prefer deliberate case selection over large volumes of arbitrary random data.

### 4. Follow data-safety rules

Treat data policy as a hard constraint.

- Prefer synthetic data by default.
- Use anonymized production-derived data only if the user or repo policy explicitly allows it.
- Never invent "fake anonymization" and present it as safe.
- Do not include real secrets, credentials, tokens, or contact details.
- Avoid realistic-but-real personal data unless the team explicitly permits that pattern.

If the repo has data classification or privacy rules, follow those over generic defaults.

### 5. Keep data intentional

Every generated value should help explain the case it supports:

- choose names that reveal purpose
- keep related fields internally consistent
- make edge-case records obviously edge-case records
- keep stable values when deterministic tests matter

Use randomness only when it improves coverage without harming reproducibility.

### 6. Validate fit

Before finishing, check that the generated data:

- satisfies the expected schema when it should be valid
- fails for the intended reason when it should be invalid
- is readable enough for future maintainers
- matches the surrounding test style and helper patterns

If reproducibility matters, prefer seeded or fixed values.

## Output

Unless the user asks for another format, provide:

1. the chosen data-generation approach
2. the concrete test data or helper pattern
3. the edge cases included
4. any safety or policy assumptions

## Report Back

Briefly tell the user:

- which local patterns or libraries you followed
- which realistic and edge-case data you included
- whether the data is synthetic or production-derived
- any policy assumptions that still need confirmation
