<#
.SYNOPSIS
  agent-loop.ps1 — Autonomous ADO feature implementation loop.

.DESCRIPTION
  Reads config from .agent-loop.json in the working directory and/or
  CLI parameters (CLI wins). Validates all required values before running.

.PARAMETER Org
  Azure DevOps org URL (e.g. https://dev.azure.com/contoso)

.PARAMETER Project
  Azure DevOps project name

.PARAMETER AreaPath
  Work item area path (e.g. "MyProject\Team A")

.PARAMETER Team
  Azure DevOps team name

.PARAMETER Process
  Process template: Scrum, Agile, or CMMI

.PARAMETER RepoUrl
  Git repository URL

.PARAMETER BaseBranch
  Base branch (auto-detected from git if omitted)

.PARAMETER MaxIterations
  Max agent invocations per PBI (default: 5)

.PARAMETER Provider
  AI provider: claude-code or cursor-cli

.PARAMETER Model
  Model ID to use (e.g. claude-opus-4-6)

.PARAMETER WorkingDirectory
  Working directory containing the repo

.PARAMETER FeatureId
  ADO Feature ID to process (optional; processes all if omitted)

.NOTES
  Required environment variables:
    AZURE_DEVOPS_PAT     — Azure DevOps Personal Access Token
    ANTHROPIC_API_KEY    — Required when -Provider is claude-code
    CURSOR_API_KEY       — Required when -Provider is cursor-cli
#>

[CmdletBinding()]
param(
    [string] $Org,
    [string] $Project,
    [string] $AreaPath,
    [string] $Team,
    [string] $Process,
    [string] $RepoUrl,
    [string] $BaseBranch,
    [int]    $MaxIterations,
    [string] $Provider,
    [string] $Model,
    [string] $WorkingDirectory,
    [string] $FeatureId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Logging ───────────────────────────────────────────────────────────
function log_info {
    param([string]$Message)
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$ts] [INFO] $Message"
}

function log_warn {
    param([string]$Message)
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    Write-Error "[$ts] [WARN] $Message"
}

function log_error {
    param([string]$Message)
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    Write-Error "[$ts] [ERROR] $Message"
}

# ── Load config file ──────────────────────────────────────────────────
# Resolve working directory: param > env > current directory
$resolvedWorkingDir = if ($WorkingDirectory) {
    $WorkingDirectory
} elseif ($env:AGENT_LOOP_WORKING_DIRECTORY) {
    $env:AGENT_LOOP_WORKING_DIRECTORY
} else {
    (Get-Location).Path
}

$configFile = Join-Path $resolvedWorkingDir '.agent-loop.json'
$fileConfig = @{}

if (Test-Path $configFile) {
    try {
        $json = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($null -ne $json.organizationUrl) { $fileConfig['Org']              = $json.organizationUrl }
        if ($null -ne $json.project)         { $fileConfig['Project']          = $json.project }
        if ($null -ne $json.areaPath)        { $fileConfig['AreaPath']         = $json.areaPath }
        if ($null -ne $json.team)            { $fileConfig['Team']             = $json.team }
        if ($null -ne $json.process)         { $fileConfig['Process']          = $json.process }
        if ($null -ne $json.repositoryUrl)   { $fileConfig['RepoUrl']          = $json.repositoryUrl }
        if ($null -ne $json.baseBranch)      { $fileConfig['BaseBranch']       = $json.baseBranch }
        if ($null -ne $json.maxIterationsPerPbi) { $fileConfig['MaxIterations'] = $json.maxIterationsPerPbi }
        if ($null -ne $json.provider)        { $fileConfig['Provider']         = $json.provider }
        if ($null -ne $json.model)           { $fileConfig['Model']            = $json.model }
        if ($null -ne $json.workingDirectory) { $fileConfig['WorkingDirectory'] = $json.workingDirectory }
        if ($null -ne $json.featureId)       { $fileConfig['FeatureId']        = [string]$json.featureId }
    } catch {
        Write-Error "Error: Failed to parse ${configFile}: $_"
        exit 1
    }
}

# ── Merge: CLI wins over config file ─────────────────────────────────
function Resolve-Value {
    param($cliValue, $configKey, $default = $null)
    if ($cliValue -and $cliValue -ne 0) { return $cliValue }
    if ($fileConfig.ContainsKey($configKey) -and $fileConfig[$configKey]) { return $fileConfig[$configKey] }
    return $default
}

$resolvedOrg            = Resolve-Value $Org           'Org'
$resolvedProject        = Resolve-Value $Project       'Project'
$resolvedAreaPath       = Resolve-Value $AreaPath      'AreaPath'
$resolvedTeam           = Resolve-Value $Team          'Team'
$resolvedProcess        = Resolve-Value $Process       'Process'
$resolvedRepoUrl        = Resolve-Value $RepoUrl       'RepoUrl'
$resolvedBaseBranch     = Resolve-Value $BaseBranch    'BaseBranch'    $null
$resolvedMaxIterations  = Resolve-Value $MaxIterations 'MaxIterations' 5
$resolvedProvider       = Resolve-Value $Provider      'Provider'
$resolvedModel          = Resolve-Value $Model         'Model'
$resolvedFeatureId      = Resolve-Value $FeatureId     'FeatureId'

# ── Validate required values ──────────────────────────────────────────
$errors = [System.Collections.Generic.List[string]]::new()

if (-not $resolvedOrg)      { $errors.Add('Missing required value: -Org (Azure DevOps org URL)') }
if (-not $resolvedProject)  { $errors.Add('Missing required value: -Project (Azure DevOps project name)') }
if (-not $resolvedProvider) { $errors.Add('Missing required value: -Provider (claude-code or cursor-cli)') }

if ($errors.Count -gt 0) {
    Write-Host 'Error: Configuration is incomplete:' -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'Provide values via CLI parameters or .agent-loop.json in the working directory.' -ForegroundColor Yellow
    Write-Host 'See .agent-loop.example.json for the full schema.' -ForegroundColor Yellow
    exit 1
}

# ── Validate provider value ───────────────────────────────────────────
if ($resolvedProvider -notin @('claude-code', 'cursor-cli')) {
    Write-Host "Error: Invalid provider '$resolvedProvider'. Must be 'claude-code' or 'cursor-cli'." -ForegroundColor Red
    exit 1
}

# ── Validate environment variables ───────────────────────────────────
$envErrors = [System.Collections.Generic.List[string]]::new()

if (-not $env:AZURE_DEVOPS_PAT) {
    $envErrors.Add('Missing required environment variable: AZURE_DEVOPS_PAT')
}

if ($resolvedProvider -eq 'claude-code' -and -not $env:ANTHROPIC_API_KEY) {
    $envErrors.Add('Missing required environment variable: ANTHROPIC_API_KEY (required for provider=claude-code)')
}

if ($resolvedProvider -eq 'cursor-cli' -and -not $env:CURSOR_API_KEY) {
    $envErrors.Add('Missing required environment variable: CURSOR_API_KEY (required for provider=cursor-cli)')
}

if ($envErrors.Count -gt 0) {
    Write-Host 'Error: Required environment variables are not set:' -ForegroundColor Red
    foreach ($err in $envErrors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    exit 1
}

# ── Export resolved config for use by the rest of the script ─────────
$env:AGENT_LOOP_ORG               = $resolvedOrg
$env:AGENT_LOOP_PROJECT           = $resolvedProject
$env:AGENT_LOOP_AREA_PATH         = $resolvedAreaPath
$env:AGENT_LOOP_TEAM              = $resolvedTeam
$env:AGENT_LOOP_PROCESS           = $resolvedProcess
$env:AGENT_LOOP_REPO_URL          = $resolvedRepoUrl
$env:AGENT_LOOP_BASE_BRANCH       = $resolvedBaseBranch
$env:AGENT_LOOP_MAX_ITERATIONS    = $resolvedMaxIterations
$env:AGENT_LOOP_PROVIDER          = $resolvedProvider
$env:AGENT_LOOP_MODEL             = $resolvedModel
$env:AGENT_LOOP_WORKING_DIRECTORY = $resolvedWorkingDir
$env:AGENT_LOOP_FEATURE_ID        = $resolvedFeatureId

$modelLabel = if ($resolvedModel) { " ($resolvedModel)" } else { '' }

$baseBranchLabel = if ($resolvedBaseBranch) { $resolvedBaseBranch } else { '(auto-detect)' }

Write-Host ('=' * 54)
Write-Host '  agent-loop'
Write-Host "  Org:             $resolvedOrg"
Write-Host "  Project:         $resolvedProject"
Write-Host "  Provider:        ${resolvedProvider}${modelLabel}"
Write-Host "  Base branch:     $baseBranchLabel"
Write-Host "  Max iter/PBI:    $resolvedMaxIterations"
if ($resolvedFeatureId) { Write-Host "  Feature ID:      $resolvedFeatureId" }
if ($resolvedAreaPath)  { Write-Host "  Area path:       $resolvedAreaPath" }
if ($resolvedTeam)      { Write-Host "  Team:            $resolvedTeam" }
if ($resolvedRepoUrl)   { Write-Host "  Repo URL:        $resolvedRepoUrl" }
Write-Host ('=' * 54)

# ── Lock manager ──────────────────────────────────────────────────────
$lockFile = Join-Path $resolvedWorkingDir '.agent-loop.lock'

function Acquire-Lock {
    try {
        $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Close()
        $stream.Dispose()
    } catch {
        log_warn "Another instance is already running (lock file exists: $lockFile). Exiting."
        exit 0
    }
    log_info "Lock acquired: $lockFile"
}

function Release-Lock {
    if (Test-Path $lockFile) {
        Remove-Item -Force $lockFile
        log_info "Lock released: $lockFile"
    }
}

# ── Context manager ───────────────────────────────────────────────────
$agentContextDir = Join-Path $resolvedWorkingDir '.agent-context'

function Ensure-Gitignore {
    $gitignore = Join-Path $resolvedWorkingDir '.gitignore'
    $entries = @('.agent-context/', '.agent-loop.lock')
    foreach ($entry in $entries) {
        if (-not (Test-Path $gitignore) -or -not (Get-Content $gitignore -Raw).Contains($entry)) {
            Add-Content -Path $gitignore -Value $entry
            log_info "$entry added to .gitignore"
        }
    }
}

function Write-FeatureContext {
    param([string]$FeatureId, [string]$Content)
    if (-not (Test-Path $agentContextDir)) { New-Item -ItemType Directory -Path $agentContextDir -Force | Out-Null }
    Set-Content -Path (Join-Path $agentContextDir 'feature.md') -Value $Content -NoNewline
    log_info "Feature context written to .agent-context/feature.md (feature $FeatureId)"
}

function Capture-AgentLog {
    param([string]$FeatureId, [string]$Output)
    $logsDir = Join-Path $agentContextDir 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    Add-Content -Path (Join-Path $logsDir "feature-${FeatureId}.log") -Value $Output
}

function Invoke-Cleanup {
    if (Test-Path $agentContextDir) {
        Remove-Item -Recurse -Force $agentContextDir
        log_info "Cleaned up .agent-context/"
    }
}

# ── ADO Client ────────────────────────────────────────────────────────

# Returns the "Basic <base64(:PAT)>" header value for ADO REST calls.
function Get-AdoAuthHeader {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(":$($env:AZURE_DEVOPS_PAT)")
    return "Basic $([Convert]::ToBase64String($bytes))"
}

# Makes an ADO REST API call.
# Returns the deserialized response on success (HTTP 2xx).
# Logs an error and re-throws on failure.
# Usage: Invoke-AdoApi -Method GET|POST -Url <url> [-Body <json>] [-ContentType <type>]
function Invoke-AdoApi {
    param(
        [string] $Method,
        [string] $Url,
        [string] $Body = $null,
        [string] $ContentType = 'application/json'
    )
    $headers = @{
        'Authorization' = Get-AdoAuthHeader
        'Content-Type'  = $ContentType
    }
    try {
        if ($Body) {
            return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $Body
        } else {
            return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody  = $_.ErrorDetails.Message
        log_error "ADO API error: HTTP $statusCode — $Method $Url"
        log_error "Response: $errorBody"
        throw
    }
}

# Queries ADO for Features that have at least one child PBI tagged
# "ready-for-agent" in "New" state, scoped to the configured AreaPath.
# Returns an array of Feature IDs (integers).
function Get-EligibleFeatures {
    $wiql = "SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.WorkItemType] = 'Feature'"
    if ($resolvedAreaPath) {
        $wiql += " AND [Source].[System.AreaPath] UNDER '$resolvedAreaPath'"
    }
    $wiql += " AND [Target].[System.Tags] CONTAINS 'ready-for-agent' AND [Target].[System.State] = 'New' AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' MODE (MustContain)"

    $url  = "$resolvedOrg/$resolvedProject/_apis/wit/wiql?api-version=7.1"
    $body = @{ query = $wiql } | ConvertTo-Json -Compress

    $response = Invoke-AdoApi -Method POST -Url $url -Body $body

    # Extract unique source Feature IDs (source is $null for the root row; skip it).
    return @(
        $response.workItemRelations |
        Where-Object { $null -ne $_.source } |
        ForEach-Object { $_.source.id } |
        Select-Object -Unique
    )
}

# Fetches all child PBIs of a Feature, expanding all fields and relations
# (including Dependency-Forward links needed by the dependency resolver).
# Returns an array of work item objects.
# Usage: Get-ChildPbis -FeatureId <id>
function Get-ChildPbis {
    param([string] $FeatureId)

    # Fetch the Feature to get its relations.
    $featureUrl = "$resolvedOrg/$resolvedProject/_apis/wit/workitems/${FeatureId}?`$expand=relations&api-version=7.1"
    $feature    = Invoke-AdoApi -Method GET -Url $featureUrl

    # Extract IDs of direct children (Hierarchy-Forward from Feature to PBI).
    $childIds = @(
        ($feature.relations ?? @()) |
        Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' } |
        ForEach-Object { ($_.url -split '/')[-1] }
    )

    if ($childIds.Count -eq 0) {
        log_info "No child PBIs found for Feature $FeatureId"
        return @()
    }

    $idsParam = $childIds -join ','
    # Fetch all child PBIs with full expansion (fields + relations).
    $pbisUrl  = "$resolvedOrg/$resolvedProject/_apis/wit/workitems?ids=$idsParam&`$expand=all&api-version=7.1"
    $response = Invoke-AdoApi -Method GET -Url $pbisUrl

    return $response.value
}

# Fetches a single work item by ID with all fields and relations expanded.
# Returns the work item object.
# Usage: Get-WorkItem -WorkItemId <id>
function Get-WorkItem {
    param([string] $WorkItemId)
    $url = "$resolvedOrg/$resolvedProject/_apis/wit/workitems/${WorkItemId}?`$expand=all&api-version=7.1"
    return Invoke-AdoApi -Method GET -Url $url
}

# Transitions a work item to the given state.
# Returns the "in progress" state name for the configured process template.
# Scrum → "In Progress"; Agile/CMMI → "Active"; unknown → "In Progress".
function Get-InProgressState {
    switch ($resolvedProcess) {
        { $_ -in @('Agile', 'CMMI') } { return 'Active' }
        default                        { return 'In Progress' }
    }
}

# The caller is responsible for passing the correct state name for the process
# template (e.g. "Active" for Agile, "In Progress" for Scrum).
# Usage: Update-WorkItemState -WorkItemId <id> -State <state>
function Update-WorkItemState {
    param(
        [string] $WorkItemId,
        [string] $State
    )
    $patchDoc = @(
        @{ op = 'add'; path = '/fields/System.State'; value = $State }
    ) | ConvertTo-Json -Compress
    $url = "$resolvedOrg/$resolvedProject/_apis/wit/workitems/${WorkItemId}?api-version=7.1"
    Invoke-AdoApi -Method PATCH -Url $url -Body $patchDoc -ContentType 'application/json-patch+json' | Out-Null
    log_info "Work item $WorkItemId state set to '$State'"
}

# Appends a tag to a work item without removing existing tags.
# Usage: Add-WorkItemTag -WorkItemId <id> -Tag <tag>
function Add-WorkItemTag {
    param(
        [string] $WorkItemId,
        [string] $Tag
    )
    # Fetch current tags so we can append rather than overwrite.
    $workItem    = Get-WorkItem -WorkItemId $WorkItemId
    $currentTags = $workItem.fields.'System.Tags'
    $newTags     = if ($currentTags) { "$currentTags; $Tag" } else { $Tag }

    $patchDoc = @(
        @{ op = 'add'; path = '/fields/System.Tags'; value = $newTags }
    ) | ConvertTo-Json -Compress
    $url = "$resolvedOrg/$resolvedProject/_apis/wit/workitems/${WorkItemId}?api-version=7.1"
    Invoke-AdoApi -Method PATCH -Url $url -Body $patchDoc -ContentType 'application/json-patch+json' | Out-Null
    log_info "Tag '$Tag' appended to work item $WorkItemId"
}

# Creates a pull request and links all PBI work items to it.
# Returns the PR web URL as a string.
# Usage: New-PullRequest -FeatureTitle <title> -FeatureBranch <branch> -Pbis <array>
#   FeatureTitle  — Title string for the PR (becomes the PR title)
#   FeatureBranch — Source branch name (e.g. agent/42-my-feature)
#   Pbis          — Array of PBI work item objects with .id and .fields.'System.Title' present
function New-PullRequest {
    param(
        [string]   $FeatureTitle,
        [string]   $FeatureBranch,
        [object[]] $Pbis
    )

    if (-not $resolvedRepoUrl) {
        log_error "New-PullRequest: RepoUrl is not set — cannot determine repository for PR creation"
        throw "RepoUrl is required for PR creation"
    }

    # Extract repository name from RepoUrl (last path segment after /_git/).
    $repoId = ($resolvedRepoUrl -split '/_git/')[-1] -replace '[/?].*', ''

    if (-not $repoId) {
        log_error "New-PullRequest: unable to parse repository name from RepoUrl='$resolvedRepoUrl'"
        throw "Could not parse repository name from RepoUrl"
    }

    # Build PR description listing all PBI IDs and titles.
    $descLines   = $Pbis | ForEach-Object { "- #$($_.id): $($_.fields.'System.Title')" }
    $description = $descLines -join "`n"

    # Build workItemRefs array: [{ "id": "123" }, ...]
    $workItemRefs = @($Pbis | ForEach-Object { @{ id = [string]$_.id } })

    $body = @{
        title         = $FeatureTitle
        description   = $description
        sourceRefName = "refs/heads/$FeatureBranch"
        targetRefName = "refs/heads/$resolvedBaseBranch"
        workItemRefs  = $workItemRefs
    } | ConvertTo-Json -Depth 5 -Compress

    $url      = "$resolvedOrg/$resolvedProject/_apis/git/repositories/$repoId/pullrequests?api-version=7.1"
    $response = Invoke-AdoApi -Method POST -Url $url -Body $body

    $prId     = $response.pullRequestId
    $prWebUrl = "$resolvedOrg/$resolvedProject/_git/$repoId/pullrequest/$prId"
    log_info "Pull request #${prId} created: $prWebUrl"
    return $prWebUrl
}

# ── Dependency resolver ───────────────────────────────────────────────

# Topologically sorts PBIs by their Dependency-Forward relations using
# Kahn's algorithm.  PBIs with no predecessors appear first; the
# relative order among independent PBIs is preserved from the input.
#
# Usage:  Sort-PbisByDependency -Pbis <array>
#   Pbis — Array of PBI work item objects (with $expand=all so the
#          .relations property is present).
#
# On success: returns an array of PBI objects in dependency order.
# On cycle:   logs an error identifying the cycle and throws.
# Empty input is handled gracefully (returns an empty array).
function Sort-PbisByDependency {
    param([object[]] $Pbis)

    if ($null -eq $Pbis -or $Pbis.Count -eq 0) { return @() }

    # Build set of IDs in scope for fast membership checks.
    $idSet = @{}
    foreach ($pbi in $Pbis) { $idSet[[string]$pbi.id] = $true }

    # adj[$src]  = List<string> of successor IDs (PBIs that depend on $src)
    # indeg[$id] = number of unprocessed predecessors for $id
    $adj   = @{}
    $indeg = @{}
    foreach ($pbi in $Pbis) {
        $id = [string]$pbi.id
        $adj[$id]   = [System.Collections.Generic.List[string]]::new()
        $indeg[$id] = 0
    }

    # Dependency-Forward on a PBI means "this PBI is a predecessor of the
    # linked item" → edge: src → tgt (src must execute before tgt).
    foreach ($pbi in $Pbis) {
        $src  = [string]$pbi.id
        $rels = if ($null -ne $pbi.relations) { @($pbi.relations) } else { @() }
        foreach ($rel in $rels) {
            if ($rel.rel -ne 'System.LinkTypes.Dependency-Forward') { continue }
            $tgt = ($rel.url -split '/')[-1]
            if (-not $idSet.ContainsKey($tgt)) { continue }
            if ($adj[$src].Contains($tgt))     { continue }  # deduplicate
            $adj[$src].Add($tgt)
            $indeg[$tgt]++
        }
    }

    # Kahn's algorithm — seed queue with zero-indegree nodes in original order.
    $queue  = [System.Collections.Generic.Queue[string]]::new()
    foreach ($pbi in $Pbis) {
        if ($indeg[[string]$pbi.id] -eq 0) { $queue.Enqueue([string]$pbi.id) }
    }

    $sorted = [System.Collections.Generic.List[string]]::new()
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $sorted.Add($node)
        foreach ($succ in @($adj[$node])) {
            $indeg[$succ]--
            if ($indeg[$succ] -eq 0) { $queue.Enqueue($succ) }
        }
    }

    # If not all nodes were processed a cycle exists.
    if ($sorted.Count -ne $Pbis.Count) {
        $cycleNodes = @(
            $Pbis |
            Where-Object { $indeg[[string]$_.id] -gt 0 } |
            ForEach-Object { [string]$_.id }
        )
        $msg = "Sort-PbisByDependency: circular dependency detected among PBIs: $($cycleNodes -join ', ')"
        log_error $msg
        throw $msg
    }

    # Return PBI objects in sorted order.
    $pbiMap = @{}
    foreach ($pbi in $Pbis) { $pbiMap[[string]$pbi.id] = $pbi }
    return @($sorted | ForEach-Object { $pbiMap[$_] })
}

# ── Git manager ────────────────────────────────────────────────────────

# Resolves the default/base branch name.
# Priority: resolvedBaseBranch config/CLI value > git symbolic-ref > error
# Returns the branch name as a string. Throws on failure.
function Get-DefaultBranch {
    if ($resolvedBaseBranch) {
        return $resolvedBaseBranch
    }

    $ref = git symbolic-ref refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $ref) {
        $msg = "Get-DefaultBranch: cannot determine default branch — set baseBranch in config or -BaseBranch"
        log_error $msg
        throw $msg
    }
    # refs/remotes/origin/main → main
    return ($ref -replace '^refs/remotes/origin/', '').Trim()
}

# Converts a Feature title to a URL-safe lowercase slug.
# Replaces non-alphanumeric characters with hyphens, collapses runs,
# and strips leading/trailing hyphens.
# Usage: ConvertTo-Slug -Title <title>
# Returns the slug string.
function ConvertTo-Slug {
    param([string]$Title)
    $slug = $Title.ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]', '-'
    $slug = $slug -replace '-+', '-'
    $slug = $slug.Trim('-')
    return $slug
}

