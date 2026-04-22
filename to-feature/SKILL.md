---
name: to-feature
description: Turn the current conversation context (typically from spec-it) into a PRD and submit it as an Azure DevOps Feature work item. Use when user wants to create a Feature in ADO from the current shared understanding, or mentions "to-feature".
---

# To Feature

Takes the current conversation context — typically the shared understanding produced by `spec-it` — and creates an Azure DevOps **Feature** work item with the PRD as its description.

Do NOT re-interview the user. Synthesize what you already know.

This is step **2** of the per-feature loop (prerequisite: `ado-context` has been run once to create `.ado-skills.json`):

1. `spec-it` — reach shared understanding
2. **`to-feature`** — create the Feature with the PRD  ← you are here
3. `to-pbis` — vertically slice the Feature into PBIs using tracer bullets

## Detect ADO Context

Run the `ado-context` skill first. It loads `.ado-skills.json` (or runs a one-time setup to create it) and resolves today's iteration, exporting:

- `ORG` / `ORG_NAME` / `PROJECT` — loaded from `.ado-skills.json`
- `PROCESS` — process template (affects story type names used downstream by `to-pbis`)
- `REPOSITORY_URL` — the canonical repo URL; append it to the PRD so the downstream agent works on the right code
- `AREA_PATH` — loaded from `.ado-skills.json`
- `ITERATION_PATH` — the iteration containing today's date

Every field below assumes those variables are already in scope, and that `AUTH` and `PROJECT_ENCODED` are set:

```bash
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
PROJECT_ENCODED=$(printf '%s' "$PROJECT" | jq -sRr @uri)
```

## Process

### 1. Explore the repo

Understand the current codebase state if you haven't already.

### 2. Sketch major modules

Identify modules to build or modify. Look for opportunities to extract **deep modules** — ones with a simple, testable interface hiding a large implementation.

Briefly check with the user:

- Do these modules match their expectations?
- Which modules do they want tests written for?

### 3. Create the ADO Feature

Write the PRD using the template below. The **entire PRD** becomes the Feature's **Description** field (`System.Description`). Do NOT ask for review first — create it.

Azure DevOps supports Markdown on large text fields (`System.Description`, `Microsoft.VSTS.Common.AcceptanceCriteria`, etc.), but the format defaults to HTML. To store the PRD as Markdown you must also set `multilineFieldsFormat/System.Description = Markdown` in the same patch.

Caveats:

- Once a field is saved as `Markdown`, it **cannot be reverted** to HTML.
- If the org hasn't enabled Markdown for work items, the call will error — fall back to HTML (see step 4).

```bash
PRD_MD=$(cat <<'EOF'
<full PRD content using the template below>
EOF
)

PAYLOAD=$(jq -n \
  --arg md "$PRD_MD" \
  --arg title "Feature title" \
  --arg area "$AREA_PATH" \
  --arg iter "$ITERATION_PATH" '[
  { op: "add", path: "/fields/System.Title",                          value: $title },
  { op: "add", path: "/fields/System.AreaPath",                       value: $area },
  { op: "add", path: "/fields/System.IterationPath",                  value: $iter },
  { op: "add", path: "/fields/System.Description",                    value: $md },
  { op: "add", path: "/multilineFieldsFormat/System.Description",     value: "Markdown" }
]')

ITEM=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/\$Feature?api-version=7.1")

FEATURE_ID=$(echo "$ITEM" | jq '.id')
echo "https://dev.azure.com/$ORG_NAME/$PROJECT/_workitems/edit/$FEATURE_ID"
```

### 4. Verify the Description

Confirm the PRD landed in `System.Description` with the right format before handing off:

```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$FEATURE_ID?api-version=7.1" \
  | jq -r '.fields["System.Description"]'
```

If the description is empty, patch it:

```bash
PATCH=$(jq -n --arg md "$PRD_MD" '[
  { op: "add", path: "/fields/System.Description",                value: $md },
  { op: "add", path: "/multilineFieldsFormat/System.Description", value: "Markdown" }
]')

curl -s -X PATCH \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PATCH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$FEATURE_ID?api-version=7.1"
```

If the initial create failed with an error about `multilineFieldsFormat` being unknown, the org hasn't enabled Markdown for work items. Retry without the `multilineFieldsFormat` op and convert the PRD to HTML first (e.g. `pandoc -f gfm -t html`).

### 5. Hand off

Print the Feature ID and URL, and remind the user the next step is `to-pbis` referencing this Feature ID.

## PRD Template

Prepend a `## Repository` section with `$REPOSITORY_URL` (so every Feature self-documents the repo agents should work in), then fill in the rest:

```
## Repository

https://dev.azure.com/<org>/<project>/_git/<repo>

## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution, from the user's perspective.

## User Stories

A long, numbered list of user stories. Format:
1. As a <actor>, I want <feature>, so that <benefit>

Cover all aspects of the feature extensively.

## Implementation Decisions

- Modules to build/modify
- Interface changes
- Architectural decisions
- Schema changes
- API contracts

Do NOT include specific file paths or code snippets — they go stale quickly.

## Testing Decisions

- What makes a good test (test external behavior, not implementation details)
- Which modules will be tested
- Prior art for tests (similar test patterns in the codebase)

## Out of Scope

What is explicitly not included in this PRD.

## Further Notes

Any additional context about the feature.
```
