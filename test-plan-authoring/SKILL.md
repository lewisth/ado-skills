---
name: test-plan-authoring
description: Generate structured test plans from requirements, user stories, bug reports, or pull requests with clear traceability and risk-based prioritization. Use when the user asks for a test plan, QA plan, UAT checklist, regression scope, release validation, or wants requirements mapped to test coverage.
---

# Test Plan Authoring

Turn requirements into a test plan that is traceable, prioritized, and ready to execute.

## Inputs

You need at least one source of truth:

- requirements or acceptance criteria
- user stories or work items
- a pull request or diff
- a bug report or incident description

If the intended audience is unclear, ask whether the plan is for QA, UAT, release validation, regression, or developer self-test.

If important context is missing, first check whether the answer can be recovered from the codebase, existing tests, CI, linked work items, or repository docs. Ask the user only for information the repo cannot reveal, such as intended audience, execution context, risk tolerance, or environment constraints.

## Workflow

### 1. Gather source material

Read the authoritative inputs first. Prefer explicit requirements over inferred behavior.

Before asking clarifying questions, inspect the relevant code, existing coverage, integration points, and nearby documentation when they are available. Use user questions to resolve product intent, ambiguous acceptance criteria, or business priority, not facts the repository already contains.

Capture:

- scope in and out
- actors or user roles
- preconditions and dependencies
- happy paths
- edge cases and failure modes
- integrations, permissions, data states, and environment assumptions

If key behavior is ambiguous, call it out and ask instead of silently guessing.

### 2. Define plan structure

Use the repo or team's existing format if one exists. Otherwise structure each test case with:

- test case ID or short title
- linked requirement, story, PR, or defect
- priority
- severity or impact if it fails
- preconditions
- test steps
- expected results
- notes or data setup when needed

Keep the plan readable and execution-oriented. Do not turn it into vague prose.

### 3. Prioritize by risk

Rank coverage by business and technical risk, not by equal weighting.

Prioritize highest:

- user-facing critical flows
- money, security, permissions, or data integrity risks
- recently changed or fragile areas
- integrations and migration paths
- behavior with poor existing coverage

Lower priority:

- cosmetic checks with limited impact
- scenarios already strongly covered elsewhere

Explain the risk logic briefly when it affects scope.

### 4. Maintain traceability

Map every test case back to its source:

- requirement or acceptance criterion
- story or ticket ID
- PR or change summary
- bug or incident being prevented

Also note any requirements that do not yet have a planned test case, and any planned tests that are based on inferred risk rather than explicit requirements.

### 5. Right-size the plan

Choose the smallest useful plan for the request:

- concise smoke plan for small PRs
- focused regression plan for bug fixes
- fuller end-to-end plan for features or releases

Do not generate a bloated matrix when a targeted plan would be clearer.

### 6. Report assumptions and gaps

Call out:

- missing requirements
- unclear expected behavior
- unavailable environments or test data
- cases that need user confirmation

Do not hide uncertainty inside the plan.

## Output

Unless the user specifies another format, produce:

1. a short scope statement
2. a prioritized list of test cases
3. a traceability section or inline trace links
4. open questions or gaps

## Report Back

Briefly tell the user:

- what source material the plan was based on
- how you prioritized risk
- any requirements without matching coverage
- what still needs clarification before execution