# Creates a feature branch named agent/<FeatureId>-<slug> from the base branch
# and pushes it to origin.
# Usage: New-FeatureBranch -FeatureId <id> -FeatureTitle <title>
# Returns the branch name as a string. Throws on failure.
function New-FeatureBranch {
    param(
        [string] $FeatureId,
        [string] $FeatureTitle
    )

    $baseBranch = Get-DefaultBranch
    $slug       = ConvertTo-Slug -Title $FeatureTitle
    $branchName = "agent/$FeatureId-$slug"

    log_info "Creating branch '$branchName' from '$baseBranch'"

    git fetch origin $baseBranch 2>&1 | ForEach-Object { log_info "git: $_" }
    if ($LASTEXITCODE -ne 0) {
        $msg = "New-FeatureBranch: failed to fetch '$baseBranch' from origin"
        log_error $msg
        throw $msg
    }

    # Check if branch already exists locally.
    git show-ref --verify --quiet "refs/heads/$branchName" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        log_info "Branch '$branchName' already exists locally — checking out"
        git checkout $branchName 2>&1 | ForEach-Object { log_info "git: $_" }
    } else {
        git checkout -b $branchName "origin/$baseBranch" 2>&1 | ForEach-Object { log_info "git: $_" }
    }
    if ($LASTEXITCODE -ne 0) {
        $msg = "New-FeatureBranch: failed to create or checkout branch '$branchName'"
        log_error $msg
        throw $msg
    }

    git push -u origin $branchName 2>&1 | ForEach-Object { log_info "git: $_" }
    if ($LASTEXITCODE -ne 0) {
        $msg = "New-FeatureBranch: failed to push '$branchName' to origin"
        log_error $msg
        throw $msg
    }

    log_info "Branch '$branchName' created and pushed to origin"
    return $branchName
}

