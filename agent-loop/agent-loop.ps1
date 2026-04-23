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
  AI provider: claude-code, cursor, or cursor-cli

.PARAMETER Model
  Model ID to use (e.g. claude-opus-4-6)

.PARAMETER WorkingDirectory
  Working directory containing the repo

.PARAMETER FeatureId
  ADO Feature ID to process (optional; processes all if omitted)

.NOTES
  Required environment variables:
    AZURE_DEVOPS_PAT     — Azure DevOps Personal Access Token
    ANTHROPIC_API_KEY    — Optional when -Provider is claude-code;
                           if set, Claude Code uses API-key auth instead of
                           the signed-in Claude session
    CURSOR_API_KEY       — Optional when -Provider is cursor/cursor-cli;
                           if omitted, the signed-in Cursor session is used
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
    [string] $SystemLogDirectory,
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
    Write-Warning "[$ts] [WARN] $Message"
}

function log_error {
    param([string]$Message)
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    # Keep error logs non-terminating so callers can decide whether to throw,
    # retry, tag a PBI as failed, or continue to cleanup.
    Write-Error "[$ts] [ERROR] $Message" -ErrorAction Continue
}

function Format-CommandArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return "''"
    }

    if ($Value -match '[\s"`$]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Write-CommandLog {
    param(
        [string]$Prefix,
        [string[]]$Arguments
    )

    $formatted = @($Arguments | ForEach-Object { Format-CommandArgument $_ }) -join ' '
    log_info "$Prefix $formatted"
}

function Get-DefaultSystemLogDirectory {
    if ($IsMacOS) {
        return (Join-Path $HOME 'Library/Logs/agent-loop')
    }

    if ($IsLinux) {
        $stateHome = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME '.local/state' }
        return (Join-Path $stateHome 'agent-loop/logs')
    }

    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'agent-loop/logs')
    }

    return (Join-Path $HOME '.agent-loop/logs')
}

# ── Load config file ──────────────────────────────────────────────────
# Config can live alongside this script and/or in the target repo working directory.
$configDirectory = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    (Get-Location).Path
}

$fileConfig = @{}

function Import-ConfigFile {
    param(
        [string]$ConfigFilePath,
        [hashtable]$Config
    )

    if (-not (Test-Path $ConfigFilePath)) {
        return
    }

    try {
        $json = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
        if ($null -ne $json.organizationUrl) { $Config['Org']              = $json.organizationUrl }
        if ($null -ne $json.project)         { $Config['Project']          = $json.project }
        if ($null -ne $json.areaPath)        { $Config['AreaPath']         = $json.areaPath }
        if ($null -ne $json.team)            { $Config['Team']             = $json.team }
        if ($null -ne $json.process)         { $Config['Process']          = $json.process }
        if ($null -ne $json.repositoryUrl)   { $Config['RepoUrl']          = $json.repositoryUrl }
        if ($null -ne $json.baseBranch)      { $Config['BaseBranch']       = $json.baseBranch }
        if ($null -ne $json.maxIterationsPerPbi) { $Config['MaxIterations'] = $json.maxIterationsPerPbi }
        if ($null -ne $json.provider)        { $Config['Provider']         = $json.provider }
        if ($null -ne $json.model)           { $Config['Model']            = $json.model }
        if ($null -ne $json.workingDirectory) { $Config['WorkingDirectory'] = $json.workingDirectory }
        if ($null -ne $json.systemLogDirectory) { $Config['SystemLogDirectory'] = $json.systemLogDirectory }
        if ($null -ne $json.featureId)       { $Config['FeatureId']        = [string]$json.featureId }
    } catch {
        Write-Error "Error: Failed to parse ${ConfigFilePath}: $_"
        exit 1
    }
}

$scriptConfigFile = Join-Path $configDirectory '.agent-loop.json'
Import-ConfigFile -ConfigFilePath $scriptConfigFile -Config $fileConfig

