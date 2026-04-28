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

### report-bug

Interview a QA engineer step-by-step to gather bug details (repro steps, expected/actual behaviour, severity), then create an Azure DevOps **Bug** work item with structured reproduction steps.

```bash
npx skills@latest add lewisth/ado-skills --skill report-bug
```

### implement-pbi

Fetch one specific ADO PBI-like work item by ID, load its parent Feature context, implement only that scope on the current checked-out branch, create a local commit, and stop without pushing or opening a PR.

```bash
npx skills@latest add lewisth/ado-skills --skill implement-pbi
```

## Testing And QA Skills

These skills help with planning, writing, reviewing, and triaging testing work around features, bugs, releases, and PRs.

### test-writing

Infer the repo's testing conventions and write new or updated tests that match them closely.

```bash
npx skills@latest add lewisth/ado-skills --skill test-writing
```

### api-testing

Write API tests that match the repo's conventions for REST or GraphQL validation, auth handling, contract testing, and dependency strategy.

```bash
npx skills@latest add lewisth/ado-skills --skill api-testing
```

### e2e-automation

Write end-to-end tests that match the repo's browser automation patterns for page objects, locators, waits, retries, and spec layout.

```bash
npx skills@latest add lewisth/ado-skills --skill e2e-automation
```

### accessibility-testing

Write accessibility testing guidance that combines automated checks, manual verification, and WCAG traceability.

```bash
npx skills@latest add lewisth/ado-skills --skill accessibility-testing
```

### exploratory-testing-charter

Create session-based exploratory testing charters with a clear mission, time box, note-taking structure, and follow-up actions.

```bash
npx skills@latest add lewisth/ado-skills --skill exploratory-testing-charter
```

### flaky-test-triage

Triage unstable test failures by gathering evidence, classifying flaky versus real versus environmental issues, inspecting code history, and proposing the right response.

```bash
npx skills@latest add lewisth/ado-skills --skill flaky-test-triage
```

### performance-testing

Write performance test plans and scripts that match the repo's tooling, workload models, SLOs, and thresholds.

```bash
npx skills@latest add lewisth/ado-skills --skill performance-testing
```

### pr-review-qa-lens

Review a pull request from a QA perspective by identifying break risk, missing coverage, edge cases, and rollback concerns.

```bash
npx skills@latest add lewisth/ado-skills --skill pr-review-qa-lens
```

### release-readiness

Assess whether a change set is ready to release using smoke results, known issues, regression coverage, and deployment-risk checks.

```bash
npx skills@latest add lewisth/ado-skills --skill release-readiness
```

### test-data-generation

Generate realistic, policy-safe test data for automated and manual testing, including edge cases and internationalized content.

```bash
npx skills@latest add lewisth/ado-skills --skill test-data-generation
```

### test-plan-authoring

Generate structured test plans from requirements, user stories, bug reports, or pull requests with clear traceability and risk-based prioritization.

```bash
npx skills@latest add lewisth/ado-skills --skill test-plan-authoring
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
