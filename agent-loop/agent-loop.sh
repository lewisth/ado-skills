#!/bin/bash
set -e

# ── agent-loop.sh ─────────────────────────────────────────────────────
# Autonomous ADO feature implementation loop.
# Reads config from .agent-loop.json in the working directory and/or
# CLI parameters (CLI wins). Validates all required values before running.

# ── Config defaults ───────────────────────────────────────────────────
CONFIG_ORG=""
CONFIG_PROJECT=""
CONFIG_AREA_PATH=""
CONFIG_TEAM=""
CONFIG_PROCESS=""
CONFIG_REPO_URL=""
CONFIG_BASE_BRANCH=""
CONFIG_MAX_ITERATIONS=""
CONFIG_PROVIDER=""
CONFIG_MODEL=""
CONFIG_WORKING_DIRECTORY=""
CONFIG_SYSTEM_LOG_DIRECTORY=""
CONFIG_FEATURE_ID=""

# ── CLI parameter parsing ─────────────────────────────────────────────
CLI_ORG=""
CLI_PROJECT=""
CLI_AREA_PATH=""
CLI_TEAM=""
CLI_PROCESS=""
CLI_REPO_URL=""
CLI_BASE_BRANCH=""
CLI_MAX_ITERATIONS=""
CLI_PROVIDER=""
CLI_MODEL=""
CLI_WORKING_DIRECTORY=""
CLI_SYSTEM_LOG_DIRECTORY=""
CLI_FEATURE_ID=""

# ── Logging ───────────────────────────────────────────────────────────
log_info() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

print_usage() {
  cat <<EOF
Usage: agent-loop.sh [OPTIONS]

Options:
  --org <url>               Azure DevOps org URL (e.g. https://dev.azure.com/contoso)
  --project <name>          Azure DevOps project name
  --area-path <path>        Work item area path (e.g. "MyProject\\Team A")
  --team <name>             Azure DevOps team name
  --process <template>      Process template: Scrum, Agile, or CMMI
  --repo-url <url>          Git repository URL
  --base-branch <branch>    Base branch (auto-detected from git if omitted)
  --max-iterations <n>      Max PBIs to process this run (default: 1)
  --provider <name>         AI provider: claude-code, cursor, or cursor-cli
  --model <id>              Model ID to use (e.g. claude-opus-4-6)
  --working-directory <dir> Working directory containing the repo
  --system-log-directory <dir>
                            Persistent system-level directory for retained agent logs
  --feature-id <id>         ADO Feature ID to process (optional; processes all if omitted)

Environment variables:
  AZURE_DEVOPS_PAT          Required. Azure DevOps Personal Access Token.
  ANTHROPIC_API_KEY         Optional when --provider is claude-code;
                            if set, Claude Code uses API-key auth instead of
                            the signed-in Claude session.
  CURSOR_API_KEY            Optional when --provider is cursor/cursor-cli;
                            if omitted, the signed-in Cursor session is used.

Config file:
  .agent-loop.json          Optional JSON config in the working directory.
                            CLI parameters override config file values.
EOF
}

require_option_value() {
  local option="$1"
  local value="${2-}"
  if [ -z "$value" ] || [[ "$value" == --* ]]; then
    echo "Error: $option requires a value." >&2
    print_usage >&2
    exit 1
  fi
}

resolve_system_log_directory() {
  case "$(uname -s)" in
    Darwin) printf '%s\n' "${HOME}/Library/Logs/agent-loop" ;;
    Linux)  printf '%s\n' "${XDG_STATE_HOME:-${HOME}/.local/state}/agent-loop/logs" ;;
    *)      printf '%s\n' "${HOME}/.agent-loop/logs" ;;
  esac
}

normalize_provider_name() {
  local provider_value="$1"

  case "${provider_value,,}" in
    cursor|cursor-cli) printf '%s\n' "cursor-cli" ;;
    claude-code) printf '%s\n' "claude-code" ;;
    *) printf '%s\n' "$provider_value" ;;
  esac
}

normalize_cursor_model() {
  local provider_value="$1"
  local model_value="$2"

  if [ "$provider_value" != "cursor-cli" ] || [ -z "$model_value" ]; then
    printf '%s\n' "$model_value"
    return 0
  fi

  case "$model_value" in
    claude-opus-4-6)
      log_info "Normalizing Cursor model '$model_value' to 'claude-4.6-opus-high-thinking'."
      printf '%s\n' "claude-4.6-opus-high-thinking"
      ;;
    *)
      printf '%s\n' "$model_value"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)              require_option_value "$1" "${2-}"; CLI_ORG="$2";                shift 2 ;;
    --project)          require_option_value "$1" "${2-}"; CLI_PROJECT="$2";            shift 2 ;;
    --area-path)        require_option_value "$1" "${2-}"; CLI_AREA_PATH="$2";          shift 2 ;;
    --team)             require_option_value "$1" "${2-}"; CLI_TEAM="$2";               shift 2 ;;
    --process)          require_option_value "$1" "${2-}"; CLI_PROCESS="$2";            shift 2 ;;
    --repo-url)         require_option_value "$1" "${2-}"; CLI_REPO_URL="$2";           shift 2 ;;
    --base-branch)      require_option_value "$1" "${2-}"; CLI_BASE_BRANCH="$2";        shift 2 ;;
    --max-iterations)   require_option_value "$1" "${2-}"; CLI_MAX_ITERATIONS="$2";     shift 2 ;;
    --provider)         require_option_value "$1" "${2-}"; CLI_PROVIDER="$2";           shift 2 ;;
    --model)            require_option_value "$1" "${2-}"; CLI_MODEL="$2";              shift 2 ;;
    --working-directory) require_option_value "$1" "${2-}"; CLI_WORKING_DIRECTORY="$2"; shift 2 ;;
    --system-log-directory) require_option_value "$1" "${2-}"; CLI_SYSTEM_LOG_DIRECTORY="$2"; shift 2 ;;
    --feature-id)       require_option_value "$1" "${2-}"; CLI_FEATURE_ID="$2";         shift 2 ;;
    --help|-h)          print_usage; exit 0 ;;
    *)
      echo "Error: Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# ── Load config file ──────────────────────────────────────────────────