$candidateWorkingDir = if ($WorkingDirectory) {
    $WorkingDirectory
} elseif ($fileConfig.ContainsKey('WorkingDirectory') -and $fileConfig['WorkingDirectory']) {
    $fileConfig['WorkingDirectory']
} elseif ($env:AGENT_LOOP_WORKING_DIRECTORY) {
    $env:AGENT_LOOP_WORKING_DIRECTORY
} else {
    (Get-Location).Path
}

if ($candidateWorkingDir) {
    $workingConfigFile = Join-Path $candidateWorkingDir '.agent-loop.json'
    $sameConfigFile = [System.StringComparer]::OrdinalIgnoreCase.Equals(
        [System.IO.Path]::GetFullPath($scriptConfigFile),
        [System.IO.Path]::GetFullPath($workingConfigFile)
    )

    if (-not $sameConfigFile) {
        Import-ConfigFile -ConfigFilePath $workingConfigFile -Config $fileConfig
    }
}

# ── Merge: CLI wins over config file ─────────────────────────────────
function Resolve-Value {
    param($cliValue, $configKey, $default = $null)
    if ($cliValue -and $cliValue -ne 0) { return $cliValue }
    if ($fileConfig.ContainsKey($configKey) -and $fileConfig[$configKey]) { return $fileConfig[$configKey] }
    return $default
}

function Resolve-ProviderName {
    param([string]$ProviderValue)

    if (-not $ProviderValue) {
        return $ProviderValue
    }

    switch ($ProviderValue.Trim().ToLowerInvariant()) {
        'cursor' { return 'cursor-cli' }
        'cursor-cli' { return 'cursor-cli' }
        'claude-code' { return 'claude-code' }
        default { return $ProviderValue }
    }
}

function Resolve-CursorModel {
    param(
        [string]$ProviderValue,
        [string]$ModelValue
    )

    if ($ProviderValue -ne 'cursor-cli' -or -not $ModelValue) {
        return $ModelValue
    }

    $cursorModelAliases = @{
        'claude-opus-4-6' = 'claude-4.6-opus-high-thinking'
    }

    if ($cursorModelAliases.ContainsKey($ModelValue)) {
        $normalizedModel = $cursorModelAliases[$ModelValue]
        log_info "Normalizing Cursor model '$ModelValue' to '$normalizedModel'."
        return $normalizedModel
    }

    return $ModelValue
}

$resolvedOrg            = Resolve-Value $Org           'Org'
$resolvedProject        = Resolve-Value $Project       'Project'
$resolvedAreaPath       = Resolve-Value $AreaPath      'AreaPath'
$resolvedTeam           = Resolve-Value $Team          'Team'
$resolvedProcess        = Resolve-Value $Process       'Process'
$resolvedRepoUrl        = Resolve-Value $RepoUrl       'RepoUrl'
$resolvedBaseBranch     = Resolve-Value $BaseBranch    'BaseBranch'    $null
$resolvedMaxIterations  = Resolve-Value $MaxIterations 'MaxIterations' 5
$resolvedProvider       = Resolve-ProviderName (Resolve-Value $Provider 'Provider')
$resolvedModel          = Resolve-Value $Model         'Model'
$resolvedFeatureId      = Resolve-Value $FeatureId     'FeatureId'
$resolvedSystemLogDir   = Resolve-Value $SystemLogDirectory 'SystemLogDirectory'
$resolvedWorkingDir     = if ($WorkingDirectory) {
    $WorkingDirectory
} elseif ($fileConfig.ContainsKey('WorkingDirectory') -and $fileConfig['WorkingDirectory']) {
    $fileConfig['WorkingDirectory']
} elseif ($env:AGENT_LOOP_WORKING_DIRECTORY) {
    $env:AGENT_LOOP_WORKING_DIRECTORY
} else {
    (Get-Location).Path
}

$resolvedModel = Resolve-CursorModel $resolvedProvider $resolvedModel

if (-not $resolvedSystemLogDir) {
    $resolvedSystemLogDir = if ($env:AGENT_LOOP_SYSTEM_LOG_DIR) { $env:AGENT_LOOP_SYSTEM_LOG_DIR } else { Get-DefaultSystemLogDirectory }
}

# ── Validate required values ──────────────────────────────────────────
$errors = [System.Collections.Generic.List[string]]::new()