# Verifies that the working tree is clean (no uncommitted changes) and that
# all commits on the feature branch have been pushed to origin.
# Usage: Test-CleanAndPushed -FeatureBranch <branch>
# Returns $true if both conditions hold, $false otherwise.
function Test-CleanAndPushed {
    param([string] $FeatureBranch)

    $statusOutput = git status --porcelain 2>&1
    if ($statusOutput) {
        log_error "Test-CleanAndPushed: working tree is not clean — uncommitted changes detected"
        log_error ($statusOutput -join "`n")
        return $false
    }

    # Fetch to make sure remote tracking ref is current.
    git fetch origin $FeatureBranch 2>$null | Out-Null

    $unpushed = git log "origin/${FeatureBranch}..HEAD" --oneline 2>&1
    if ($unpushed) {
        log_error "Test-CleanAndPushed: there are unpushed commits on '$FeatureBranch':"
        log_error ($unpushed -join "`n")
        return $false
    }

    return $true
}

# ── Agent dispatcher ───────────────────────────────────────────────────

# Assembles the prompt that will be sent to the AI agent.
# The prompt includes PBI title, description, and acceptance criteria,
# plus instructions to read feature context and signal completion.
# Usage: Build-Prompt -PbiTitle <title> -PbiDescription <desc> -AcceptanceCriteria <ac>
# Returns the assembled prompt string.
function Build-Prompt {
    param(
        [string] $PbiTitle,
        [string] $PbiDescription,
        [string] $AcceptanceCriteria
    )

    return @"
You are an autonomous software development agent implementing a Product Backlog Item (PBI).

## PBI Details

**Title:** $PbiTitle

**Description:**
$PbiDescription

**Acceptance Criteria:**
$AcceptanceCriteria

## Feature Context

Read the file ```.agent-context/feature.md``` in your working directory for additional context about the parent Feature this PBI belongs to.

## Instructions

1. Implement the PBI described above, satisfying all acceptance criteria.
2. Write, edit, and test code as needed using the tools available to you.
3. Commit your changes with a clear commit message referencing the work done.
4. Push the commit to the remote origin. Do NOT create a pull request.
5. When you have finished implementing and pushing all changes, output the exact string ``AGENT_COMPLETE`` on a line by itself to signal completion.
"@
}

