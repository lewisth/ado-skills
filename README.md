# ADO Skills

A collection of skills for working with repositories in Azure DevOps. 

All ADO skills detect your org, project, and process template automatically from `git remote`. They require the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) with the DevOps extension:

```bash
az extension add --name azure-devops
az login
```

## Workflow

These three skills chain together to take a rough idea all the way to independently-grabbable ADO work items for AI agents:

1. **spec-it** — reach shared understanding
2. **to-feature** — create an ADO Feature with the PRD
3. **to-pbis** — vertically slice the Feature into PBIs (or User Stories / Requirements, depending on process template)

### spec-it

Pair design with our LLM of choice about a plan or design until every branch of the decision tree is resolved.

```
npx skills@latest add lewistharper/ado-skills/spec-it
```

### to-feature

Turn the current conversation context (typically from `spec-it`) into a PRD and submit it as an Azure DevOps **Feature** work item.

```
npx skills@latest add lewistharper/ado-skills/to-feature
```

### to-pbis

Break a Feature into independently-grabbable PBIs using tracer-bullet vertical slices. Links each PBI as a child of the parent Feature and preserves blocking relationships as predecessors. Tags AFK slices `ready-for-agent` and HITL slices `ready-for-human`.

```
npx skills@latest add lewistharper/ado-skills/to-pbis
```

## ADO Concepts Reference

| GitHub | Azure DevOps |
|--------|-------------|
| Issues | Work Items (Bug, User Story, PBI, Requirement, Task) |
| Labels | Tags + Work Item Type + State |
| Issue comments | Work item discussions (`--discussion`) |
| "Blocked by" text | Predecessor/Successor relations |
| `gh issue create` | `az boards work-item create` |
| `gh issue list` | `az boards query --wiql` |
| `gh pr create` | `az repos pr create` |

| Process | Story type           | Task type |
| ------- | -------------------- | --------- |
| Agile   | User Story           | Task      |
| Scrum   | Product Backlog Item | Task      |
| CMMI    | Requirement          | Task      |