if (-not $resolvedOrg)      { $errors.Add('Missing required value: -Org (Azure DevOps org URL)') }
if (-not $resolvedProject)  { $errors.Add('Missing required value: -Project (Azure DevOps project name)') }
if (-not $resolvedProvider) { $errors.Add('Missing required value: -Provider (claude-code, cursor, or cursor-cli)') }

if ($errors.Count -gt 0) {
    Write-Host 'Error: Configuration is incomplete:' -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'Provide values via CLI parameters or .agent-loop.json next to the script and/or in the working directory.' -ForegroundColor Yellow
    Write-Host 'See .agent-loop.example.json for the full schema.' -ForegroundColor Yellow
    exit 1
}

# ── Validate provider value ───────────────────────────────────────────
if ($resolvedProvider -notin @('claude-code', 'cursor-cli')) {
    Write-Host "Error: Invalid provider '$resolvedProvider'. Must be 'claude-code', 'cursor', or 'cursor-cli'." -ForegroundColor Red
    exit 1
}

if ($resolvedMaxIterations -lt 1) {
    Write-Host 'Error: -MaxIterations must be a positive integer.' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $resolvedWorkingDir -PathType Container)) {
    Write-Host "Error: working directory does not exist: $resolvedWorkingDir" -ForegroundColor Red
    exit 1
}

$resolvedWorkingDir = (Resolve-Path $resolvedWorkingDir).Path

if (-not (Test-Path $resolvedSystemLogDir -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedSystemLogDir -Force | Out-Null
}

$resolvedSystemLogDir = (Resolve-Path $resolvedSystemLogDir).Path

# ── Validate environment variables ───────────────────────────────────
$envErrors = [System.Collections.Generic.List[string]]::new()

if (-not $env:AZURE_DEVOPS_PAT) {
    $envErrors.Add('Missing required environment variable: AZURE_DEVOPS_PAT')
}

if ($resolvedProvider -eq 'claude-code') {
    if ($env:ANTHROPIC_API_KEY) {
        log_warn 'ANTHROPIC_API_KEY is set; Claude Code will use API-key auth instead of the signed-in Claude session.'
    } elseif ($env:CLAUDE_CODE_OAUTH_TOKEN) {
        log_info 'CLAUDE_CODE_OAUTH_TOKEN detected; Claude Code will use OAuth token auth.'
    } else {
        log_info 'Claude Code will use the signed-in Claude session. Run `claude` and complete login first if needed.'
    }
}

if ($resolvedProvider -eq 'cursor-cli' -and -not $env:CURSOR_API_KEY) {
    log_info 'CURSOR_API_KEY not set; Cursor Agent will use the signed-in Cursor session.'
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
$env:AGENT_LOOP_SYSTEM_LOG_DIR    = $resolvedSystemLogDir
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
Write-Host "  System logs:     $resolvedSystemLogDir"
Write-Host ('=' * 54)

# ── Lock manager ──────────────────────────────────────────────────────
$lockFile = Join-Path $resolvedWorkingDir '.agent-loop.lock'
$script:lockAcquired = $false

function Acquire-Lock {
    try {
        $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $writer = [System.IO.StreamWriter]::new($stream)
        $writer.Write([string]$PID)
        $writer.Flush()
        $writer.Dispose()
        $stream.Dispose()
    } catch {
        log_warn "Another instance is already running (lock file exists: $lockFile). Exiting."
        return $false
    }
    $script:lockAcquired = $true
    log_info "Lock acquired: $lockFile"
    return $true
}

function Release-Lock {
    if ($script:lockAcquired -and (Test-Path $lockFile) -and ((Get-Content $lockFile -Raw).Trim() -eq [string]$PID)) {
        Remove-Item -Force $lockFile
        log_info "Lock released: $lockFile"
    }
}

# ── Context manager ───────────────────────────────────────────────────
$agentContextDir = Join-Path $resolvedWorkingDir '.agent-context'
$script:currentFeatureLogFile = $null

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
    if ($script:currentFeatureLogFile) {
        Add-Content -Path $script:currentFeatureLogFile -Value $Output
    }
}

function Start-FeatureLog {
    param([string]$FeatureId, [string]$FeatureTitle)
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $script:currentFeatureLogFile = Join-Path $resolvedSystemLogDir "feature-${FeatureId}-${timestamp}.log"
    @(
        "Feature ID: $FeatureId"
        "Feature Title: $FeatureTitle"
        "Started At (UTC): $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))"
        "Working Directory: $resolvedWorkingDir"
        "Provider: $resolvedProvider$(if ($resolvedModel) { " ($resolvedModel)" } else { '' })"
        ''
    ) | Set-Content -Path $script:currentFeatureLogFile
    log_info "Persistent agent log: $($script:currentFeatureLogFile)"
}

function Add-FeatureLogNote {
    param([string]$Message)
    if ($script:currentFeatureLogFile) {
        Add-Content -Path $script:currentFeatureLogFile -Value "[$((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))] $Message"
    }
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
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        if ($Body) {
            log_info "ADO request: Invoke-RestMethod -Method $Method -Uri '$Url' -ContentType '$ContentType' -Body $Body"
        } else {
            log_info "ADO request: Invoke-RestMethod -Method $Method -Uri '$Url' -ContentType '$ContentType'"
        }

        if ($Body) {
            return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $Body
        } else {
            return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers
        }
    } catch {
        $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 'n/a' }
        $errorBody  = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        log_error "ADO API error: HTTP $statusCode — $Method $Url"
        log_error "Response: $errorBody"
        throw
    } finally {
        $ProgressPreference = $previousProgressPreference
    }
}

