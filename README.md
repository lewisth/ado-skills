# ADO Skills

A collection of skills for working with repositories in Azure DevOps. 

All ADO skills detect your org, project, and process template automatically from `git remote`. They use the **Azure DevOps REST API** directly via `curl` — no Azure CLI extension required.

The only prerequisite is a Personal Access Token (PAT) with **Read** scope on Project and **Read & Write** scope on Work Items:

```bash
export AZURE_DEVOPS_PAT=your-pat-here
```

Add it to your shell profile or CI environment so it's always available.

Org, project, process template, repository URL, and area path are all **static per repo** — so `ado-context` runs a one-time setup that persists them to `.ado-skills.json`, and every subsequent invocation just reads the file. The iteration path is the only thing computed fresh each run, from today's date.

Example `.ado-skills.json` (commit this so your team and any CI agents share the same defaults):

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

- **Repository URL** — embedded in every Feature PRD and PBI description so downstream agents check out the right code.
- **Area path** — persisted once; change by editing `.ado-skills.json`.
- **Iteration path** — computed from today's date via the team iterations REST API (`$timeframe=current`), with the project default as a fallback.

## Workflow

### Setup (once per repo)

Run **`ado-context`** once. It detects org, project, process template, and repository URL from `git remote`, prompts for an area path, and writes `.ado-skills.json`. Commit the file so your team and any CI agents share the same defaults.

### Per-feature loop

These three skills chain together to take a rough idea all the way to independently-grabbable ADO work items for AI agents. `to-feature` and `to-pbis` silently re-invoke `ado-context` to reload `.ado-skills.json` and calculate today's iteration.

1. **spec-it** — reach shared understanding
2. **to-feature** — create an ADO Feature with the PRD
3. **to-pbis** — vertically slice the Feature into PBIs (or User Stories / Requirements, depending on process template)

Install all of them at once:

```bash
npx skills@latest add lewisth/ado-skills
```

### spec-it

Pair design with our LLM of choice about a plan or design until every branch of the decision tree is resolved.

```bash
npx skills@latest add lewisth/ado-skills --skill spec-it
```

### ado-context

Resolve the shared Azure DevOps context (org, project, process template, repository URL, area path, iteration path) used by the other ADO skills. Runs a one-time setup per repo that writes the static values to `.ado-skills.json`; afterwards just reads the file and calculates today's iteration.

```bash
npx skills@latest add lewisth/ado-skills --skill ado-context
```

### to-feature

Turn the current conversation context (typically from `spec-it`) into a PRD and submit it as an Azure DevOps **Feature** work item.

```bash
npx skills@latest add lewisth/ado-skills --skill to-feature
```

### to-pbis

Break a Feature into independently-grabbable PBIs using tracer-bullet vertical slices. Links each PBI as a child of the parent Feature and preserves blocking relationships as predecessors. Tags AFK slices `ready-for-agent` and HITL slices `ready-for-human`.

```bash
npx skills@latest add lewisth/ado-skills --skill to-pbis
```

### implement-pbi

Fetch one specific ADO PBI-like work item by ID, load its parent Feature context, implement only that scope on the current checked-out branch, create a local commit, and stop without pushing or opening a PR.

```bash
npx skills@latest add lewisth/ado-skills --skill implement-pbi
```

## ADO Concepts Reference

| GitHub | Azure DevOps |
|--------|-------------|
| Issues | Work Items (Bug, User Story, PBI, Requirement, Task) |
| Labels | Tags + Work Item Type + State |
| Issue comments | Work item discussions |
| "Blocked by" text | Predecessor/Successor relations (`System.LinkTypes.Dependency`) |
| Parent/child | Hierarchy relations (`System.LinkTypes.Hierarchy`) |
| `gh issue create` | `POST /wit/workitems/$Type` |
| `gh issue list` | `POST /wit/wiql` |
| `gh pr create` | `POST /repos/pullrequests` |

---

The workflow and skills is heavily inspired by [mattpocock/skills](https://github.com/mattpocock/skills). Go check out Matt's courses at [AIHero](https://www.aihero.dev/) and [Total TypeScript](https://www.totaltypescript.com/) — seriously good stuff.
