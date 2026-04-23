# agent-loop

`agent-loop` automates an Azure DevOps feature implementation loop with an AI coding agent.

It ships with two entrypoints:

- `agent-loop.sh` for Bash environments
- `agent-loop.ps1` for PowerShell environments

Both scripts do the same job:

1. Load configuration from `.agent-loop.json` and/or CLI arguments.
2. Query Azure DevOps for a Feature to process.
3. Create and push a feature branch.
4. Process eligible child PBIs one at a time with an AI agent.
5. Create an Azure DevOps pull request when all PBIs complete successfully.

## What The Scripts Do

At a high level, the scripts:

- authenticate to Azure DevOps with `AZURE_DEVOPS_PAT`
- optionally filter Features by `areaPath`
- select either:
  - a specific Feature via `featureId`, or
  - the first Feature that has at least one child PBI tagged `ready-for-agent` and in state `New`
- fetch child PBIs and sort them by dependency order
- create a branch named `agent/<feature-id>-<feature-slug>`
- write parent Feature context to `.agent-context/feature.md`
- invoke either:
  - `claude` when `provider` is `claude-code`
  - `agent` when `provider` is `cursor-cli`
- repeat agent invocations for each PBI until the agent signals completion and the branch is clean and fully pushed
- tag PBIs as `agent-done` on success or `agent-failed` on failure
- create an Azure DevOps pull request linked to the processed PBIs

## Files In This Folder

- `agent-loop.sh`: Bash implementation
- `agent-loop.ps1`: PowerShell implementation
- `.agent-loop.example.json`: example config you can copy to `.agent-loop.json`

## Prerequisites

Common requirements:

- Git
- network access to Azure DevOps
- an Azure DevOps PAT exposed as `AZURE_DEVOPS_PAT`
- a local clone of the target repository
- one supported agent CLI:
  - `claude` for `claude-code`
  - `agent` for `cursor-cli`

Additional requirements by script:

- `agent-loop.sh`
  - Bash
  - `curl`
  - `jq`
- `agent-loop.ps1`
  - PowerShell 7+

## Configuration

The scripts read config in this order:

1. CLI arguments / parameters
2. `.agent-loop.json` in the working directory
3. a few environment variable fallbacks for paths

Minimum required values:

- `organizationUrl`
- `project`
- `provider`

Useful optional values:

- `areaPath`
- `team`
- `process`
- `repositoryUrl`
- `baseBranch`
- `maxIterationsPerPbi`
- `model`
- `workingDirectory`
- `systemLogDirectory`
- `featureId`

Provider-specific environment variables:

- `ANTHROPIC_API_KEY` is optional when `provider` is `claude-code`; if set, Claude Code uses API-key auth instead of the signed-in Claude session
- `CURSOR_API_KEY` when `provider` is `cursor-cli`

## Example Config

Create `agent-loop/.agent-loop.json` from the example file and fill in real values:

```json
{
  "organizationUrl": "https://dev.azure.com/your-org",
  "project": "Your Project",
  "areaPath": "Your Project\\Your Team",
  "team": "Your Project Team",
  "process": "Scrum",
  "repositoryUrl": "https://dev.azure.com/your-org/Your%20Project/_git/your-repo",
  "baseBranch": "main",
  "maxIterationsPerPbi": 5,
  "provider": "claude-code",
  "model": "claude-opus-4-6",
  "workingDirectory": "/absolute/path/to/your/repo",
  "systemLogDirectory": "/absolute/path/to/system/logs",
  "featureId": "12345"
}
```

Note: `.agent-loop.example.json` currently includes `pollIntervalSeconds`, but the scripts do not read or use that setting.

## Usage

### Bash

Run from the `agent-loop` folder, or pass `--working-directory` explicitly:

