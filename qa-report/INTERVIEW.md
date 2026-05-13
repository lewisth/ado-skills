# Interview Question Trees

Ask questions **one at a time**. Wait for each answer. Probe if the answer is vague.

---

## Bug Branch

### 1. Summary
"Give me a one-sentence summary of what's broken."

### 2. Expected behaviour
"What did you expect to happen?"

### 3. Actual behaviour
"What actually happened instead?"

### 4. Reproduction steps
"Walk me through the exact steps to reproduce this, starting from a clean state. Be as specific as possible — include URLs, button names, menu paths, and the order you did things."

Probe until you have a numbered step-by-step list. If the reporter says "I just clicked the button", ask *which* button, *on which page*, *after doing what*.

### 5. Test data
"What data did you use? Include specific values — usernames, IDs, form inputs, payloads, query parameters. If you used seed data or a specific database state, describe that too."

### 6. Frequency and consistency
"Does this happen every time, or is it intermittent? If intermittent, roughly how often — and have you spotted any pattern (time of day, specific data, specific user)?"

### 7. Error output
"Did you see any error messages, stack traces, console errors, or log output? Paste them here if so."

### 8. Workaround
"Is there any workaround you've found?"

### 9. Evidence
"Drag and drop any screenshots, videos, screen recordings, HAR files, or other evidence into the chat now. Type 'none' if you have nothing to attach."

### 10. Impact
"Who is affected by this? How many users / how critical is the workflow that's broken?"

---

## Feature Misalignment Branch

### 1. Summary
"Give me a one-sentence summary of what doesn't match the spec or expectation."

### 2. Specification reference
"Where is the expected behaviour defined? Link to a spec, PRD, design file, ticket, or acceptance criteria. If it's an unwritten expectation, describe what it should be and why."

### 3. Current behaviour
"What does the system currently do?"

### 4. Expected behaviour
"What should it do instead, per the spec?"

### 5. Steps to observe
"Walk me through the exact steps to see the misalignment. Include URLs, inputs, and the order of actions."

Probe until you have a numbered step-by-step list.

### 6. Test data
"What data did you use to observe this? Include specific values — usernames, IDs, form inputs, payloads."

### 7. Scope of divergence
"Is this a single field/element that's wrong, or does it affect a whole workflow? Are there related screens or endpoints that also diverge?"

### 8. Evidence
"Drag and drop any screenshots comparing expected vs. actual, screen recordings, or design mockups into the chat now. Type 'none' if you have nothing to attach."

### 9. Impact
"How important is the alignment? Is this blocking a release, failing acceptance testing, or a nice-to-have correction?"
