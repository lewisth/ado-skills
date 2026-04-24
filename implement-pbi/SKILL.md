---
name: implement-pbi
description: Fetch a specific Azure DevOps PBI-like work item by ID, load its parent Feature context, implement only that item on the current checked-out branch, commit the code changes, and stop. Use when the user wants to implement a single PBI, User Story, or Requirement by work item id, or mentions "implement-pbi".
---

# Implement PBI

Implement exactly one Azure DevOps work item on the **current checked-out branch**, then stop after creating a **local commit**.

Do not create a pull request. Create a branch if the user is on the default branch.

## Inputs

You need a work item ID. If the user did not provide one, ask for it before doing anything else.

## Detect ADO Context

Run the `ado-context` skill first. It loads `.ado-skills.json` (or runs one-time setup) and resolves:

- `ORG` / `ORG_NAME` / `PROJECT`
- `PROCESS`
- `REPOSITORY_URL`
- `AREA_PATH`
- `ITERATION_PATH`

Every shell invocation is a fresh process. Set `AZURE_DEVOPS_PAT` and derived variables at the top of every script block that needs them.

**Bash:**
```bash
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
PROJECT_ENCODED=$(printf '%s' "$PROJECT" | jq -sRr @uri)
```

**PowerShell:**
```powershell
$AUTH = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_PAT"))
$PROJECT_ENCODED = [Uri]::EscapeDataString($PROJECT)
```

## Process

### 1. Fetch the work item

Fetch the requested work item with all fields and relations expanded:

**Bash:**
```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$WORK_ITEM_ID?\$expand=all&api-version=7.1"
```

**PowerShell:**
```powershell
$workItem = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$WORK_ITEM_ID?`$expand=all&api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" }
```

Validate the work item type. This skill is for story-type items only:

- `Product Backlog Item`
- `User Story`
- `Requirement`

If the item is a `Feature`, `Task`, `Bug`, or anything else, stop and tell the user.

### 2. Pull supporting Feature context

If the work item has a parent Feature, fetch it and write its description to `.agent-context/feature.md` for supporting context only.

If there is no parent Feature, continue without it.

**Bash:**
```bash
FEATURE_URL=$(printf '%s' "$WORK_ITEM_JSON" | jq -r '
  .relations[]? | select(.rel == "System.LinkTypes.Hierarchy-Reverse") | .url
' | head -n1)
```

**PowerShell:**
```powershell
$featureUrl = $workItem.relations |
  Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Reverse' } |
  Select-Object -First 1 -ExpandProperty url
```

When a parent exists, fetch it and write `.agent-context/feature.md`. Treat that file as supporting context, not additional scope.

### 3. Extract the implementation brief

Use these fields as the source of truth:

- `System.Title`
- `System.Description`
- `Microsoft.VSTS.Common.AcceptanceCriteria`

If acceptance criteria are blank, use the description and title, then call out that the work item lacks explicit acceptance criteria.

### 4. Prepare local working context

- Read `progress.txt` in the repo root if it exists.
- If `progress.txt` does not exist, create it.
- Do not include `progress.txt` in the commit.
- Keep `.agent-context/` uncommitted.

## Execution Rules

1. Implement only this work item and satisfy its acceptance criteria.
2. Make the smallest change set that solves the item cleanly.
3. Do not fix unrelated bugs or refactor outside the work required for this item.
4. If you notice unrelated problems, leave them alone unless they block this item.
5. Do not create child work items, update ADO state, or retag the work item unless the user explicitly asks.
6. Run only the focused checks needed to validate this item. Do not run the whole application.
7. Append a concise entry to `progress.txt` with today's date, the work item ID, what you completed, and any important follow-up notes.
8. Stage and commit only the code changes for this item on the current branch. Exclude `progress.txt` and `.agent-context/`.
9. Stop after the local commit. Do not push and do not open a PR.
10. If you are blocked, do not make a speculative commit. Record the blocker in `progress.txt` and tell the user exactly what is missing.

## Report Back

When finished, tell the user:

- the work item ID
- whether the item was completed or blocked
- the local commit hash if a commit was created
- any manual verification they still need to run