```bash
export AZURE_DEVOPS_PAT=...

# Make sure `claude` is already signed in if using provider=claude-code.
# Do not set ANTHROPIC_API_KEY if you want to use your Claude subscription.

./agent-loop.sh \
  --org "https://dev.azure.com/your-org" \
  --project "Your Project" \
  --provider "claude-code" \
  --repo-url "https://dev.azure.com/your-org/Your%20Project/_git/your-repo" \
  --working-directory "/absolute/path/to/your/repo"
```

One-shot mode for a specific Feature:

```bash
./agent-loop.sh \
  --org "https://dev.azure.com/your-org" \
  --project "Your Project" \
  --provider "cursor-cli" \
  --working-directory "/absolute/path/to/your/repo" \
  --feature-id 12345
```

### PowerShell

```powershell
$env:AZURE_DEVOPS_PAT = "..."

./agent-loop.ps1 `
  -Org "https://dev.azure.com/your-org" `
  -Project "Your Project" `
  -Provider "claude-code" `
  -RepoUrl "https://dev.azure.com/your-org/Your%20Project/_git/your-repo" `
  -WorkingDirectory "/absolute/path/to/your/repo"
```

One-shot mode for a specific Feature:

```powershell
./agent-loop.ps1 `
  -Org "https://dev.azure.com/your-org" `
  -Project "Your Project" `
  -Provider "claude-code" `
  -WorkingDirectory "/absolute/path/to/your/repo" `
  -FeatureId 12345
```

## Runtime Behavior

### Scheduled Mode

If you do not supply a Feature ID, the scripts query Azure DevOps for the first Feature that has at least one direct child PBI where:

- the tag `ready-for-agent` is present
- the state is `New`

If `areaPath` is set, the Feature query is limited to that area path.

### One-Shot Mode

If you set `featureId`, the scripts process only that Feature.

### PBI Processing Rules

For each eligible child PBI, the scripts:

- set the PBI state to:
  - `In Progress` for Scrum and unknown processes
  - `Active` for Agile and CMMI
- build a prompt from:
  - PBI title
  - PBI description
  - acceptance criteria
  - parent Feature context
- invoke the AI agent up to `maxIterationsPerPbi` times
- require both of the following before marking the PBI complete:
  - the agent outputs `AGENT_COMPLETE`
  - the git working tree is clean and all commits are pushed

If any PBI fails, remaining PBIs for that Feature are skipped.

### Dependency Ordering

PBIs are processed in topological order using Azure DevOps `Dependency-Forward` links. If a circular dependency is detected, processing stops.

## Files And Side Effects

The scripts create or manage these repo-local files:

- `.agent-loop.lock`: prevents concurrent runs
- `.agent-context/feature.md`: temporary feature context for the agent
- `.agent-context/logs/feature-<id>.log`: captured agent output during the run

They also make sure `.gitignore` contains:

- `.agent-context/`
- `.agent-loop.lock`

Persistent logs are written outside the repo by default:

- macOS: `~/Library/Logs/agent-loop`
- Linux: `${XDG_STATE_HOME:-~/.local/state}/agent-loop/logs`
- Windows PowerShell: `%LOCALAPPDATA%\agent-loop\logs` when available

You can override that path with `systemLogDirectory`.

## Outputs

On success, the scripts:

- push a feature branch to `origin`
- tag each completed PBI with `agent-done`
- create an Azure DevOps pull request targeting the resolved base branch

On failure, the scripts:

- tag the failing PBI with `agent-failed`
- stop processing the remaining PBIs for that Feature

## Notes

- `repositoryUrl` is effectively required if you want automatic pull request creation.
- If `baseBranch` is omitted, the scripts try to detect it from `origin/HEAD`.
- `claude-code` does not require `ANTHROPIC_API_KEY` when the user is already logged into Claude Code. If `ANTHROPIC_API_KEY` is set, Claude Code will prefer the API key instead of the signed-in subscription session.
- The Bash and PowerShell versions are intended to stay behaviorally aligned.