import_config_file() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required to parse .agent-loop.json. Install with: brew install jq / sudo apt install jq" >&2
    exit 1
  fi

  CONFIG_ORG=$(jq -r '.organizationUrl // empty' "$config_file" 2>/dev/null || true)
  CONFIG_PROJECT=$(jq -r '.project // empty' "$config_file" 2>/dev/null || true)
  CONFIG_AREA_PATH=$(jq -r '.areaPath // empty' "$config_file" 2>/dev/null || true)
  CONFIG_TEAM=$(jq -r '.team // empty' "$config_file" 2>/dev/null || true)
  CONFIG_PROCESS=$(jq -r '.process // empty' "$config_file" 2>/dev/null || true)
  CONFIG_REPO_URL=$(jq -r '.repositoryUrl // empty' "$config_file" 2>/dev/null || true)
  CONFIG_BASE_BRANCH=$(jq -r '.baseBranch // empty' "$config_file" 2>/dev/null || true)
  CONFIG_MAX_ITERATIONS=$(jq -r '.maxIterationsPerPbi // empty' "$config_file" 2>/dev/null || true)
  CONFIG_PROVIDER=$(jq -r '.provider // empty' "$config_file" 2>/dev/null || true)
  CONFIG_MODEL=$(jq -r '.model // empty' "$config_file" 2>/dev/null || true)
  CONFIG_WORKING_DIRECTORY=$(jq -r '.workingDirectory // empty' "$config_file" 2>/dev/null || true)
  CONFIG_SYSTEM_LOG_DIRECTORY=$(jq -r '.systemLogDirectory // empty' "$config_file" 2>/dev/null || true)
  CONFIG_FEATURE_ID=$(jq -r '.featureId // empty' "$config_file" 2>/dev/null || true)
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_CONFIG_FILE="$SCRIPT_DIR/.agent-loop.json"
import_config_file "$SCRIPT_CONFIG_FILE"

CANDIDATE_WORKING_DIR="${CLI_WORKING_DIRECTORY:-${CONFIG_WORKING_DIRECTORY:-${AGENT_LOOP_WORKING_DIRECTORY:-$(pwd)}}}"
if [ -n "$CANDIDATE_WORKING_DIR" ]; then
  WORKING_CONFIG_FILE="$CANDIDATE_WORKING_DIR/.agent-loop.json"
  if [ "$(cd "$(dirname "$WORKING_CONFIG_FILE")" 2>/dev/null && pwd)/$(basename "$WORKING_CONFIG_FILE")" != "$(cd "$(dirname "$SCRIPT_CONFIG_FILE")" 2>/dev/null && pwd)/$(basename "$SCRIPT_CONFIG_FILE")" ]; then
    import_config_file "$WORKING_CONFIG_FILE"
  fi
fi

# ── Merge: CLI wins over config file ─────────────────────────────────
ORG="${CLI_ORG:-$CONFIG_ORG}"
PROJECT="${CLI_PROJECT:-$CONFIG_PROJECT}"
AREA_PATH="${CLI_AREA_PATH:-$CONFIG_AREA_PATH}"
TEAM="${CLI_TEAM:-$CONFIG_TEAM}"
PROCESS="${CLI_PROCESS:-$CONFIG_PROCESS}"
REPO_URL="${CLI_REPO_URL:-$CONFIG_REPO_URL}"
BASE_BRANCH="${CLI_BASE_BRANCH:-${CONFIG_BASE_BRANCH:-}}"
MAX_ITERATIONS="${CLI_MAX_ITERATIONS:-${CONFIG_MAX_ITERATIONS:-1}}"
PROVIDER="$(normalize_provider_name "${CLI_PROVIDER:-$CONFIG_PROVIDER}")"
MODEL="${CLI_MODEL:-$CONFIG_MODEL}"
FEATURE_ID="${CLI_FEATURE_ID:-$CONFIG_FEATURE_ID}"
WORKING_DIR="${CLI_WORKING_DIRECTORY:-${CONFIG_WORKING_DIRECTORY:-${AGENT_LOOP_WORKING_DIRECTORY:-$(pwd)}}}"
SYSTEM_LOG_DIR="${CLI_SYSTEM_LOG_DIRECTORY:-${CONFIG_SYSTEM_LOG_DIRECTORY:-${AGENT_LOOP_SYSTEM_LOG_DIR:-$(resolve_system_log_directory)}}}"

MODEL="$(normalize_cursor_model "$PROVIDER" "$MODEL")"

# ── Validate required values ──────────────────────────────────────────
ERRORS=()

[ -z "$ORG" ]      && ERRORS+=("Missing required value: --org (Azure DevOps org URL)")
[ -z "$PROJECT" ]  && ERRORS+=("Missing required value: --project (Azure DevOps project name)")
[ -z "$PROVIDER" ] && ERRORS+=("Missing required value: --provider (claude-code, cursor, or cursor-cli)")

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Error: Configuration is incomplete:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Provide values via CLI parameters or .agent-loop.json in the working directory." >&2
  echo "See .agent-loop.example.json for the full schema." >&2
  exit 1
fi

# ── Validate provider value ───────────────────────────────────────────
if [[ "$PROVIDER" != "claude-code" && "$PROVIDER" != "cursor-cli" ]]; then
  echo "Error: Invalid provider '$PROVIDER'. Must be 'claude-code', 'cursor', or 'cursor-cli'." >&2
  exit 1
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --max-iterations must be a positive integer." >&2
  exit 1
fi

if [ ! -d "$WORKING_DIR" ]; then
  echo "Error: working directory does not exist: $WORKING_DIR" >&2
  exit 1
fi

if ! mkdir -p "$SYSTEM_LOG_DIR"; then
  echo "Error: could not create system log directory: $SYSTEM_LOG_DIR" >&2
  exit 1
fi

# ── Validate environment variables ───────────────────────────────────
ENV_ERRORS=()

if [ -z "${AZURE_DEVOPS_PAT:-}" ]; then
  ENV_ERRORS+=("Missing required environment variable: AZURE_DEVOPS_PAT")
fi

if [ "$PROVIDER" = "claude-code" ]; then
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    log_warn "ANTHROPIC_API_KEY is set; Claude Code will use API-key auth instead of the signed-in Claude session."
  elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    log_info "CLAUDE_CODE_OAUTH_TOKEN detected; Claude Code will use OAuth token auth."
  else
    log_info "Claude Code will use the signed-in Claude session. Run 'claude' and complete login first if needed."
  fi
fi

if [ "$PROVIDER" = "cursor-cli" ] && [ -z "${CURSOR_API_KEY:-}" ]; then
  log_info "CURSOR_API_KEY not set; Cursor Agent will use the signed-in Cursor session."
fi

