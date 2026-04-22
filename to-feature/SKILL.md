---
name: to-feature
description: Turn the current conversation context (typically from build-a-spec) into a PRD and submit it as an Azure DevOps Feature work item. Use when user wants to create a Feature in ADO from the current shared understanding, or mentions "to-feature".
---

# To Feature

Takes the current conversation context — typically the shared understanding produced by `build-a-spec` — and creates an Azure DevOps **Feature** work item with the PRD as its description.

Do NOT re-interview the user. Synthesize what you already know.

This is step **2** of the workflow:

1. `build-a-spec` — reach shared understanding
2. **`to-feature`** — create the Feature with the PRD  ← you are here
3. `to-pbis` — vertically slice the Feature into PBIs using tracer bullets

## Detect ADO Context

Parse org and project from `git remote get-url origin`:

- HTTPS: `https://dev.azure.com/{org}/{project}/_git/{repo}`
- SSH: `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`
- Legacy: `https://{org}.visualstudio.com/{project}/_git/{repo}`

Detect process template (affects story type names used downstream by `to-pbis`):

```bash
az devops project show --org $ORG --project "$PROJECT" \
  --query "capabilities.processTemplate.templateName" -o tsv
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

Write the PRD using the template below and create the Feature. Do NOT ask for review first — create it.

```bash
ITEM=$(az boards work-item create \
  --org $ORG \
  --project "$PROJECT" \
  --type "Feature" \
  --title "Feature title" \
  --description "$(cat <<'EOF'
<PRD content>
EOF
)" \
  --output json)

FEATURE_ID=$(echo $ITEM | jq '.id')
echo "https://dev.azure.com/$ORG_NAME/$PROJECT/_workitems/edit/$FEATURE_ID"
```

### 4. Hand off

Print the Feature ID and URL, and remind the user the next step is `to-pbis` referencing this Feature ID.

## PRD Template

```
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