function Get-WorkItemFieldValue {
    param(
        $Fields,
        [string] $FieldName,
        $DefaultValue = ''
    )

    if ($null -eq $Fields) {
        return $DefaultValue
    }

    $property = $Fields.PSObject.Properties[$FieldName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value
}

# Queries ADO for Features that have at least one child PBI tagged
# "ready-for-agent" in "New" state, scoped to the configured AreaPath.
# Returns an array of Feature IDs (integers).
function Get-EligibleFeatures {
    $wiql = "SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.WorkItemType] = 'Feature'"
    if ($resolvedAreaPath) {
        $escapedAreaPath = $resolvedAreaPath -replace "'", "''"
        $wiql += " AND [Source].[System.AreaPath] UNDER '$escapedAreaPath'"
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
# Scrum PBIs → "Committed"; Agile/CMMI PBIs → "Active"; unknown → "In Progress".
function Get-InProgressState {
    switch ($resolvedProcess) {
        'Scrum'                        { return 'Committed' }
        { $_ -in @('Agile', 'CMMI') }  { return 'Active' }
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
    $currentWorkItem = Get-WorkItem -WorkItemId $WorkItemId
    $currentState = Get-WorkItemFieldValue -Fields $currentWorkItem.fields -FieldName 'System.State' -DefaultValue ''
    if ($currentState -eq $State) {
        log_info "Work item $WorkItemId is already in state '$State'"
        return
    }

    $patchDoc = ConvertTo-Json -InputObject @(
        @{ op = 'replace'; path = '/fields/System.State'; value = $State }
    ) -Compress
    $url = "$resolvedOrg/$resolvedProject/_apis/wit/workitems/${WorkItemId}?api-version=7.1"

    try {
        Invoke-AdoApi -Method PATCH -Url $url -Body $patchDoc -ContentType 'application/json-patch+json' | Out-Null
        log_info "Work item $WorkItemId state set to '$State'"
    } catch {
        $refreshedWorkItem = Get-WorkItem -WorkItemId $WorkItemId
        $refreshedState = Get-WorkItemFieldValue -Fields $refreshedWorkItem.fields -FieldName 'System.State' -DefaultValue ''
        if ($refreshedState -eq $State) {
            log_warn "Work item $WorkItemId was updated to '$State' by another process; continuing"
            return
        }

        throw
    }
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
    $currentTags = Get-WorkItemFieldValue -Fields $workItem.fields -FieldName 'System.Tags' -DefaultValue ''
    $tagList     = if ($currentTags) { @($currentTags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
    if ($tagList -contains $Tag) {
        log_info "Tag '$Tag' already present on work item $WorkItemId"
        return
    }
    $newTags     = if ($currentTags) { "$currentTags; $Tag" } else { $Tag }
    $op          = if ($currentTags) { 'replace' } else { 'add' }

    $patchDoc = ConvertTo-Json -InputObject @(
        @{ op = $op; path = '/fields/System.Tags'; value = $newTags }
    ) -Compress
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

    $repoUrlForPr = $resolvedRepoUrl

    try {
        Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'remote', 'get-url', 'origin')
        $originRepoUrl = (git remote get-url origin 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $originRepoUrl) {
            $repoUrlForPr = $originRepoUrl.Trim()
        }
    } catch {
        # Fall back to configured RepoUrl when git remote inspection fails.
    }

    if (-not $repoUrlForPr) {
        log_error "New-PullRequest: RepoUrl is not set and origin remote could not be resolved"
        throw "RepoUrl is required for PR creation"
    }

    try {
        $repoUri = [Uri]$repoUrlForPr
    } catch {
        log_error "New-PullRequest: RepoUrl '$repoUrlForPr' is not a valid absolute URI"
        throw "Could not parse repository URL"
    }

    $repoPathParts = @($repoUri.AbsolutePath.Trim('/') -split '/')
    if ($repoPathParts.Count -lt 4 -or $repoPathParts[2] -ne '_git') {
        log_error "New-PullRequest: unable to parse repository project/name from RepoUrl='$repoUrlForPr'"
        throw "Could not parse repository project/name from RepoUrl"
    }

    $repoProject    = $repoPathParts[1]
    $repoNameFromUrl = $repoPathParts[3]

    if (-not $repoProject -or -not $repoNameFromUrl) {
        log_error "New-PullRequest: parsed invalid repository context from RepoUrl='$repoUrlForPr'"
        throw "Could not parse repository context from RepoUrl"
    }

    $repoProjectEscaped = [Uri]::EscapeDataString($repoProject)
    $repoNameCandidates = @(
        $repoNameFromUrl
        ($repoNameFromUrl -replace '\.git$', '')
    ) | Where-Object { $_ } | Select-Object -Unique

    $repoListUrl = "$resolvedOrg/$repoProjectEscaped/_apis/git/repositories?api-version=7.1"
    $repoList    = @(Invoke-AdoApi -Method GET -Url $repoListUrl).value
    $repo        = $repoList | Where-Object {
        $candidateNames = @(
            [string]$_.name
            (([string]$_.name) -replace '\.git$', '')
        ) | Where-Object { $_ } | Select-Object -Unique

        @($candidateNames | Where-Object { $repoNameCandidates -contains $_ }).Count -gt 0
    } | Select-Object -First 1

    if (-not $repo) {
        log_error "New-PullRequest: unable to resolve repository metadata for RepoUrl='$repoUrlForPr'"
        throw "Could not resolve repository metadata from RepoUrl"
    }

    $repoId         = [string]$repo.id
    $repoName       = [string]$repo.name
    $repoIdEscaped  = [Uri]::EscapeDataString($repoId)
    $repoNameEscaped = [Uri]::EscapeDataString($repoName)

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

    $url      = "$resolvedOrg/$repoProjectEscaped/_apis/git/repositories/$repoIdEscaped/pullrequests?api-version=7.1"
    $response = Invoke-AdoApi -Method POST -Url $url -Body $body

    $prId     = $response.pullRequestId
    $prWebUrl = "$resolvedOrg/$repoProjectEscaped/_git/$repoNameEscaped/pullrequest/$prId"
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

    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'symbolic-ref', 'refs/remotes/origin/HEAD')
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

    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'fetch', 'origin', $baseBranch)
    git fetch origin $baseBranch 2>&1 | ForEach-Object { log_info "git: $_" }
    if ($LASTEXITCODE -ne 0) {
        $msg = "New-FeatureBranch: failed to fetch '$baseBranch' from origin"
        log_error $msg
        throw $msg
    }

    # Check if branch already exists locally.
    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'show-ref', '--verify', '--quiet', "refs/heads/$branchName")
    git show-ref --verify --quiet "refs/heads/$branchName" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        log_info "Branch '$branchName' already exists locally — checking out"
        Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'checkout', $branchName)
        git checkout $branchName 2>&1 | ForEach-Object { log_info "git: $_" }
    } else {
        Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'checkout', '-b', $branchName, "origin/$baseBranch")
        git checkout -b $branchName "origin/$baseBranch" 2>&1 | ForEach-Object { log_info "git: $_" }
    }
    if ($LASTEXITCODE -ne 0) {
        $msg = "New-FeatureBranch: failed to create or checkout branch '$branchName'"
        log_error $msg
        throw $msg
    }

    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'push', '-u', 'origin', $branchName)
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

    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'status', '--porcelain')
    $statusOutput = git status --porcelain 2>&1
    if ($statusOutput) {
        log_error "Test-CleanAndPushed: working tree is not clean — uncommitted changes detected"
        log_error ($statusOutput -join "`n")
        return $false
    }

    # Fetch to make sure remote tracking ref is current.
    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'fetch', 'origin', $FeatureBranch)
    git fetch origin $FeatureBranch 2>$null | Out-Null

    Write-CommandLog -Prefix 'Running:' -Arguments @('git', 'log', "origin/${FeatureBranch}..HEAD", '--oneline')
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