if [ ${#ENV_ERRORS[@]} -gt 0 ]; then
  echo "Error: Required environment variables are not set:" >&2
  for err in "${ENV_ERRORS[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

# ── Export resolved config for use by the rest of the script ─────────
export AGENT_LOOP_ORG="$ORG"
export AGENT_LOOP_PROJECT="$PROJECT"
export AGENT_LOOP_AREA_PATH="$AREA_PATH"
export AGENT_LOOP_TEAM="$TEAM"
export AGENT_LOOP_PROCESS="$PROCESS"
export AGENT_LOOP_REPO_URL="$REPO_URL"
export AGENT_LOOP_BASE_BRANCH="$BASE_BRANCH"
export AGENT_LOOP_MAX_ITERATIONS="$MAX_ITERATIONS"
export AGENT_LOOP_PROVIDER="$PROVIDER"
export AGENT_LOOP_MODEL="$MODEL"
export AGENT_LOOP_WORKING_DIRECTORY="$WORKING_DIR"
export AGENT_LOOP_SYSTEM_LOG_DIR="$SYSTEM_LOG_DIR"
export AGENT_LOOP_FEATURE_ID="$FEATURE_ID"

echo "══════════════════════════════════════════════════════"
echo "  agent-loop"
echo "  Org:             $ORG"
echo "  Project:         $PROJECT"
echo "  Provider:        $PROVIDER${MODEL:+ ($MODEL)}"
echo "  Base branch:     ${BASE_BRANCH:-(auto-detect)}"
echo "  Max PBIs/run:    $MAX_ITERATIONS"
[ -n "$FEATURE_ID" ] && echo "  Feature ID:      $FEATURE_ID"
[ -n "$AREA_PATH" ]  && echo "  Area path:       $AREA_PATH"
[ -n "$TEAM" ]       && echo "  Team:            $TEAM"
[ -n "$REPO_URL" ]   && echo "  Repo URL:        $REPO_URL"
echo "  System logs:     $SYSTEM_LOG_DIR"
echo "══════════════════════════════════════════════════════"

# ── Lock manager ──────────────────────────────────────────────────────
LOCK_FILE="$WORKING_DIR/.agent-loop.lock"
LOCK_ACQUIRED=false

acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    log_warn "Another instance is already running (lock file exists: $LOCK_FILE). Exiting."
    return 1
  fi
  LOCK_ACQUIRED=true
  log_info "Lock acquired: $LOCK_FILE"
}

release_lock() {
  if [ "$LOCK_ACQUIRED" = true ] && [ -f "$LOCK_FILE" ] && [ "$(tr -d '[:space:]' < "$LOCK_FILE" 2>/dev/null)" = "$$" ]; then
    rm -f "$LOCK_FILE"
    log_info "Lock released: $LOCK_FILE"
  fi
}

# ── Context manager ───────────────────────────────────────────────────
AGENT_CONTEXT_DIR="$WORKING_DIR/.agent-context"
PROGRESS_FILE="$WORKING_DIR/progress.txt"
CURRENT_FEATURE_LOG_FILE=""

ensure_gitignore() {
  local gitignore="$WORKING_DIR/.gitignore"
  local entries=('.agent-context/' '.agent-loop.lock' 'progress.txt')
  for entry in "${entries[@]}"; do
    if [ ! -f "$gitignore" ] || ! grep -qxF "$entry" "$gitignore"; then
      echo "$entry" >> "$gitignore"
      log_info "$entry added to .gitignore"
    fi
  done
}

ensure_progress_file() {
  if [ ! -f "$PROGRESS_FILE" ]; then
    {
      printf '# Ralph Loop Progress Log\n'
      printf '# Repo: %s\n' "$(basename "$WORKING_DIR")"
      printf '# Started: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '\n'
    } > "$PROGRESS_FILE"
    log_info "Progress file initialized: $PROGRESS_FILE"
  fi
}

write_feature_context() {
  local feature_id="$1"
  local content="$2"
  mkdir -p "$AGENT_CONTEXT_DIR"
  printf '%s' "$content" > "$AGENT_CONTEXT_DIR/feature.md"
  log_info "Feature context written to .agent-context/feature.md (feature $feature_id)"
}

capture_agent_log() {
  local feature_id="$1"
  local output="$2"
  mkdir -p "$AGENT_CONTEXT_DIR/logs"
  printf '%s\n' "$output" >> "$AGENT_CONTEXT_DIR/logs/feature-${feature_id}.log"
  if [ -n "$CURRENT_FEATURE_LOG_FILE" ]; then
    printf '%s\n' "$output" >> "$CURRENT_FEATURE_LOG_FILE"
  fi
}

start_feature_log() {
  local feature_id="$1"
  local feature_title="$2"
  local timestamp
  timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
  CURRENT_FEATURE_LOG_FILE="$SYSTEM_LOG_DIR/feature-${feature_id}-${timestamp}.log"
  {
    printf 'Feature ID: %s\n' "$feature_id"
    printf 'Feature Title: %s\n' "$feature_title"
    printf 'Started At (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')"
    printf 'Working Directory: %s\n' "$WORKING_DIR"
    printf 'Provider: %s%s\n' "$PROVIDER" "${MODEL:+ ($MODEL)}"
    printf '\n'
  } >> "$CURRENT_FEATURE_LOG_FILE"
  log_info "Persistent agent log: $CURRENT_FEATURE_LOG_FILE"
}

append_feature_log_note() {
  local message="$1"
  if [ -n "$CURRENT_FEATURE_LOG_FILE" ]; then
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')" "$message" >> "$CURRENT_FEATURE_LOG_FILE"
  fi
}

cleanup() {
  if [ -d "$AGENT_CONTEXT_DIR" ]; then
    rm -rf "$AGENT_CONTEXT_DIR"
    log_info "Cleaned up .agent-context/"
  fi
}

# ── ADO Client ────────────────────────────────────────────────────────

# Returns "Basic <base64(:PAT)>" for use in Authorization headers.
_ado_auth_header() {
  printf 'Basic %s' "$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64 | tr -d '\n')"
}

