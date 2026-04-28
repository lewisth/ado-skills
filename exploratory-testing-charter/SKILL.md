---
name: exploratory-testing-charter
description: Create session-based exploratory testing charters with clear mission, time box, note-taking structure, and follow-up actions. Use when the user asks for an exploratory test charter, session-based testing plan, manual discovery workflow, or help turning findings into bugs or automated tests.
---

# Exploratory Testing Charter

Structure exploratory testing so the session stays focused, evidence-rich, and easy to turn into follow-up work.

## Inputs

You need the feature, workflow, risk area, or release scope to explore. If the session goal, audience, or time budget is unclear, ask first.

Ask a small number of focused questions if the mission, time box, or target risk area is unclear. Do not let clarification overwhelm the speed and focus of the charter.

## Workflow

### 1. Define the mission

State what the session is trying to learn or de-risk:

- feature behavior under normal use
- edge cases and error handling
- risky integrations or state transitions
- usability, accessibility, or data integrity concerns

Keep the mission narrow enough to fit the session.

### 2. Time-box the session

Pick a realistic session size based on scope and risk.

Include:

- session goal
- planned duration
- target environment
- required data or accounts
- known constraints

Do not create an open-ended "test everything" charter.

### 3. Define note-taking format

Capture notes in a structured way during the session:

- actions taken
- observations
- questions
- bugs or suspicious behavior
- follow-up automation opportunities

Prefer concise evidence over narrative storytelling.

### 4. Guide the exploration

Suggest focus areas such as:

- alternate paths and edge cases
- invalid inputs and recovery behavior
- permissions and role changes
- state transitions and repeated actions
- browser, device, locale, or accessibility differences when relevant

Encourage learning-driven exploration, but keep it aligned to the session mission.

### 5. Convert findings into follow-up work

For each meaningful finding, decide whether it should become:

- a bug report
- a product question
- a new automated test
- a future exploratory charter

Do not leave important findings trapped in session notes.

## Output

Unless the user asks for another format, provide:

1. the charter mission
2. the time box and setup
3. the suggested exploration areas
4. the note-taking template
5. how to convert findings into follow-up work

## Report Back

Briefly tell the user:

- what the session is intended to uncover
- how long and how focused it should be
- how findings should be captured
- how bugs or automation follow-ups should be created
