---
name: report-bug
description: Interview a QA engineer step-by-step to gather bug details, then raise a Bug work item in Azure DevOps with structured repro steps. Use when user wants to report a bug, file a bug, log a defect, or mentions "report-bug".
---

# Report Bug

Interview the user step-by-step to build a structured bug report, then create an Azure DevOps **Bug** work item.

## Detect ADO Context

Run the `ado-context` skill first. It loads `.ado-skills.json` (or runs a one-time setup to create it) and resolves today's iteration, exporting:

- `ORG` / `ORG_NAME` / `PROJECT` — loaded from `.ado-skills.json`
- `PROCESS` — process template
- `REPOSITORY_URL` — the canonical repo URL
- `AREA_PATH` — loaded from `.ado-skills.json`
- `ITERATION_PATH` — the iteration containing today's date

Every field below assumes those variables are already in scope, and that `AUTH` and `PROJECT_ENCODED` are set.

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

> **Agent context note:** Each shell invocation is a fresh process. Set `AZURE_DEVOPS_PAT` (and all other variables) at the top of every script block — they do not persist between calls.

## Process

### 1. Interview the QA engineer

Ask the following questions **one at a time**. If the user has already provided information up-front, acknowledge it and skip to the next unanswered question. For each question, provide a suggested answer if you can infer one from context.

#### Required

1. **Summary** — one-line description of the bug (becomes the work item title)
2. **Steps to reproduce** — numbered steps another person can follow to trigger the bug
3. **Expected behaviour** — what should happen
4. **Actual behaviour** — what actually happens

#### Optional (ask, but accept "skip")

5. **Severity** — how bad is it? Offer ADO's scale with guidance:
   - `1 - Critical` — system down, data loss, no workaround
   - `2 - High` — major feature broken, workaround exists
   - `3 - Medium` — feature partially working, moderate impact
   - `4 - Low` — cosmetic, minor inconvenience
   Default to `3 - Medium` if the user skips.
6. **Priority** — how urgently should it be fixed? (`1` = must fix now, `2` = should fix soon, `3` = can wait). Default to `2` if the user skips.
7. **Environment** — browser, OS, device, screen size, or any relevant environment details
8. **Related work item** — an existing work item ID to link to (parent Feature or PBI)

### 2. Draft the bug report

Present the structured report back to the user for review before creating anything:

```
Title: <summary>
Severity: <severity>
Priority: <priority>

## Steps to Reproduce
1. …
2. …

## Expected Behaviour
…

## Actual Behaviour
…

## Environment
… (or "Not specified")
```

Ask: "Does this look right, or would you like to change anything?"

Iterate until the user approves.

### 3. Create the ADO Bug

Build the `ReproSteps` field content combining all gathered details, then create the work item.

ADO Bugs use `Microsoft.VSTS.TCM.ReproSteps` as the primary rich text field rather than `System.Description`.

**Bash:**
```bash
REPRO_STEPS=$(cat <<EOF
## Steps to Reproduce

1. Step one
2. Step two

## Expected Behaviour

What should happen.

## Actual Behaviour

What actually happens.

## Environment

Browser, OS, device, etc. (or "Not specified")
EOF
)

PAYLOAD=$(jq -n \
  --arg title    "Bug title" \
  --arg area     "$AREA_PATH" \
  --arg iter     "$ITERATION_PATH" \
  --arg severity "3 - Medium" \
  --arg priority "2" \
  --arg repro    "$REPRO_STEPS" \
  '[
    { op: "add", path: "/fields/System.Title",                                  value: $title },
    { op: "add", path: "/fields/System.AreaPath",                               value: $area },
    { op: "add", path: "/fields/System.IterationPath",                          value: $iter },
    { op: "add", path: "/fields/Microsoft.VSTS.Common.Severity",                value: $severity },
    { op: "add", path: "/fields/Microsoft.VSTS.Common.Priority",                value: ($priority | tonumber) },
    { op: "add", path: "/fields/Microsoft.VSTS.TCM.ReproSteps",                 value: $repro },
    { op: "add", path: "/multilineFieldsFormat/Microsoft.VSTS.TCM.ReproSteps",  value: "Markdown" }
  ]')

BUG=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/\$Bug?api-version=7.1")

BUG_ID=$(echo "$BUG" | jq '.id')
```

**PowerShell:**
```powershell
$REPRO_STEPS = @"
## Steps to Reproduce

1. Step one
2. Step two

## Expected Behaviour

What should happen.

## Actual Behaviour

What actually happens.

## Environment

Browser, OS, device, etc. (or "Not specified")
"@

$PAYLOAD = @(
  @{ op = "add"; path = "/fields/System.Title";                                 value = "Bug title" }
  @{ op = "add"; path = "/fields/System.AreaPath";                              value = $AREA_PATH }
  @{ op = "add"; path = "/fields/System.IterationPath";                         value = $ITERATION_PATH }
  @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Severity";               value = "3 - Medium" }
  @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority";               value = 2 }
  @{ op = "add"; path = "/fields/Microsoft.VSTS.TCM.ReproSteps";                value = $REPRO_STEPS }
  @{ op = "add"; path = "/multilineFieldsFormat/Microsoft.VSTS.TCM.ReproSteps"; value = "Markdown" }
) | ConvertTo-Json

$BUG = Invoke-RestMethod `
  -Method Post `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/`$Bug?api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" } `
  -ContentType "application/json-patch+json" `
  -Body $PAYLOAD

$BUG_ID = $BUG.id
```

### 4. Link to a related work item (optional)

If the user provided a related work item ID, link the Bug to it. Use `System.LinkTypes.Related` for a general relationship:

**Bash:**
```bash
LINK_PAYLOAD=$(jq -n \
  --arg related_url "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$RELATED_ID" \
  '[{
    op: "add",
    path: "/relations/-",
    value: {
      rel: "System.LinkTypes.Related",
      url: $related_url,
      attributes: { comment: "" }
    }
  }]')

curl -s -X PATCH \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$LINK_PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$BUG_ID?api-version=7.1"
```

**PowerShell:**
```powershell
$LINK_PAYLOAD = @(
  @{
    op    = "add"
    path  = "/relations/-"
    value = @{
      rel        = "System.LinkTypes.Related"
      url        = "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$RELATED_ID"
      attributes = @{ comment = "" }
    }
  }
) | ConvertTo-Json -Depth 5

Invoke-RestMethod `
  -Method Patch `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$BUG_ID?api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" } `
  -ContentType "application/json-patch+json" `
  -Body $LINK_PAYLOAD
```

### 5. Verify and report

Confirm the Bug was created successfully by fetching it back:

**Bash:**
```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$BUG_ID?api-version=7.1" \
  | jq '{id: .id, title: .fields["System.Title"], severity: .fields["Microsoft.VSTS.Common.Severity"], state: .fields["System.State"]}'
```

**PowerShell:**
```powershell
$check = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$BUG_ID?api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" }
Write-Host "ID: $($check.id) | Title: $($check.fields.'System.Title') | Severity: $($check.fields.'Microsoft.VSTS.Common.Severity')"
```

Print the Bug ID and URL:

```
Bug #<id>: https://dev.azure.com/<org>/<project>/_workitems/edit/<id>
```
