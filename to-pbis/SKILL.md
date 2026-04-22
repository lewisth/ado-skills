---
name: to-pbis
description: Vertically slice an Azure DevOps Feature into PBIs (or User Stories / Requirements, depending on process template) using tracer-bullet slices. Links each PBI as a child of the Feature and preserves blocking relationships. Use when user wants to break a Feature into PBIs, or mentions "to-pbis".
---

# To PBIs

Break a Feature into independently-grabbable **PBIs** using tracer-bullet vertical slices, linked as children of the parent Feature.

This is step **3** of the per-feature loop (prerequisite: `ado-context` has been run once to create `.ado-skills.json`):

1. `spec-it` — reach shared understanding
2. `to-feature` — create the Feature with the PRD
3. **`to-pbis`** — vertically slice the Feature into PBIs using tracer bullets  ← you are here

> "PBI" is the Scrum process template term. This skill works across all three templates and uses the correct type automatically:
>
> | Process | Story type           | Task type |
> | ------- | -------------------- | --------- |
> | Agile   | User Story           | Task      |
> | Scrum   | Product Backlog Item | Task      |
> | CMMI    | Requirement          | Task      |

## Detect ADO Context

Run the `ado-context` skill first. It loads `.ado-skills.json` (or runs a one-time setup to create it) and resolves today's iteration, exporting:

- `ORG` / `ORG_NAME` / `PROJECT` — loaded from `.ado-skills.json`
- `PROCESS` — process template; use it to pick the right story type (User Story / Product Backlog Item / Requirement)
- `REPOSITORY_URL` — the canonical repo URL; include it in each PBI description so the downstream agent works on the right code
- `AREA_PATH` — loaded from `.ado-skills.json`
- `ITERATION_PATH` — the iteration containing today's date

Every field below assumes those variables are already in scope, and that `AUTH` and `PROJECT_ENCODED` are set:

```bash
AUTH=$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)
PROJECT_ENCODED=$(printf '%s' "$PROJECT" | jq -sRr @uri)
```

## Process

### 1. Resolve the parent Feature

The parent Feature ID should come from the user (typically just produced by `to-feature`). If they don't supply one, ask. Fetch its details:

```bash
curl -s \
  -H "Authorization: Basic $AUTH" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$FEATURE_ID?api-version=7.1"
```

Use its PRD description as the primary source material.

### 2. Explore the codebase (optional)

If not already explored, understand the current state of the code.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** slices. Each slice is a thin vertical slice cutting through ALL integration layers end-to-end — NOT a horizontal layer slice.

Classify each slice:

- **AFK** — Away-from-keyboard: can be implemented and merged without human interaction
- **HITL** — Human-in-the-loop: requires a decision or design review

Prefer AFK over HITL where possible.

- Each slice delivers a narrow but COMPLETE path through every layer
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices must complete first (if any)
- **User stories covered**: map back to the PRD's user stories

Ask:

- Does the granularity feel right?
- Are dependency relationships correct?
- Should any slices be merged or split?
- Are HITL/AFK designations correct?

Iterate until the user approves.

### 5. Create ADO PBIs

Create items in dependency order (blockers first) so you can reference real IDs.

Apply a tag to each PBI based on its classification:

- **AFK** slices → `ready-for-agent`
- **HITL** slices → `ready-for-human`

For each approved slice, build the description and create the work item:

```bash
DESCRIPTION=$(cat <<EOF
## Repository

$REPOSITORY_URL

## What to build

A concise description of this vertical slice. End-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

#<work-item-id> (or "None — can start immediately")
EOF
)

PAYLOAD=$(jq -n \
  --arg title "Slice title" \
  --arg area  "$AREA_PATH" \
  --arg iter  "$ITERATION_PATH" \
  --arg tags  "ready-for-agent" \
  --arg desc  "$DESCRIPTION" \
  '[
    { op: "add", path: "/fields/System.Title",                          value: $title },
    { op: "add", path: "/fields/System.AreaPath",                       value: $area },
    { op: "add", path: "/fields/System.IterationPath",                  value: $iter },
    { op: "add", path: "/fields/System.Tags",                           value: $tags },
    { op: "add", path: "/fields/System.Description",                    value: $desc },
    { op: "add", path: "/multilineFieldsFormat/System.Description",     value: "Markdown" }
  ]')

STORY_TYPE_ENCODED=$(printf '%s' "$STORY_TYPE" | jq -sRr @uri)

ITEM=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/\$$STORY_TYPE_ENCODED?api-version=7.1")

ITEM_ID=$(echo "$ITEM" | jq '.id')
```

Link each PBI as a **child** of the parent Feature. The relation type `System.LinkTypes.Hierarchy-Reverse` means "the target is my parent":

```bash
PARENT_PAYLOAD=$(jq -n \
  --arg feature_url "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$FEATURE_ID" \
  '[{
    op: "add",
    path: "/relations/-",
    value: {
      rel: "System.LinkTypes.Hierarchy-Reverse",
      url: $feature_url,
      attributes: { comment: "" }
    }
  }]')

curl -s -X PATCH \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PARENT_PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$ITEM_ID?api-version=7.1"
```

Link blocking relationships between PBIs. The relation type `System.LinkTypes.Dependency-Forward` means "the target is my predecessor" (I am blocked by the target):

```bash
PREDECESSOR_PAYLOAD=$(jq -n \
  --arg blocker_url "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$BLOCKER_ID" \
  '[{
    op: "add",
    path: "/relations/-",
    value: {
      rel: "System.LinkTypes.Dependency-Forward",
      url: $blocker_url,
      attributes: { comment: "" }
    }
  }]')

curl -s -X PATCH \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json-patch+json" \
  -d "$PREDECESSOR_PAYLOAD" \
  "https://dev.azure.com/$ORG_NAME/$PROJECT_ENCODED/_apis/wit/workitems/$ITEM_ID?api-version=7.1"
```

### 6. Report out

Print the list of PBI IDs and URLs, grouped by their tag (`ready-for-agent` vs `ready-for-human`), and note the parent Feature ID and any blocking relationships.