# Dispatches the configured AI provider with the given prompt and captures output.
# Returns a hashtable with:
#   ExitCode   — exit code from the agent process
#   Completed  — $true if AGENT_COMPLETE was detected in output, else $false
#   Output     — the captured agent output string
# Throws if the provider value is not recognised.
# Usage: Invoke-Agent -Prompt <string>
function Invoke-Agent {
    param([string] $Prompt)

    $output   = ''
    $exitCode = 0

    switch ($resolvedProvider) {
        'claude-code' {
            $modelArgs = if ($resolvedModel) { @('--model', $resolvedModel) } else { @() }
            try {
                $output = & claude -p $Prompt `
                    --output-format json `
                    @modelArgs `
                    --allowedTools 'Read,Write,Edit,Bash' 2>&1 | Out-String
            } catch {
                $output   = $_.Exception.Message
                $exitCode = 1
            }
            $exitCode = $LASTEXITCODE
        }
        'cursor-cli' {
            try {
                $output = & agent -p $Prompt --force --output-format json 2>&1 | Out-String
            } catch {
                $output   = $_.Exception.Message
                $exitCode = 1
            }
            $exitCode = $LASTEXITCODE
        }
        default {
            $msg = "Invoke-Agent: unknown provider '$resolvedProvider'. Must be 'claude-code' or 'cursor-cli'."
            log_error $msg
            throw $msg
        }
    }

    $completed = $output -match 'AGENT_COMPLETE'

    if ($exitCode -ne 0) {
        log_error "Invoke-Agent: agent exited with non-zero exit code $exitCode"
    }

    return @{
        ExitCode  = $exitCode
        Completed = $completed
        Output    = $output
    }
}

# ── Inner Ralph loop ───────────────────────────────────────────────────

# Inner loop that processes a single PBI through repeated agent invocations
# until the work is verifiably complete or the max iteration limit is hit.
#
# Sets PBI state to "In Progress" before the first invocation. Each iteration
# invokes the agent with a fresh context (no session resumption). The stop
# condition requires BOTH an AGENT_COMPLETE signal AND a clean, fully-pushed
# working tree. On success the PBI is tagged "agent-done"; on exhaustion or
# agent error it is tagged "agent-failed".
#
# Usage: Invoke-ProcessPbi -PbiId <id> -PbiTitle <title> -PbiDescription <desc> -AcceptanceCriteria <ac> -FeatureBranch <branch> -FeatureId <id>
# Returns $true on success, $false on failure.
function Invoke-ProcessPbi {
    param(
        [string] $PbiId,
        [string] $PbiTitle,
        [string] $PbiDescription,
        [string] $AcceptanceCriteria,
        [string] $FeatureBranch,
        [string] $FeatureId
    )

    log_info "Starting inner loop for PBI ${PbiId}: $PbiTitle"

    # Set PBI state to the process-appropriate in-progress state before first agent invocation.
    $inProgressState = Get-InProgressState
    try {
        Update-WorkItemState -WorkItemId $PbiId -State $inProgressState
    } catch {
        log_error "Invoke-ProcessPbi: failed to set PBI $PbiId to '$inProgressState' — aborting"
        return $false
    }

    $prompt = Build-Prompt -PbiTitle $PbiTitle -PbiDescription $PbiDescription -AcceptanceCriteria $AcceptanceCriteria

    for ($iteration = 1; $iteration -le $resolvedMaxIterations; $iteration++) {
        log_info "Iteration ${iteration}/$resolvedMaxIterations for PBI $PbiId"

        $result = Invoke-Agent -Prompt $prompt

        # Capture agent output to the context log for this feature.
        Capture-AgentLog -FeatureId $FeatureId -Output $result.Output

        # Stop condition: AGENT_COMPLETE signal AND clean+pushed working tree.
        if ($result.Completed -and (Test-CleanAndPushed -FeatureBranch $FeatureBranch)) {
            log_info "PBI $PbiId completed successfully after $iteration iteration(s)"
            try { Add-WorkItemTag -WorkItemId $PbiId -Tag 'agent-done' } catch { log_warn "Invoke-ProcessPbi: failed to tag PBI $PbiId as agent-done" }
            return $true
        }

        # If the agent process itself errored, stop retrying immediately.
        if ($result.ExitCode -ne 0) {
            log_error "Invoke-ProcessPbi: agent exited with code $($result.ExitCode) on iteration $iteration — stopping"
            break
        }
    }

    log_error "Invoke-ProcessPbi: PBI $PbiId did not complete within $resolvedMaxIterations iteration(s)"
    try { Add-WorkItemTag -WorkItemId $PbiId -Tag 'agent-failed' } catch { log_warn "Invoke-ProcessPbi: failed to tag PBI $PbiId as agent-failed" }
    return $false
}

try {
    Acquire-Lock
    Ensure-Gitignore

    # Resolve base branch early (auto-detect if not configured) so it is
    # available to both New-FeatureBranch and New-PullRequest.
    $resolvedBaseBranch = Get-DefaultBranch
    log_info "Base branch resolved to '$resolvedBaseBranch'"

    # ── Orchestrator ──────────────────────────────────────────────────────

    log_info "agent-loop started"

    # Step 3/4: Determine the Feature to process
    if ($resolvedFeatureId) {
        # One-shot mode: -FeatureId was supplied
        log_info "One-shot mode: processing Feature $resolvedFeatureId"
        $featureJson = Get-WorkItem -WorkItemId $resolvedFeatureId
        $featureId   = [string]$resolvedFeatureId
    } else {
        # Scheduled mode: pick the first eligible Feature
        log_info "Scheduled mode: querying for eligible Features"
        $eligibleIds = @(Get-EligibleFeatures)
        if ($eligibleIds.Count -eq 0) {
            log_info "No eligible Features found — nothing to do"
            exit 0
        }
        $featureId   = [string]$eligibleIds[0]
        log_info "Selected Feature $featureId for processing"
        $featureJson = Get-WorkItem -WorkItemId $featureId
    }

    $featureTitle       = $featureJson.fields.'System.Title'
    $featureDescription = $featureJson.fields.'System.Description'

    log_info "Processing Feature ${featureId}: $featureTitle"

    # Step 5: Fetch all child PBIs
    log_info "Fetching child PBIs for Feature $featureId"
    $pbis = @(Get-ChildPbis -FeatureId $featureId)

    # Filter to only PBIs tagged "ready-for-agent" in "New" state.
    $pbis = @($pbis | Where-Object {
        $tags  = $_.fields.'System.Tags'
        $state = $_.fields.'System.State'
        ($tags -and $tags -match 'ready-for-agent') -and ($state -eq 'New')
    })

    if ($pbis.Count -eq 0) {
        log_info "Feature $featureId has no eligible child PBIs (ready-for-agent + New) — nothing to do"
        exit 0
    }
    log_info "Found $($pbis.Count) eligible PBI(s) for Feature $featureId"

    # Step 6: Topologically sort PBIs by dependency
    log_info "Sorting PBIs by dependency order"
    $sortedPbis = @(Sort-PbisByDependency -Pbis $pbis)

    # Step 7: Create feature branch
    log_info "Creating feature branch for Feature $featureId"
    $featureBranch = New-FeatureBranch -FeatureId $featureId -FeatureTitle $featureTitle

    # Step 8: Write Feature PRD to .agent-context/feature.md
    $featureContext = "# Feature: $featureTitle`n`n## Description`n$featureDescription"
    Write-FeatureContext -FeatureId $featureId -Content $featureContext

    # Step 9/10: Process each PBI serially; stop on first failure
    $featureSuccess = $true
    foreach ($pbi in $sortedPbis) {
        $pbiId          = [string]$pbi.id
        $pbiTitle       = $pbi.fields.'System.Title'
        $pbiDescription = $pbi.fields.'System.Description'
        $pbiAc          = $pbi.fields.'Microsoft.VSTS.Common.AcceptanceCriteria'

        log_info "Starting PBI ${pbiId}: $pbiTitle"

        $ok = Invoke-ProcessPbi `
            -PbiId              $pbiId `
            -PbiTitle           ($pbiTitle       ?? '') `
            -PbiDescription     ($pbiDescription ?? '') `
            -AcceptanceCriteria ($pbiAc          ?? '') `
            -FeatureBranch      $featureBranch `
            -FeatureId          $featureId

        if (-not $ok) {
            log_error "PBI $pbiId failed — skipping remaining PBIs for Feature $featureId"
            $featureSuccess = $false
            break
        }

        log_info "PBI $pbiId completed"
    }

    # Step 11: Create PR only when all PBIs are tagged agent-done
    if ($featureSuccess) {
        log_info "All PBIs completed — creating pull request for Feature $featureId"
        $prUrl = New-PullRequest -FeatureTitle $featureTitle -FeatureBranch $featureBranch -Pbis $sortedPbis
        log_info "Feature $featureId complete — PR: $prUrl"
        exit 0
    } else {
        log_error "Feature $featureId processing failed — one or more PBIs did not complete"
        exit 1
    }
} finally {
    Release-Lock
    Invoke-Cleanup
}
