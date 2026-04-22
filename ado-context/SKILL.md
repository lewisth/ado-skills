---
name: ado-context
description: Resolve Azure DevOps context (org, project, process template, repository URL, area path, iteration path) for other ADO skills. Runs a one-time setup per repo that persists static values to `.ado-skills.json`, then loads them on each invocation and calculates the current iteration from today's date. Use as a prerequisite step whenever creating or updating ADO work items, or when the user mentions "ado-context".
---

# ADO Context

Resolve the shared Azure DevOps context used by every other ADO skill:

- `ORG` — organisation URL (e.g. `https://dev.azure.com/contoso`)
- `ORG_NAME` — short org name (e.g. `contoso`)
- `PROJECT` — project name
- `PROCESS` — process template name (Agile / Scrum / CMMI)
- `REPOSITORY_URL` — canonical URL of the repo the agent should work in
- `AREA_PATH` — where work items are filed
- `ITERATION_PATH` — which sprint/iteration they land in

All but `ITERATION_PATH` are **static per repo** — they don't move. Resolve them once in a setup step that writes `.ado-skills.json`, then just read the file on every subsequent invocation. The iteration path is **always computed fresh** from today's date.

Run this **before** any skill that creates or updates work items (`to-feature`, `to-pbis`, …). Export the values so downstream steps can reference them without re-resolving.

## Shell environment

These skills assume a **Bash-compatible shell** (Linux, macOS, Git Bash, WSL). If the workspace shell is **PowerShell**, use the PowerShell equivalents shown alongside each Bash block. Every shell invocation in an agent context is a **fresh process** — environment variables do not persist between calls. Set all required variables (including `$env:AZURE_DEVOPS_PAT`) at the top of every script block that needs them.

## Authentication

All REST calls use a Personal Access Token (PAT). The PAT must be set in the environment as `AZURE_DEVOPS_PAT` with at least **Read** scope on Project and Work Items (and **Read & Write** for skills that create items).

Build the auth header once at the start of every skill that calls this:

**Bash:**
```bash
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
# Usage: -H "Authorization: Basic $AUTH"
```

**PowerShell:**
```powershell
$AUTH = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_PAT"))
# Usage: -Headers @{ Authorization = "Basic $AUTH" }
```

If `AZURE_DEVOPS_PAT` is unset or empty, stop and tell the user to set it before continuing. In agent contexts, set it at the top of every script block — it will not carry over from a previous invocation.

## Config file

`.ado-skills.json` lives at the repo root and is committed so the whole team shares the same defaults. All fields are **required** — the skill will fail if any are missing:

```json
{
  "organizationUrl": "https://dev.azure.com/contoso",
  "project": "My Project",
  "process": "Scrum",
  "repositoryUrl": "https://dev.azure.com/contoso/My Project/_git/my-repo",
  "areaPath": "My Project\\Squad A",
  "team": "Engineering"
}
```

Backslashes must be escaped in JSON. `iterationPath` is **not** stored — it's calculated on every run. `team` is **required** — do not leave it out or default it; ask the user for the correct team name if unknown.

## Process

### 0. Set up auth

**Bash:**
```bash
if [ -z "$AZURE_DEVOPS_PAT" ]; then
  echo "AZURE_DEVOPS_PAT is not set. Please create a PAT in Azure DevOps and set it."
  exit 1
fi
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
```

**PowerShell:**
```powershell
if (-not $env:AZURE_DEVOPS_PAT) {
  Write-Error "AZURE_DEVOPS_PAT is not set. Please create a PAT in Azure DevOps and set it."
  exit 1
}
$AUTH = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_PAT"))
```

### 1. Load `.ado-skills.json` if it exists

**Bash:**
```bash
CONFIG_FILE=".ado-skills.json"

if [ -f "$CONFIG_FILE" ]; then
  export ORG=$(jq -r '.organizationUrl // empty'      "$CONFIG_FILE")
  export PROJECT=$(jq -r '.project // empty'          "$CONFIG_FILE")
  export PROCESS=$(jq -r '.process // empty'          "$CONFIG_FILE")
  export REPOSITORY_URL=$(jq -r '.repositoryUrl // empty' "$CONFIG_FILE")
  export AREA_PATH=$(jq -r '.areaPath // empty'       "$CONFIG_FILE")
  export TEAM=$(jq -r '.team // empty'                "$CONFIG_FILE")
  export ORG_NAME=$(basename "$ORG")
fi
```

**PowerShell:**
```powershell
$CONFIG_FILE = ".ado-skills.json"

if (Test-Path $CONFIG_FILE) {
  $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
  $ORG            = $config.organizationUrl
  $PROJECT        = $config.project
  $PROCESS        = $config.process
  $REPOSITORY_URL = $config.repositoryUrl
  $AREA_PATH      = $config.areaPath
  $TEAM           = $config.team
  $ORG_NAME       = $ORG.TrimEnd('/').Split('/')[-1]
}
```

After loading, **validate that every required field is non-empty**, including `team`. If any field is missing, stop and run step 2 to resolve the missing values — even if all other fields are present. Do not silently default `team` to `{project} Team`; ask the user for the correct value.

### 2. First-time setup (only when config is missing or incomplete)

#### 2a. Detect org, project, and repository URL from `git remote`

**Bash:**
```bash
REMOTE=$(git remote get-url origin)
```

**PowerShell:**
```powershell
$REMOTE = git remote get-url origin
```

Match one of these shapes and extract the parts:

- HTTPS: `https://dev.azure.com/{org}/{project}/_git/{repo}`
- SSH: `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`
- Legacy: `https://{org}.visualstudio.com/{project}/_git/{repo}`