# Makes an ADO REST API call.
# Prints the response body on success (HTTP 2xx).
# Logs an error and returns 1 on failure.
# Usage: _ado_call <METHOD> <URL> [JSON_BODY] [CONTENT_TYPE]
_ado_call() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local content_type="${4:-application/json}"
  local auth
  auth=$(_ado_auth_header)

  local tmp_body
  tmp_body=$(mktemp)

  local http_code
  if [ -n "$body" ]; then
    http_code=$(curl -s -o "$tmp_body" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: $auth" \
      -H "Content-Type: $content_type" \
      -d "$body" \
      "$url")
  else
    http_code=$(curl -s -o "$tmp_body" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: $auth" \
      "$url")
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    log_error "ADO API error: HTTP $http_code — $method $url"
    log_error "Response: $(cat "$tmp_body")"
    rm -f "$tmp_body"
    return 1
  fi

  cat "$tmp_body"
  rm -f "$tmp_body"
}

# Queries ADO for Features that have at least one child PBI tagged
# "ready-for-agent", not tagged "agent-done", and still in a runnable state,
# scoped to the configured areaPath.
# Prints one Feature ID per line.
query_eligible_features() {
  local wiql="SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.WorkItemType] = 'Feature'"
  local in_progress_state
  in_progress_state=$(get_in_progress_state)
  if [ -n "$AREA_PATH" ]; then
    local escaped_area_path=${AREA_PATH//\'/\'\'}
    wiql+=" AND [Source].[System.AreaPath] UNDER '$escaped_area_path'"
  fi
  wiql+=" AND [Target].[System.Tags] CONTAINS 'ready-for-agent' AND [Target].[System.Tags] NOT CONTAINS 'agent-done' AND ([Target].[System.State] = 'New' OR [Target].[System.State] = '$in_progress_state') AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' MODE (MustContain)"

  local payload
  payload=$(jq -n --arg q "$wiql" '{"query": $q}')

  local url="${ORG}/${PROJECT}/_apis/wit/wiql?api-version=7.1"
  local response
  response=$(_ado_call POST "$url" "$payload") || return 1

  # Extract unique source Feature IDs (source is null for the root row; skip it).
  echo "$response" | jq -r '[.workItemRelations[].source | select(. != null) | .id] | unique | .[]'
}

# Fetches all child PBIs of a Feature, expanding all fields and relations
# (including Dependency-Forward links needed by the dependency resolver).
# Prints the raw JSON "value" array from the batch work-items response.
# Usage: get_child_pbis <feature_id>
get_child_pbis() {
  local feature_id="$1"

  # Fetch the Feature to get its relations.
  local feature_url="${ORG}/${PROJECT}/_apis/wit/workitems/${feature_id}?\$expand=relations&api-version=7.1"
  local feature_json
  feature_json=$(_ado_call GET "$feature_url") || return 1

  # Extract IDs of direct children (Hierarchy-Forward from Feature to PBI).
  local child_ids
  child_ids=$(echo "$feature_json" | jq -r '
    (.relations // [])
    | map(select(.rel == "System.LinkTypes.Hierarchy-Forward"))
    | map(.url | split("/") | last)
    | .[]
  ')

  if [ -z "$child_ids" ]; then
    log_info "No child PBIs found for Feature $feature_id"
    echo "[]"
    return 0
  fi

  local ids_param
  ids_param=$(echo "$child_ids" | tr '\n' ',' | sed 's/,$//')

  # Fetch all child PBIs with full expansion (fields + relations).
  local pbis_url="${ORG}/${PROJECT}/_apis/wit/workitems?ids=${ids_param}&\$expand=all&api-version=7.1"
  local pbis_json
  pbis_json=$(_ado_call GET "$pbis_url") || return 1

  echo "$pbis_json" | jq '.value'
}

# Fetches a single work item by ID with all fields and relations expanded.
# Prints the raw work item JSON object.
# Usage: get_work_item <work_item_id>
get_work_item() {
  local work_item_id="$1"
  local url="${ORG}/${PROJECT}/_apis/wit/workitems/${work_item_id}?\$expand=all&api-version=7.1"
  _ado_call GET "$url"
}

# Returns the "in progress" state name for the configured process template.
# Scrum → "Committed"; Agile/CMMI → "Active"; unknown → "In Progress".
get_in_progress_state() {
  case "${PROCESS:-}" in
    Scrum)      echo "Committed" ;;
    Agile|CMMI) echo "Active" ;;
    *)          echo "In Progress" ;;
  esac
}

# Transitions a work item to the given state.
# The caller is responsible for passing the correct state name for the process
# template (e.g. "Active" for Agile, "In Progress" for Scrum).
# Usage: update_work_item_state <work_item_id> <state>
update_work_item_state() {
  local work_item_id="$1"
  local state="$2"

  local current_work_item
  current_work_item=$(get_work_item "$work_item_id") || return 1

  local current_state
  current_state=$(printf '%s' "$current_work_item" | jq -r '.fields["System.State"] // ""')
  if [ "$current_state" = "$state" ]; then
    log_info "Work item $work_item_id is already in state '$state'"
    return 0
  fi

  local payload
  payload=$(jq -n --arg s "$state" '[{"op":"replace","path":"/fields/System.State","value":$s}]')

  local url="${ORG}/${PROJECT}/_apis/wit/workitems/${work_item_id}?api-version=7.1"
  if ! _ado_call PATCH "$url" "$payload" "application/json-patch+json" >/dev/null; then
    local refreshed_work_item
    refreshed_work_item=$(get_work_item "$work_item_id") || return 1

    local refreshed_state
    refreshed_state=$(printf '%s' "$refreshed_work_item" | jq -r '.fields["System.State"] // ""')
    if [ "$refreshed_state" = "$state" ]; then
      log_warn "Work item $work_item_id was updated to '$state' by another process; continuing"
      return 0
    fi

    return 1
  fi
  log_info "Work item $work_item_id state set to '$state'"
}

# Appends a tag to a work item without removing existing tags.
# Usage: add_work_item_tag <work_item_id> <tag>
add_work_item_tag() {
  local work_item_id="$1"
  local tag="$2"

  # Fetch current tags so we can append rather than overwrite.
  local work_item
  work_item=$(get_work_item "$work_item_id") || return 1

  local current_tags
  current_tags=$(echo "$work_item" | jq -r '.fields["System.Tags"] // ""')

  local new_tags
  local op="replace"
  if printf '%s' "$current_tags" | jq -Rr --arg tag "$tag" 'split(";") | map(gsub("^\\s+|\\s+$"; "")) | any(. == $tag)' | grep -qx 'true'; then
    log_info "Tag '$tag' already present on work item $work_item_id"
    return 0
  fi
  if [ -z "$current_tags" ]; then
    new_tags="$tag"
    op="add"
  else
    new_tags="${current_tags}; ${tag}"
  fi

  local payload
  payload=$(jq -n --arg op "$op" --arg t "$new_tags" '[{"op":$op,"path":"/fields/System.Tags","value":$t}]')

  local url="${ORG}/${PROJECT}/_apis/wit/workitems/${work_item_id}?api-version=7.1"
  _ado_call PATCH "$url" "$payload" "application/json-patch+json" || return 1
  log_info "Tag '$tag' appended to work item $work_item_id"
}

# Creates a pull request and links all PBI work items to it.
# Usage: create_pull_request <feature_title> <feature_branch> <pbis_json>
#   feature_title  — Title string for the PR (becomes the PR title)
#   feature_branch — Source branch name (e.g. agent/42-my-feature)
#   pbis_json      — JSON array of PBI work item objects with .id and
#                    .fields["System.Title"] present
# Prints the PR web URL on success. Returns 1 on failure.
create_pull_request() {
  local feature_title="$1"
  local feature_branch="$2"
  local pbis_json="$3"
  local repo_url_for_pr="$REPO_URL"

  local origin_repo_url=""
  if origin_repo_url=$(git remote get-url origin 2>/dev/null); then
    origin_repo_url="${origin_repo_url%%$'\n'*}"
    if [ -n "$origin_repo_url" ]; then
      repo_url_for_pr="$origin_repo_url"
    fi
  fi

  if [ -z "$repo_url_for_pr" ]; then
    log_error "create_pull_request: REPO_URL is not set and origin remote could not be resolved"
    return 1
  fi

  local repo_path
  repo_path=$(printf '%s' "$repo_url_for_pr" | sed -E 's|^[^:]+://[^/]+||; s|^[^@]+@[^:]+:|/|')
  repo_path="${repo_path#/}"
  repo_path="${repo_path%%\?*}"

  IFS='/' read -r -a repo_path_parts <<< "$repo_path"
  if [ "${#repo_path_parts[@]}" -lt 4 ] || [ "${repo_path_parts[2]}" != "_git" ]; then
    log_error "create_pull_request: unable to parse repository project/name from REPO_URL='$repo_url_for_pr'"
    return 1
  fi

  local repo_project="${repo_path_parts[1]}"
  local repo_name_from_url="${repo_path_parts[3]}"
  if [ -z "$repo_project" ] || [ -z "$repo_name_from_url" ]; then
    log_error "create_pull_request: parsed invalid repository context from REPO_URL='$repo_url_for_pr'"
    return 1
  fi

  local repo_list_url="${ORG}/${repo_project}/_apis/git/repositories?api-version=7.1"
  local repo_list_json
  repo_list_json=$(_ado_call GET "$repo_list_url") || return 1

  local repo_name_candidates_json
  repo_name_candidates_json=$(jq -n \
    --arg repoName "$repo_name_from_url" \
    '[$repoName, ($repoName | sub("\\.git$"; ""))] | map(select(length > 0)) | unique')

  local repo_json
  repo_json=$(printf '%s' "$repo_list_json" | jq -c \
    --argjson names "$repo_name_candidates_json" '
      (.value // [])
      | map(
          . as $repo
          | (($names | index($repo.name)) != null
             or ($names | index(($repo.name | sub("\\.git$"; "")))) != null)
          | select(.)
          | $repo
        )
      | .[0] // empty
    ')

  if [ -z "$repo_json" ]; then
    log_error "create_pull_request: unable to resolve repository metadata for REPO_URL='$repo_url_for_pr'"
    return 1
  fi

  local repo_id repo_name
  repo_id=$(printf '%s' "$repo_json" | jq -r '.id // empty')
  repo_name=$(printf '%s' "$repo_json" | jq -r '.name // empty')
  if [ -z "$repo_id" ] || [ -z "$repo_name" ]; then
    log_error "create_pull_request: could not parse repository metadata from REPO_URL='$repo_url_for_pr'"
    return 1
  fi

  # Build PR description listing all PBI IDs and titles.
  local description
  description=$(printf '%s' "$pbis_json" | jq -r '
    map("- #\(.id): \(.fields["System.Title"])")
    | join("\n")
  ')

  # Build workItemRefs array: [{ "id": "123" }, ...]
  local work_item_refs
  work_item_refs=$(printf '%s' "$pbis_json" | jq '[.[] | {"id": (.id | tostring)}]')

  local payload
  payload=$(jq -n \
    --arg title  "$feature_title" \
    --arg src    "refs/heads/$feature_branch" \
    --arg tgt    "refs/heads/$BASE_BRANCH" \
    --arg desc   "$description" \
    --argjson wir "$work_item_refs" \
    '{
      "title":         $title,
      "description":   $desc,
      "sourceRefName": $src,
      "targetRefName": $tgt,
      "workItemRefs":  $wir
    }')

  local url="${ORG}/${repo_project}/_apis/git/repositories/${repo_id}/pullrequests?api-version=7.1"
  local response
  response=$(_ado_call POST "$url" "$payload") || {
    log_error "create_pull_request: failed to create PR for branch '$feature_branch'"
    return 1
  }

  local pr_id
  pr_id=$(printf '%s' "$response" | jq -r '.pullRequestId // empty')

  if [ -z "$pr_id" ]; then
    log_error "create_pull_request: PR created but could not parse pullRequestId from response"
    return 1
  fi

  local pr_web_url="${ORG}/${repo_project}/_git/${repo_name}/pullrequest/${pr_id}"
  log_info "Pull request #${pr_id} created: $pr_web_url"
  printf '%s\n' "$pr_web_url"
}

# ── Dependency resolver ───────────────────────────────────────────────

# Topologically sorts PBIs by their Dependency-Forward relations using
# Kahn's algorithm.  PBIs with no predecessors appear first; the
# relative order among independent PBIs is preserved from the input.
#
# Usage:  sort_pbis_by_dependency <pbis_json>
#   pbis_json — JSON array of PBI work item objects (with $expand=all so
#               the .relations field is present).
#
# On success: prints a JSON array of PBI objects in dependency order.
# On cycle:   logs an error identifying the cycle and returns 1.
# Empty input is handled gracefully (prints "[]").
sort_pbis_by_dependency() {
  local pbis_json="$1"

  # The entire algorithm runs inside jq (already required by the script).
  # Dependency-Forward on a PBI means "this PBI is a predecessor of the
  # linked item" → edge: src → tgt (src must execute before tgt).
  local jq_prog='
. as $pbis |
(map(.id | tostring) | unique) as $allIds |
if ($allIds | length) == 0 then {"ok": true, "result": []}
else
  ($pbis | map({key: (.id | tostring), value: .}) | from_entries) as $pbiMap |
  ($allIds | map({key: ., value: 0}) | from_entries) as $initIndeg |
  (reduce $pbis[] as $pbi (
    {adj: {}, indeg: $initIndeg};
    ($pbi.id | tostring) as $src |
    .adj[$src] //= [] |
    reduce (($pbi.relations // [])[] | select(.rel == "System.LinkTypes.Dependency-Forward")) as $rel (
      .;
      ($rel.url | split("/") | last) as $tgt |
      if ($initIndeg | has($tgt)) and ((.adj[$src] | index($tgt)) == null) then
        .adj[$src] += [$tgt] |
        .indeg[$tgt] += 1
      else . end
    )
  )) as $g |
  def kahn(adj; indeg; queue; sorted):
    if (queue | length) == 0 then {indeg: indeg, sorted: sorted}
    else
      queue[0] as $node |
      queue[1:] as $rest |
      reduce (adj[$node] // [])[] as $succ (
        {indeg: indeg, queue: $rest};
        .indeg[$succ] -= 1 |
        if .indeg[$succ] == 0 then .queue += [$succ] else . end
      ) as $s |
      kahn(adj; $s.indeg; $s.queue; sorted + [$node])
    end;
  ($allIds | map(select($g.indeg[.] == 0))) as $q0 |
  kahn($g.adj; $g.indeg; $q0; []) as $r |
  if ($r.sorted | length) != ($allIds | length) then
    ($r.indeg | to_entries | map(select(.value > 0)) | map(.key)) as $cycle |
    {"ok": false, "error": "Circular dependency detected among PBIs: \($cycle | join(", "))"}
  else
    {"ok": true, "result": ($r.sorted | map($pbiMap[.]))}
  end
end
'

  local result
  result=$(echo "$pbis_json" | jq "$jq_prog") || {
    log_error "sort_pbis_by_dependency: jq failed to process PBI list"
    return 1
  }

  local ok
  ok=$(echo "$result" | jq -r '.ok')
  if [ "$ok" != "true" ]; then
    log_error "sort_pbis_by_dependency: $(echo "$result" | jq -r '.error')"
    return 1
  fi

  echo "$result" | jq '.result'
}

# ── Git manager ────────────────────────────────────────────────────────

# Resolves the default/base branch name.
# Priority: BASE_BRANCH config/CLI value > git symbolic-ref > error
# Prints the branch name on success. Returns 1 on failure.
detect_default_branch() {
  if [ -n "$BASE_BRANCH" ]; then
    echo "$BASE_BRANCH"
    return 0
  fi

  local symbolic_ref
  symbolic_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || {
    log_error "detect_default_branch: cannot determine default branch — set baseBranch in config or --base-branch"
    return 1
  }
  # symbolic_ref is like refs/remotes/origin/main → strip the prefix
  echo "${symbolic_ref#refs/remotes/origin/}"
}

# Converts a Feature title to a URL-safe lowercase slug.
# Replaces non-alphanumeric characters with hyphens, collapses runs,
# and strips leading/trailing hyphens.
# Usage: slugify_title <title>
# Prints the slug.
slugify_title() {
  local title="$1"
  printf '%s' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\+/-/g' \
    | sed 's/^-//;s/-$//'
}

# Creates a feature branch named agent/<feature_id>-<slug> from the base branch
# and pushes it to origin.
# Usage: create_feature_branch <feature_id> <feature_title>
# Prints the branch name on success. Returns 1 on failure.
create_feature_branch() {
  local feature_id="$1"
  local feature_title="$2"

  local base_branch
  base_branch=$(detect_default_branch) || return 1

  local slug
  slug=$(slugify_title "$feature_title")
  local branch_name="agent/${feature_id}-${slug}"

  log_info "Creating branch '$branch_name' from '$base_branch'"

  git fetch origin "$base_branch" 2>&1 | while IFS= read -r line; do log_info "git: $line"; done
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log_error "create_feature_branch: failed to fetch '$base_branch' from origin"
    return 1
  fi

  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    log_info "Branch '$branch_name' already exists locally — checking out"
    git checkout "$branch_name" 2>&1 | while IFS= read -r line; do log_info "git: $line"; done
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      log_error "create_feature_branch: failed to checkout existing branch '$branch_name'"
      return 1
    fi
  else
    git checkout -b "$branch_name" "origin/$base_branch" 2>&1 | while IFS= read -r line; do log_info "git: $line"; done
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      log_error "create_feature_branch: failed to create branch '$branch_name'"
      return 1
    fi
  fi

  git push -u origin "$branch_name" 2>&1 | while IFS= read -r line; do log_info "git: $line"; done
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log_error "create_feature_branch: failed to push '$branch_name' to origin"
    return 1
  fi

  log_info "Branch '$branch_name' created and pushed to origin"
  printf '%s\n' "$branch_name"
}

# Verifies that the working tree is clean (no uncommitted changes) and that
# all commits on the feature branch have been pushed to origin.
# Usage: check_clean_and_pushed <feature_branch>
# Returns 0 if both conditions hold, 1 otherwise.
check_clean_and_pushed() {
  local feature_branch="$1"

  local status_output
  status_output=$(git status --porcelain 2>&1)
  if [ -n "$status_output" ]; then
    log_error "check_clean_and_pushed: working tree is not clean — uncommitted changes detected"
    log_error "$status_output"
    return 1
  fi

  # Fetch to make sure remote tracking ref is current.
  git fetch origin "$feature_branch" 2>/dev/null || true

  local unpushed
  unpushed=$(git log "origin/${feature_branch}..HEAD" --oneline 2>/dev/null)
  if [ -n "$unpushed" ]; then
    log_error "check_clean_and_pushed: there are unpushed commits on '$feature_branch':"
    log_error "$unpushed"
    return 1
  fi

  return 0
}

trap 'release_lock; cleanup' EXIT

cd "$WORKING_DIR"

acquire_lock || exit 0
ensure_gitignore
ensure_progress_file

# Resolve base branch early (auto-detect if not configured) so it is
# available to both create_feature_branch and create_pull_request.
BASE_BRANCH=$(detect_default_branch) || {
  log_error "Failed to determine base branch"
  exit 1
}
export AGENT_LOOP_BASE_BRANCH="$BASE_BRANCH"
log_info "Base branch resolved to '$BASE_BRANCH'"

# ── Agent dispatcher ───────────────────────────────────────────────────

# Assembles the prompt that will be sent to the AI agent.
# The prompt includes the exact PBI scope plus strict instructions to keep
# changes minimal and signal a clear terminal state.
# Usage: build_prompt <pbi_id> <pbi_title> <pbi_description> <acceptance_criteria>
# Prints the assembled prompt string.
build_prompt() {
  local pbi_id="$1"
  local pbi_title="$2"
  local pbi_description="$3"
  local acceptance_criteria="$4"

  cat <<'PROMPT'
You are implementing exactly one Product Backlog Item (PBI). Stay tightly scoped to this PBI only.

## PBI Details

**ID:**
PROMPT
  printf '%s\n\n' "$pbi_id"
  cat <<'PROMPT'

**Title:**
PROMPT
  printf '%s\n\n' "$pbi_title"
  cat <<'PROMPT'

**Description:**
PROMPT
  printf '%s\n\n' "$pbi_description"
  cat <<'PROMPT'

**Acceptance Criteria:**
PROMPT
  printf '%s\n\n' "$acceptance_criteria"
  cat <<'PROMPT'

## Feature Context

Read \`.agent-context/feature.md\` only for supporting context about the parent Feature.

## Progress Memory

Read \`progress.txt\` in the repo root before you start so you can reuse useful context and avoid repeating failed approaches from prior runs.

## Instructions

1. Implement only this PBI and satisfy its acceptance criteria.
2. Make the smallest change set that solves this PBI.
3. Do not fix unrelated bugs, clean up unrelated code, or refactor outside the work required for this PBI.
4. If you notice unrelated problems, leave them alone unless they block this PBI.
5. Run only the checks needed to validate this PBI.
6. Append a concise entry to \`progress.txt\` with today's date, the PBI ID, what you completed, and any important follow-up notes for the next run.
7. If blocked, append a concise entry to \`progress.txt\` describing exactly what blocked you and what should be avoided or tried next.
8. Commit only the code changes for this PBI and push to origin. Do NOT create a pull request. Do not include \`progress.txt\` in the commit.
9. When complete, output the exact string \`AGENT_DONE\` on a line by itself.
10. If you cannot complete this PBI cleanly, output the exact string \`AGENT_BLOCKED\` on a line by itself.
PROMPT
}

# Dispatches the configured AI provider with the given prompt and captures output.
# Globals set after return:
#   AGENT_INVOKE_EXIT_CODE  — exit code from the agent process
#   AGENT_INVOKE_COMPLETED  — "true" if AGENT_DONE/AGENT_COMPLETE was detected
#   AGENT_INVOKE_BLOCKED    — "true" if AGENT_BLOCKED was detected
# Usage: invoke_agent <prompt>
# Prints the captured agent output (stdout + stderr combined).
# Returns 1 if provider is invalid, otherwise returns 0 regardless of agent exit code
# (the caller should inspect AGENT_INVOKE_EXIT_CODE for the agent's own exit status).
invoke_agent() {
  local prompt="$1"
  local output=""
  local exit_code=0

  AGENT_INVOKE_EXIT_CODE=0
  AGENT_INVOKE_COMPLETED="false"
  AGENT_INVOKE_BLOCKED="false"

  test_agent_signal_value() {
    local input="$1"
    local raw_pattern="$2"
    local json_pattern="$3"

    if [ -z "$input" ]; then
      return 1
    fi

    if printf '%s\n' "$input" | grep -Eq "$raw_pattern"; then
      return 0
    fi

    if printf '%s' "$input" | jq -e --arg pattern "$json_pattern" '
      def contains_completion:
        if type == "string" then test($pattern)
        elif type == "array" then any(.[]; contains_completion)
        elif type == "object" then any(.[]; contains_completion)
        else false
        end;
      contains_completion
    ' >/dev/null 2>&1; then
      return 0
    fi

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if printf '%s' "$line" | jq -e --arg pattern "$json_pattern" '
        def contains_completion:
          if type == "string" then test($pattern)
          elif type == "array" then any(.[]; contains_completion)
          elif type == "object" then any(.[]; contains_completion)
          else false
          end;
        contains_completion
      ' >/dev/null 2>&1; then
        return 0
      fi
    done <<< "$input"

    return 1
  }

  case "$PROVIDER" in
    claude-code)
      local model_args=()
      if [ -n "$MODEL" ]; then
        model_args=(--model "$MODEL")
      fi
      output=$(claude -p "$prompt" \
        --output-format json \
        "${model_args[@]}" \
        --allowedTools "Read,Write,Edit,Bash" 2>&1) || exit_code=$?
      ;;
    cursor-cli)
      local model_args=()
      if [ -n "$MODEL" ]; then
        model_args=(--model "$MODEL")
      fi
      output=$(agent -p "$prompt" \
        --force \
        --trust \
        --workspace "$WORKING_DIR" \
        --output-format json \
        "${model_args[@]}" 2>&1) || exit_code=$?
      ;;
    *)
      log_error "invoke_agent: unknown provider '$PROVIDER'. Must be 'claude-code', 'cursor', or 'cursor-cli'."
      return 1
      ;;
  esac

  AGENT_INVOKE_EXIT_CODE=$exit_code

  if test_agent_signal_value "$output" '^[[:space:]]*(AGENT_DONE|AGENT_COMPLETE)[[:space:]]*$' '(?m)^\s*(AGENT_DONE|AGENT_COMPLETE)\s*$'; then
    AGENT_INVOKE_COMPLETED="true"
  fi

  if test_agent_signal_value "$output" '^[[:space:]]*AGENT_BLOCKED[[:space:]]*$' '(?m)^\s*AGENT_BLOCKED\s*$'; then
    AGENT_INVOKE_BLOCKED="true"
  fi

  if [ "$exit_code" -ne 0 ]; then
    log_error "invoke_agent: agent exited with non-zero exit code $exit_code"
  fi

  printf '%s' "$output"
}

# ── PBI processor ───────────────────────────────────────────────────────
#
# Processes a single PBI with one agent invocation. The agent must either
# complete the work cleanly or explicitly report that it is blocked.
#
# Usage: process_pbi <pbi_id> <pbi_title> <pbi_description> <acceptance_criteria> <feature_branch> <feature_id>
# Returns 0 on success, 1 on failure.
process_pbi() {
  local pbi_id="$1"
  local pbi_title="$2"
  local pbi_description="$3"
  local acceptance_criteria="$4"
  local feature_branch="$5"
  local feature_id="$6"

  log_info "Processing PBI $pbi_id: $pbi_title"

  # Set PBI state to the process-appropriate in-progress state before first agent invocation.
  local in_progress_state
  in_progress_state=$(get_in_progress_state)
  update_work_item_state "$pbi_id" "$in_progress_state" || {
    log_error "process_pbi: failed to set PBI $pbi_id to '$in_progress_state' — aborting"
    return 1
  }

  local prompt
  prompt=$(build_prompt "$pbi_id" "$pbi_title" "$pbi_description" "$acceptance_criteria")

  local agent_output
  agent_output=$(invoke_agent "$prompt")

  capture_agent_log "$feature_id" "$agent_output"

  if [ "$AGENT_INVOKE_EXIT_CODE" -ne 0 ]; then
    log_error "process_pbi: agent exited with code $AGENT_INVOKE_EXIT_CODE for PBI $pbi_id"
    add_work_item_tag "$pbi_id" "agent-failed" || log_warn "process_pbi: failed to tag PBI $pbi_id as agent-failed"
    return 1
  fi

  if [ "$AGENT_INVOKE_BLOCKED" = "true" ]; then
    log_error "process_pbi: agent reported PBI $pbi_id is blocked"
    add_work_item_tag "$pbi_id" "agent-failed" || log_warn "process_pbi: failed to tag PBI $pbi_id as agent-failed"
    return 1
  fi

  if [ "$AGENT_INVOKE_COMPLETED" = "true" ] && check_clean_and_pushed "$feature_branch"; then
    log_info "PBI $pbi_id completed successfully"
    add_work_item_tag "$pbi_id" "agent-done" || log_warn "process_pbi: failed to tag PBI $pbi_id as agent-done"
    return 0
  fi

  if [ "$AGENT_INVOKE_COMPLETED" = "true" ]; then
    log_error "process_pbi: PBI $pbi_id reported completion but the branch is not clean and pushed"
  else
    log_error "process_pbi: PBI $pbi_id did not report AGENT_DONE"
  fi

  add_work_item_tag "$pbi_id" "agent-failed" || log_warn "process_pbi: failed to tag PBI $pbi_id as agent-failed"
  return 1
}

# ── Orchestrator ──────────────────────────────────────────────────────

log_info "agent-loop started"

# Step 3/4: Determine the Feature to process
if [ -n "$FEATURE_ID" ]; then
  # One-shot mode: --feature-id was supplied
  log_info "One-shot mode: processing Feature $FEATURE_ID"
  FEATURE_JSON=$(get_work_item "$FEATURE_ID") || {
    log_error "Failed to fetch Feature $FEATURE_ID"
    exit 1
  }
else
  # Scheduled mode: pick the first eligible Feature
  log_info "Scheduled mode: querying for eligible Features"
  ELIGIBLE_IDS=$(query_eligible_features) || {
    log_error "Failed to query eligible Features"
    exit 1
  }

  if [ -z "$ELIGIBLE_IDS" ]; then
    log_info "No eligible Features found — nothing to do"
    exit 0
  fi

  FEATURE_ID=$(echo "$ELIGIBLE_IDS" | head -n1)
  log_info "Selected Feature $FEATURE_ID for processing"

  FEATURE_JSON=$(get_work_item "$FEATURE_ID") || {
    log_error "Failed to fetch Feature $FEATURE_ID"
    exit 1
  }
fi

FEATURE_TYPE=$(printf '%s' "$FEATURE_JSON" | jq -r '.fields["System.WorkItemType"] // ""')
if [ "$FEATURE_TYPE" != "Feature" ]; then
  log_error "Work item $FEATURE_ID is a '$FEATURE_TYPE', not a Feature"
  exit 1
fi

FEATURE_TITLE=$(printf '%s' "$FEATURE_JSON" | jq -r '.fields["System.Title"] // ""')
FEATURE_DESCRIPTION=$(printf '%s' "$FEATURE_JSON" | jq -r '.fields["System.Description"] // ""')

log_info "Processing Feature $FEATURE_ID: $FEATURE_TITLE"
start_feature_log "$FEATURE_ID" "$FEATURE_TITLE"
append_feature_log_note "Feature processing started"

# Step 5: Fetch all child PBIs
log_info "Fetching child PBIs for Feature $FEATURE_ID"
PBIS_JSON=$(get_child_pbis "$FEATURE_ID") || {
  log_error "Failed to fetch child PBIs for Feature $FEATURE_ID"
  exit 1
}

runnable_state=$(get_in_progress_state)
READY_FOR_AGENT_PBIS=$(printf '%s' "$PBIS_JSON" | jq '[.[] | select(
  ((.fields["System.Tags"] // "")
    | split(";")
    | map(gsub("^\\s+|\\s+$"; ""))
    | any(. == "ready-for-agent"))
)]')

READY_FOR_AGENT_COUNT=$(printf '%s' "$READY_FOR_AGENT_PBIS" | jq 'length')
if [ "$READY_FOR_AGENT_COUNT" -eq 0 ]; then
  log_info "Feature $FEATURE_ID has no ready-for-agent child PBIs — nothing to do"
  exit 0
fi

REMAINING_READY_FOR_AGENT_PBIS=$(printf '%s' "$READY_FOR_AGENT_PBIS" | jq '[.[] | select(
  ((.fields["System.Tags"] // "")
    | split(";")
    | map(gsub("^\\s+|\\s+$"; ""))
    | any(. == "agent-done")) | not
)]')

PBIS_JSON=$(printf '%s' "$REMAINING_READY_FOR_AGENT_PBIS" | jq \
  --arg runnable_state "$runnable_state" '[.[] | select(
    ((.fields["System.Tags"] // "")
      | split(";")
      | map(gsub("^\\s+|\\s+$"; ""))
      | any(. == "ready-for-agent"))
    and (((.fields["System.Tags"] // "")
      | split(";")
      | map(gsub("^\\s+|\\s+$"; ""))
      | any(. == "agent-done")) | not)
    and ((.fields["System.State"] // "") == "New" or (.fields["System.State"] // "") == $runnable_state)
  )]')

log_info "Sorting PR PBIs by dependency order"
PR_PBIS=$(sort_pbis_by_dependency "$READY_FOR_AGENT_PBIS") || {
  log_error "Failed to sort PR PBIs by dependency for Feature $FEATURE_ID"
  exit 1
}

PBI_COUNT=$(printf '%s' "$PBIS_JSON" | jq 'length')
if [ "$PBI_COUNT" -eq 0 ]; then
  REMAINING_READY_COUNT=$(printf '%s' "$REMAINING_READY_FOR_AGENT_PBIS" | jq 'length')
  if [ "$REMAINING_READY_COUNT" -eq 0 ]; then
    log_info "All ready-for-agent PBIs are already tagged agent-done — continuing to pull request creation"
    SORTED_PBIS='[]'
  else
    log_info "Feature $FEATURE_ID has no eligible child PBIs (ready-for-agent + not agent-done + runnable state) — nothing to do"
    exit 0
  fi
else
  log_info "Found $PBI_COUNT eligible PBI(s) for Feature $FEATURE_ID"

  # Step 6: Topologically sort PBIs by dependency
  log_info "Sorting PBIs by dependency order"
  SORTED_PBIS=$(sort_pbis_by_dependency "$PBIS_JSON") || {
    log_error "Failed to sort PBIs by dependency for Feature $FEATURE_ID"
    exit 1
  }
fi

# Step 7: Create feature branch
log_info "Creating feature branch for Feature $FEATURE_ID"
FEATURE_BRANCH=$(create_feature_branch "$FEATURE_ID" "$FEATURE_TITLE") || {
  log_error "Failed to create feature branch for Feature $FEATURE_ID"
  exit 1
}

# Step 8: Write Feature PRD to .agent-context/feature.md
write_feature_context "$FEATURE_ID" "# Feature: $FEATURE_TITLE

## Description
$FEATURE_DESCRIPTION"

# Step 9/10: Process PBIs serially; stop on first failure
FEATURE_SUCCESS=true
if [ "$PBI_COUNT" -gt 0 ]; then
  PBI_LIMIT="$PBI_COUNT"
  if [ "$MAX_ITERATIONS" -lt "$PBI_LIMIT" ]; then
    PBI_LIMIT="$MAX_ITERATIONS"
  fi

  log_info "Processing up to $PBI_LIMIT PBI(s) for Feature $FEATURE_ID this run"

  for i in $(seq 0 $((PBI_LIMIT - 1))); do
    PBI_JSON=$(printf '%s' "$SORTED_PBIS" | jq ".[$i]")
    PBI_ID=$(printf '%s' "$PBI_JSON" | jq -r '.id')
    PBI_TITLE=$(printf '%s' "$PBI_JSON" | jq -r '.fields["System.Title"] // ""')
    PBI_DESCRIPTION=$(printf '%s' "$PBI_JSON" | jq -r '.fields["System.Description"] // ""')
    PBI_AC=$(printf '%s' "$PBI_JSON" | jq -r '.fields["Microsoft.VSTS.Common.AcceptanceCriteria"] // ""')

    log_info "Starting PBI $PBI_ID: $PBI_TITLE"

    if ! process_pbi "$PBI_ID" "$PBI_TITLE" "$PBI_DESCRIPTION" "$PBI_AC" "$FEATURE_BRANCH" "$FEATURE_ID"; then
      log_error "PBI $PBI_ID failed — skipping remaining PBIs for Feature $FEATURE_ID"
      FEATURE_SUCCESS=false
      break
    fi

    log_info "PBI $PBI_ID completed"
  done
fi

# Step 11: Create PR only when all ready-for-agent PBIs are tagged agent-done
if [ "$FEATURE_SUCCESS" = "true" ]; then
  UPDATED_PBIS_JSON=$(get_child_pbis "$FEATURE_ID") || {
    log_error "Failed to refresh child PBIs for Feature $FEATURE_ID"
    exit 1
  }

  REMAINING_READY_FOR_AGENT_PBIS=$(printf '%s' "$UPDATED_PBIS_JSON" | jq '[.[] | select(
    ((.fields["System.Tags"] // "")
      | split(";")
      | map(gsub("^\\s+|\\s+$"; ""))
      | any(. == "ready-for-agent"))
    and (((.fields["System.Tags"] // "")
      | split(";")
      | map(gsub("^\\s+|\\s+$"; ""))
      | any(. == "agent-done")) | not)
  )]')
  REMAINING_READY_COUNT=$(printf '%s' "$REMAINING_READY_FOR_AGENT_PBIS" | jq 'length')

  if [ "$REMAINING_READY_COUNT" -eq 0 ]; then
    log_info "All ready-for-agent PBIs completed — creating pull request for Feature $FEATURE_ID"
    PR_URL=$(create_pull_request "$FEATURE_TITLE" "$FEATURE_BRANCH" "$PR_PBIS") || {
      log_error "Failed to create pull request for Feature $FEATURE_ID"
      append_feature_log_note "Failed to create pull request"
      exit 1
    }
    append_feature_log_note "Feature completed successfully. Pull request: $PR_URL"
    log_info "Feature $FEATURE_ID complete — PR: $PR_URL"
    exit 0
  fi

  append_feature_log_note "Feature still has $REMAINING_READY_COUNT ready-for-agent PBI(s) remaining"
  log_info "Feature $FEATURE_ID still has $REMAINING_READY_COUNT ready-for-agent PBI(s) remaining"
  exit 0
else
  append_feature_log_note "Feature processing failed"
  log_error "Feature $FEATURE_ID processing failed — one or more PBIs did not complete"
  exit 1
fi
