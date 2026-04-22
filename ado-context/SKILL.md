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

## Authentication

All REST calls use a Personal Access Token (PAT). The PAT must be set in the environment as `AZURE_DEVOPS_PAT` with at least **Read** scope on Project and Work Items (and **Read & Write** for skills that create items).

Build the auth header once at the start of every skill that calls this:

```bash
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
# Usage: -H "Authorization: Basic $AUTH"
```

If `AZURE_DEVOPS_PAT` is unset, stop and tell the user to set it before continuing.

## Config file

`.ado-skills.json` lives at the repo root and is committed so the whole team shares the same defaults:

```json
{
  "organizationUrl": "https://dev.azure.com/contoso",
  "project": "My Project",
  "process": "Scrum",
  "repositoryUrl": "https://dev.azure.com/contoso/My Project/_git/my-repo",
  "areaPath": "My Project\\Squad A",
  "team": "My Project Team"
}
```

Backslashes must be escaped in JSON. `iterationPath` is **not** stored — it's calculated on every run. `team` defaults to `{project} Team` if omitted.

## Process

### 0. Set up auth

```bash
if [ -z "$AZURE_DEVOPS_PAT" ]; then
  echo "AZURE_DEVOPS_PAT is not set. Please create a PAT in Azure DevOps and export it."
  exit 1
fi
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
```

### 1. Load `.ado-skills.json` if it exists

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

If every field above is populated, skip to [step 3](#3-resolve-iteration-path-from-todays-date). Otherwise, run the setup in step 2.

### 2. First-time setup (only when config is missing or incomplete)

#### 2a. Detect org, project, and repository URL from `git remote`

```bash
REMOTE=$(git remote get-url origin)
```

Match one of these shapes and extract the parts:

- HTTPS: `https://dev.azure.com/{org}/{project}/_git/{repo}`
- SSH: `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`
- Legacy: `https://{org}.visualstudio.com/{project}/_git/{repo}`

Normalise the repository URL to the canonical HTTPS form so agents always check out from the same place, regardless of who originally cloned via SSH:

```bash
ORG_NAME="contoso"
PROJECT="My Project"
REPO="my-repo"

ORG="https://dev.azure.com/$ORG_NAME"
REPOSITORY_URL="$ORG/$PROJECT/_git/$REPO"
```

Confirm the derived values with the user before persisting — especially if the remote is a fork or mirror.

#### 2b. Detect the process template

URL-encode the project name (spaces become `%20`) and call the Projects API:

```bash
PROJECT_ENCODED=$(printf '%s' "$PROJECT" | jq -sRr @uri)

PROCESS=$(curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/_apis/projects/$PROJECT_ENCODED?includeCapabilities=true&api-version=7.2" \
  | jq -r '.capabilities.processTemplate.templateName')
```

This picks the right story type downstream (User Story / Product Backlog Item / Requirement).

#### 2c. Pick an area path

Fetch the area tree and flatten it to a list of paths for the user to choose from:

```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/classificationnodes/areas?\$depth=10&api-version=7.2" \
  | jq -r 'recurse(.children[]?) | .path'
```

Present the list and prompt the user to pick one. If the user has no preference, fall back to the project root (`$PROJECT`) — that's ADO's own default.

#### 2d. Determine the team name

The iteration endpoint is team-scoped. The default team name is usually `{project} Team`. Confirm with the user or derive it:

```bash
TEAM="${PROJECT} Team"
```

#### 2e. Write `.ado-skills.json`

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

Tell the user to commit `.ado-skills.json` so teammates and CI agents share the same context. Export the variables so the rest of this run can use them.

### 3. Resolve iteration path (from today's date)

Fetch the current iteration for the team. ADO determines which iteration contains today — no date math needed:

```bash
TEAM_ENCODED=$(printf '%s' "$TEAM" | jq -sRr @uri)

ITERATION_PATH=$(curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/$TEAM_ENCODED/_apis/work/teamsettings/iterations?\$timeframe=current&api-version=7.2" \
  | jq -r '.value[0].path // empty')
```

If nothing comes back — no sprint configured for today, or a gap between sprints — fall back to the project default iteration and warn the user:

```bash
if [ -z "$ITERATION_PATH" ]; then
  echo "No current iteration found — falling back to project default."
  ITERATION_PATH="$PROJECT"
fi

export ITERATION_PATH
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
TEAM:           My Project Team
```
