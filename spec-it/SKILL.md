---
name: spec-it
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "spec it", "spec it out", or "build a spec".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

If codebase exploration reveals a bug or refactor candidate that could affect the design, stop and ask the user whether to include it in the spec before folding it in.

Do not silently expand scope. Present the finding briefly, explain why it matters to the spec, and ask whether to:
- include it in the spec
- note it as a separate follow-up
- ignore it for now