Normalise the repository URL to the canonical HTTPS form so agents always check out from the same place, regardless of who originally cloned via SSH:

**Bash:**
```bash
ORG_NAME="contoso"
PROJECT="My Project"
REPO="my-repo"

ORG="https://dev.azure.com/$ORG_NAME"
REPOSITORY_URL="$ORG/$PROJECT/_git/$REPO"
```

**PowerShell:**
```powershell
$ORG_NAME = "contoso"
$PROJECT = "My Project"
$REPO = "my-repo"

$ORG = "https://dev.azure.com/$ORG_NAME"
$REPOSITORY_URL = "$ORG/$PROJECT/_git/$REPO"
```

Confirm the derived values with the user before persisting — especially if the remote is a fork or mirror.

#### 2b. Detect the process template

URL-encode the project name (spaces become `%20`) and call the Projects API:

**Bash:**
```bash
PROJECT_ENCODED=$(printf '%s' "$PROJECT" | jq -sRr @uri)

PROCESS=$(curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/_apis/projects/$PROJECT_ENCODED?includeCapabilities=true&api-version=7.1" \
  | jq -r '.capabilities.processTemplate.templateName')
```

**PowerShell:**
```powershell
$PROJECT_ENCODED = [Uri]::EscapeDataString($PROJECT)

$resp = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$ORG_NAME/_apis/projects/$PROJECT_ENCODED?includeCapabilities=true&api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" }
$PROCESS = $resp.capabilities.processTemplate.templateName
```

This picks the right story type downstream (User Story / Product Backlog Item / Requirement).

#### 2c. Pick an area path

Fetch the area tree and flatten it to a list of paths for the user to choose from:

**Bash:**
```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/classificationnodes/areas?\$depth=10&api-version=7.1" \
  | jq -r 'recurse(.children[]?) | .path'
```

**PowerShell:**
```powershell
$areas = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/classificationnodes/areas?`$depth=10&api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" }

function Get-AreaPaths($node) {
  $node.path
  if ($node.children) { $node.children | ForEach-Object { Get-AreaPaths $_ } }
}
Get-AreaPaths $areas
```

Present the list and prompt the user to pick one. If the user has no preference, fall back to the project root (`$PROJECT`) — that's ADO's own default.

#### 2d. Determine the team name

The iteration endpoint is team-scoped. **Ask the user for the exact team name** — do not guess or default. The team name must exactly match an existing team in the project:

**Bash:**
```bash
# Ask the user: "What is the name of your ADO team?"
TEAM="Engineering"   # example — use the value the user provides
```

**PowerShell:**
```powershell
# Ask the user: "What is the name of your ADO team?"
$TEAM = "Engineering"   # example — use the value the user provides
```

#### 2e. Write `.ado-skills.json`

**Bash:**
```bash
jq -n \
  --arg org     "$ORG" \
  --arg proj    "$PROJECT" \
  --arg proc    "$PROCESS" \
  --arg repo    "$REPOSITORY_URL" \
  --arg area    "$AREA_PATH" \
  --arg team    "$TEAM" \
  '{
    organizationUrl: $org,
    project:         $proj,
    process:         $proc,
    repositoryUrl:   $repo,
    areaPath:        $area,
    team:            $team
  }' > "$CONFIG_FILE"
```

**PowerShell:**
```powershell
@{
  organizationUrl = $ORG
  project         = $PROJECT
  process         = $PROCESS
  repositoryUrl   = $REPOSITORY_URL
  areaPath        = $AREA_PATH
  team            = $TEAM
} | ConvertTo-Json | Set-Content $CONFIG_FILE
```

Tell the user to commit `.ado-skills.json` so teammates and CI agents share the same context. Export the variables so the rest of this run can use them.

### 3. Resolve iteration path (from today's date)

Fetch the current iteration for the team. ADO determines which iteration contains today — no date math needed:

**Bash:**
```bash
TEAM_ENCODED=$(printf '%s' "$TEAM" | jq -sRr @uri)

ITERATION_PATH=$(curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/$TEAM_ENCODED/_apis/work/teamsettings/iterations?\$timeframe=current&api-version=7.1" \
  | jq -r '.value[0].path // empty')
```

**PowerShell:**
```powershell
$TEAM_ENCODED = [Uri]::EscapeDataString($TEAM)

$iterResp = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/$TEAM_ENCODED/_apis/work/teamsettings/iterations?`$timeframe=current&api-version=7.1" `
  -Headers @{ Authorization = "Basic $AUTH" }
$ITERATION_PATH = $iterResp.value[0].path
```

If nothing comes back — no sprint configured for today, or a gap between sprints — fall back to the project default iteration and warn the user:

**Bash:**
```bash
if [ -z "$ITERATION_PATH" ]; then
  echo "No current iteration found — falling back to project default."
  ITERATION_PATH="$PROJECT"
fi

export ITERATION_PATH
```

**PowerShell:**
```powershell
if (-not $ITERATION_PATH) {
  Write-Warning "No current iteration found — falling back to project default."
  $ITERATION_PATH = $PROJECT
}
```

### 4. Report

Print the resolved context so the user can sanity-check before work items get created:

```
ORG:            https://dev.azure.com/contoso
PROJECT:        My Project
PROCESS:        Scrum
REPOSITORY_URL: https://dev.azure.com/contoso/My Project/_git/my-repo
AREA_PATH:      My Project\Squad A
ITERATION_PATH: My Project\Sprint 42
TEAM:           Engineering
```
