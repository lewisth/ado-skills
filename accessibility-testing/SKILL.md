---
name: accessibility-testing
description: Write accessibility testing guidance that combines automated checks, manual verification, and WCAG traceability. Use when the user asks for axe-core, WCAG checks, a11y testing, accessibility regression coverage, screen reader validation, or accessibility-specific bug reporting.
---

# Accessibility Testing

Test accessibility with both automation and manual checks, and keep the findings distinct from general functional bugs.

## Inputs

You need the page, flow, component, or feature to assess. Default to WCAG 2.2 AA if the target standard is unclear, and inspect the repo first for accessibility tooling, shared helpers, patterns, and standards. Ask the user only if conformance level, assistive-technology support, or browser and device expectations are still unclear.

## Workflow

### 1. Discover the local a11y pattern

Inspect nearby tests, shared accessibility helpers, and issue templates first.

Capture:

- automated tooling already used (`axe-core`, Playwright integrations, Cypress plugins, etc.)
- where accessibility checks live
- naming and assertion style
- manual QA expectations already documented by the team
- bug-reporting workflow for accessibility findings

Follow any repo-specific accessibility checklist or audit flow.

### 2. Combine automated and manual coverage

Use automation for fast repeatable checks, then add the manual checks it cannot prove.

Automation is good for:

- obvious semantic issues
- missing labels and names
- ARIA misuse
- contrast checks supported by the tool

Manual checks are still needed for:

- keyboard-only flow
- focus order and focus visibility
- screen reader behavior
- meaningful content and instructions
- error recovery and status messaging

Do not present automation as complete accessibility validation.

### 3. Map findings to WCAG

Tie checks or failures to the relevant WCAG criterion and user impact when possible.

Prefer clear statements of:

- what failed
- who it affects
- why it matters
- which criterion it maps to when known

### 4. Match the repo's automation style

For automated checks:

- reuse existing test helpers and fixture setup
- colocate checks where the repo expects them
- keep assertions focused and readable
- avoid noisy scans that make failures hard to triage

If a flow already has E2E coverage, extend it with local accessibility checks instead of duplicating the full journey.

### 5. Keep accessibility bugs distinct

Separate accessibility defects from general functional defects if the team does so.

Include:

- reproduction steps
- affected users or assistive technology context
- WCAG mapping when known
- severity and user impact

### 6. Validate safely

Run only the focused accessibility checks needed for the changed area. Do not run the whole application. If manual browser or assistive-technology verification is required, ask the user to perform it and report back.

## Report Back

Briefly tell the user:

- which automation and manual checks you used
- any WCAG mapping included
- how accessibility findings should be filed or separated
- what manual validation they still need to perform
