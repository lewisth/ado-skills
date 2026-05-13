---
name: qa-report
description: Guided QA bug/defect report or feature misalignment filed as a GitHub issue with detailed repro steps, evidence, and codebase context. Use when user says "report a bug", "qa report", "file a bug", "feature misalignment", or "raise a defect".
---

# QA Report

Interview a QA engineer to capture a bug or feature misalignment, enrich it with codebase exploration and environment data, then file a GitHub issue ready for an agent or human to pick up.

Ask questions **one at a time**. Do not batch. Wait for each answer before proceeding.

## 1. Classify

Ask: **"Is this a bug (something is broken) or a feature misalignment (built behaviour doesn't match the spec/expectation)?"**

This determines the interview branch — see [INTERVIEW.md](INTERVIEW.md).

## 2. Interview

Walk through the relevant question tree in [INTERVIEW.md](INTERVIEW.md). Rules:

- One question at a time, wait for the answer.
- If the reporter's answer is vague, probe deeper — don't move on until you have something actionable.
- At the evidence step, prompt: *"Drag and drop any screenshots, videos, or files into the chat now. Type 'none' if you have nothing to attach."*
- Record every answer; you'll need them all for the issue.

## 3. Auto-collect environment info

After the interview, silently gather what's available:

- OS and version (`uname -a` or equivalent)
- Current git branch and short SHA (`git rev-parse --short HEAD`, `git branch --show-current`)
- Runtime versions relevant to the project (e.g. `dotnet --version`, `node -v`)
- Any `.env` or config that reveals the target environment (do NOT include secrets)

Include this in the issue under **Environment**.

## 4. Codebase exploration

Use subagents (explore type) to find:

- Code paths related to the reported behaviour
- Recent commits touching those paths (`git log --oneline -10 -- <paths>`)
- Existing tests covering the area (or lack thereof)
- Similar patterns elsewhere that work correctly

Summarise findings for the issue — describe modules and behaviours, not file paths or line numbers, so the issue stays durable.

## 5. Severity classification

Based on the interview answers, recommend a severity and priority:

| Label | Meaning |
|---|---|
| `severity:critical` | System down, data loss, security hole |
| `severity:major` | Core workflow broken, no workaround |
| `severity:minor` | Broken but workaround exists |
| `severity:cosmetic` | Visual or UX polish |
| `priority:high` | Fix before next release |
| `priority:medium` | Fix soon, not blocking |
| `priority:low` | Backlog |

State your recommendation and ask the reporter to confirm or adjust.

## 6. Preview and confirm

Render the full issue using the template in [ISSUE-TEMPLATE.md](ISSUE-TEMPLATE.md). Present it to the reporter and ask: **"Does this accurately capture the problem? Any corrections before I file it?"**

Make any requested edits before proceeding.

## 7. File the issue

Create the issue with `gh issue create`. Apply labels: the category (`bug` or `feature-misalignment`), the confirmed severity, and the confirmed priority.

Print the issue URL when done.
