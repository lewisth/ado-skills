---
name: to-pbis
description: Vertically slice an Azure DevOps Feature into PBIs (or User Stories / Requirements, depending on process template) using tracer-bullet slices. Links each PBI as a child of the Feature and preserves blocking relationships. Use when user wants to break a Feature into PBIs, or mentions "to-pbis".
---

# To PBIs

Break a Feature into independently-grabbable **PBIs** using tracer-bullet vertical slices, linked as children of the parent Feature.

This is step **3** of the workflow:

1. `build-a-spec` — reach shared understanding
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

Parse org and project from `git remote get-url origin`:

- HTTPS: `https://dev.azure.com/{org}/{project}/_git/{repo}`
- SSH: `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`
- Legacy: `https://{org}.visualstudio.com/{project}/_git/{repo}`

Detect process template to select the correct story type:

```bash
az devops project show --org $ORG --project "$PROJECT" \
  --query "capabilities.processTemplate.templateName" -o tsv
```

## Process

### 1. Resolve the parent Feature

The parent Feature ID should come from the user (typically just produced by `to-feature`). If they don't supply one, ask. Fetch it:

```bash
az boards work-item show --org $ORG --id $FEATURE_ID --output json
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

For each approved slice:

```bash
ITEM=$(az boards work-item create \
  --org $ORG \
  --project "$PROJECT" \
  --type "$STORY_TYPE" \
  --title "Slice title" \
  --tags "ready-for-agent" \
  --description "$(cat <<'EOF'
## What to build

A concise description of this vertical slice. End-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

#<work-item-id> (or "None — can start immediately")
EOF
)" \
  --output json)

ITEM_ID=$(echo $ITEM | jq '.id')
```

Link each PBI as a **child** of the parent Feature:

```bash
az boards work-item relation add \
  --org $ORG \
  --id $ITEM_ID \
  --relation-type "Parent" \
  --target-id $FEATURE_ID
```

Link blocking relationships between PBIs as predecessors:

```bash
az boards work-item relation add \
  --org $ORG \
  --id $ITEM_ID \
  --relation-type "Predecessor" \
  --target-id $BLOCKER_ID
```

### 6. Report out

Print the list of PBI IDs and URLs, grouped by their tag (`ready-for-agent` vs `ready-for-human`), and note the parent Feature ID and any blocking relationships.