# Recursively checks raw or JSON-parsed agent output for the exact
# AGENT_COMPLETE token on its own line.
function Test-AgentCompletionValue {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [string]) {
        return [regex]::IsMatch($Value, '(?m)^\s*AGENT_COMPLETE\s*$')
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($entry in $Value.GetEnumerator()) {
            if (Test-AgentCompletionValue -Value $entry.Value) {
                return $true
            }
        }

        return $false
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            if (Test-AgentCompletionValue -Value $item) {
                return $true
            }
        }

        return $false
    }

    foreach ($property in $Value.PSObject.Properties) {
        if (Test-AgentCompletionValue -Value $property.Value) {
            return $true
        }
    }

    return $false
}

# Detects AGENT_COMPLETE in either raw text output or JSON output emitted by
# Cursor/Claude CLIs when --output-format json is enabled.
function Test-AgentCompleted {
    param([string] $Output)

    if (-not $Output) {
        return $false
    }

    if (Test-AgentCompletionValue -Value $Output) {
        return $true
    }

    $jsonCandidates = @($Output)
    $jsonCandidates += @(
        $Output -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    foreach ($candidate in ($jsonCandidates | Select-Object -Unique)) {
        try {
            $parsed = $candidate | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            continue
        }

        if (Test-AgentCompletionValue -Value $parsed) {
            return $true
        }
    }

    return $false
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
                $exitCode = $LASTEXITCODE
            } catch {
                $output   = $_.Exception.Message
                $exitCode = 1
            }
        }
        'cursor-cli' {
            $modelArgs = if ($resolvedModel) { @('--model', $resolvedModel) } else { @() }
            try {
                $output = & agent -p $Prompt `
                    --force `
                    --trust `
                    --workspace $resolvedWorkingDir `
                    --output-format json `
                    @modelArgs 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            } catch {
                $output   = $_.Exception.Message
                $exitCode = 1
            }
        }
        default {
            $msg = "Invoke-Agent: unknown provider '$resolvedProvider'. Must be 'claude-code', 'cursor', or 'cursor-cli'."
            log_error $msg
            throw $msg
        }
    }

    $completed = Test-AgentCompleted -Output $output

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
    Set-Location $resolvedWorkingDir

    if (-not (Acquire-Lock)) {
        exit 0
    }
    Ensure-Gitignore

    # Resolve base branch early (auto-detect if not configured) so it is
    # available to both New-FeatureBranch and New-PullRequest.
    $resolvedBaseBranch = Get-DefaultBranch
    $env:AGENT_LOOP_BASE_BRANCH = $resolvedBaseBranch
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

    $featureType = [string]$featureJson.fields.'System.WorkItemType'
    if ($featureType -ne 'Feature') {
        log_error "Work item $featureId is a '$featureType', not a Feature"
        exit 1
    }

    $featureTitle       = $featureJson.fields.'System.Title'
    $featureDescription = Get-WorkItemFieldValue -Fields $featureJson.fields -FieldName 'System.Description' -DefaultValue ''

    log_info "Processing Feature ${featureId}: $featureTitle"
    Start-FeatureLog -FeatureId $featureId -FeatureTitle $featureTitle
    Add-FeatureLogNote -Message 'Feature processing started'

    # Step 5: Fetch all child PBIs
    log_info "Fetching child PBIs for Feature $featureId"
    $allChildPbis = @(Get-ChildPbis -FeatureId $featureId)

    # Track all ready-for-agent PBIs for feature-level completion/PR creation,
    # then separately derive the subset still pending and runnable.
    $runnableStates = @('New', (Get-InProgressState))
    $readyForAgentPbis = @($allChildPbis | Where-Object {
        $tags = Get-WorkItemFieldValue -Fields $_.fields -FieldName 'System.Tags' -DefaultValue ''
        $tagList = if ($tags) {
            @($tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else {
            @()
        }
        ($tagList -contains 'ready-for-agent')
    })

    if ($readyForAgentPbis.Count -eq 0) {
        log_info "Feature $featureId has no ready-for-agent child PBIs — nothing to do"
        exit 0
    }

    $remainingReadyForAgentPbis = @($readyForAgentPbis | Where-Object {
        $tags = Get-WorkItemFieldValue -Fields $_.fields -FieldName 'System.Tags' -DefaultValue ''
        $tagList = if ($tags) {
            @($tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else {
            @()
        }
        (-not ($tagList -contains 'agent-done'))
    })

    $pbis = @($remainingReadyForAgentPbis | Where-Object {
        $tags = Get-WorkItemFieldValue -Fields $_.fields -FieldName 'System.Tags' -DefaultValue ''
        $tagList = if ($tags) {
            @($tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else {
            @()
        }
        $state = Get-WorkItemFieldValue -Fields $_.fields -FieldName 'System.State' -DefaultValue ''
        (($tagList -contains 'ready-for-agent') -and (-not ($tagList -contains 'agent-done')) -and ($runnableStates -contains $state))
    })

    log_info "Sorting PR PBIs by dependency order"
    $prPbis = @(Sort-PbisByDependency -Pbis $readyForAgentPbis)

    if ($pbis.Count -eq 0) {
        if ($remainingReadyForAgentPbis.Count -eq 0) {
            log_info "All ready-for-agent PBIs are already tagged agent-done — continuing to pull request creation"
            $sortedPbis = @()
        } else {
            log_info "Feature $featureId has no eligible child PBIs (ready-for-agent + not agent-done + runnable state) — nothing to do"
            exit 0
        }
    } else {
        log_info "Found $($pbis.Count) eligible PBI(s) for Feature $featureId"

        # Step 6: Topologically sort PBIs by dependency
        log_info "Sorting PBIs by dependency order"
        $sortedPbis = @(Sort-PbisByDependency -Pbis $pbis)
    }

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
        $pbiDescription = Get-WorkItemFieldValue -Fields $pbi.fields -FieldName 'System.Description' -DefaultValue ''
        $pbiAc          = Get-WorkItemFieldValue -Fields $pbi.fields -FieldName 'Microsoft.VSTS.Common.AcceptanceCriteria' -DefaultValue ''

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
        try {
            $prUrl = New-PullRequest -FeatureTitle $featureTitle -FeatureBranch $featureBranch -Pbis $prPbis
        } catch {
            Add-FeatureLogNote -Message 'Failed to create pull request'
            throw
        }
        Add-FeatureLogNote -Message "Feature completed successfully. Pull request: $prUrl"
        log_info "Feature $featureId complete — PR: $prUrl"
        exit 0
    } else {
        Add-FeatureLogNote -Message 'Feature processing failed'
        log_error "Feature $featureId processing failed — one or more PBIs did not complete"
        exit 1
    }
} finally {
    Release-Lock
    Invoke-Cleanup
}
