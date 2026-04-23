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
  --base-branch <branch>    Base branch to branch from (default: main)
  --max-iterations <n>      Maximum loop iterations (default: 50)
  --provider <name>         AI provider: claude-code or cursor-cli
  --model <id>              Model ID to use (e.g. claude-opus-4-6)
  --working-directory <dir> Working directory containing the repo
  --feature-id <id>         ADO Feature ID to process (optional; processes all if omitted)

Environment variables:
  AZURE_DEVOPS_PAT          Required. Azure DevOps Personal Access Token.
  ANTHROPIC_API_KEY         Required when --provider is anthropic.
  CURSOR_API_KEY            Required when --provider is cursor.

Config file:
  .agent-loop.json          Optional JSON config in the working directory.
                            CLI parameters override config file values.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)              CLI_ORG="$2";               shift 2 ;;
    --project)          CLI_PROJECT="$2";           shift 2 ;;
    --area-path)        CLI_AREA_PATH="$2";         shift 2 ;;
    --team)             CLI_TEAM="$2";              shift 2 ;;
    --process)          CLI_PROCESS="$2";           shift 2 ;;
    --repo-url)         CLI_REPO_URL="$2";          shift 2 ;;
    --base-branch)      CLI_BASE_BRANCH="$2";       shift 2 ;;
    --max-iterations)   CLI_MAX_ITERATIONS="$2";    shift 2 ;;
    --provider)         CLI_PROVIDER="$2";          shift 2 ;;
    --model)            CLI_MODEL="$2";             shift 2 ;;
    --working-directory) CLI_WORKING_DIRECTORY="$2"; shift 2 ;;
    --feature-id)       CLI_FEATURE_ID="$2";        shift 2 ;;
    --help|-h)          print_usage; exit 0 ;;
    *)
      echo "Error: Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# ── Load config file ──────────────────────────────────────────────────
# Resolve working directory: CLI > env > current directory
WORKING_DIR="${CLI_WORKING_DIRECTORY:-${AGENT_LOOP_WORKING_DIRECTORY:-$(pwd)}}"
CONFIG_FILE="$WORKING_DIR/.agent-loop.json"

if [ -f "$CONFIG_FILE" ]; then
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required to parse .agent-loop.json. Install with: brew install jq / sudo apt install jq" >&2
    exit 1
  fi

  CONFIG_ORG=$(jq -r '.org // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_PROJECT=$(jq -r '.project // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_AREA_PATH=$(jq -r '.areaPath // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_TEAM=$(jq -r '.team // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_PROCESS=$(jq -r '.process // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_REPO_URL=$(jq -r '.repoUrl // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_BASE_BRANCH=$(jq -r '.baseBranch // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_MAX_ITERATIONS=$(jq -r '.maxIterations // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_PROVIDER=$(jq -r '.provider // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_MODEL=$(jq -r '.model // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_WORKING_DIRECTORY=$(jq -r '.workingDirectory // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIG_FEATURE_ID=$(jq -r '.featureId // empty' "$CONFIG_FILE" 2>/dev/null || true)
fi

# ── Merge: CLI wins over config file ─────────────────────────────────
ORG="${CLI_ORG:-$CONFIG_ORG}"
PROJECT="${CLI_PROJECT:-$CONFIG_PROJECT}"
AREA_PATH="${CLI_AREA_PATH:-$CONFIG_AREA_PATH}"
TEAM="${CLI_TEAM:-$CONFIG_TEAM}"
PROCESS="${CLI_PROCESS:-$CONFIG_PROCESS}"
REPO_URL="${CLI_REPO_URL:-$CONFIG_REPO_URL}"
BASE_BRANCH="${CLI_BASE_BRANCH:-${CONFIG_BASE_BRANCH:-main}}"
MAX_ITERATIONS="${CLI_MAX_ITERATIONS:-${CONFIG_MAX_ITERATIONS:-50}}"
PROVIDER="${CLI_PROVIDER:-$CONFIG_PROVIDER}"
MODEL="${CLI_MODEL:-$CONFIG_MODEL}"
FEATURE_ID="${CLI_FEATURE_ID:-$CONFIG_FEATURE_ID}"

# ── Validate required values ──────────────────────────────────────────
ERRORS=()

[ -z "$ORG" ]      && ERRORS+=("Missing required value: --org (Azure DevOps org URL)")
[ -z "$PROJECT" ]  && ERRORS+=("Missing required value: --project (Azure DevOps project name)")
[ -z "$PROVIDER" ] && ERRORS+=("Missing required value: --provider (claude-code or cursor-cli)")

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
  echo "Error: Invalid provider '$PROVIDER'. Must be 'claude-code' or 'cursor-cli'." >&2
  exit 1
fi

# ── Validate environment variables ───────────────────────────────────
ENV_ERRORS=()

if [ -z "${AZURE_DEVOPS_PAT:-}" ]; then
  ENV_ERRORS+=("Missing required environment variable: AZURE_DEVOPS_PAT")
fi

if [ "$PROVIDER" = "claude-code" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  ENV_ERRORS+=("Missing required environment variable: ANTHROPIC_API_KEY (required for provider=claude-code)")
fi

if [ "$PROVIDER" = "cursor-cli" ] && [ -z "${CURSOR_API_KEY:-}" ]; then
  ENV_ERRORS+=("Missing required environment variable: CURSOR_API_KEY (required for provider=cursor-cli)")
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
export AGENT_LOOP_FEATURE_ID="$FEATURE_ID"

echo "══════════════════════════════════════════════════════"
echo "  agent-loop"
echo "  Org:             $ORG"
echo "  Project:         $PROJECT"
echo "  Provider:        $PROVIDER${MODEL:+ ($MODEL)}"
echo "  Base branch:     $BASE_BRANCH"
echo "  Max iterations:  $MAX_ITERATIONS"
[ -n "$FEATURE_ID" ] && echo "  Feature ID:      $FEATURE_ID"
[ -n "$AREA_PATH" ]  && echo "  Area path:       $AREA_PATH"
[ -n "$TEAM" ]       && echo "  Team:            $TEAM"
[ -n "$REPO_URL" ]   && echo "  Repo URL:        $REPO_URL"
echo "══════════════════════════════════════════════════════"

# ── Lock manager ──────────────────────────────────────────────────────
LOCK_FILE="$WORKING_DIR/.agent-loop.lock"

acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    log_warn "Another instance is already running (lock file exists: $LOCK_FILE). Exiting."
    exit 0
  fi
  log_info "Lock acquired: $LOCK_FILE"
}

release_lock() {
  if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
    log_info "Lock released: $LOCK_FILE"
  fi
}

# ── Context manager ───────────────────────────────────────────────────
AGENT_CONTEXT_DIR="$WORKING_DIR/.agent-context"

ensure_gitignore() {
  local gitignore="$WORKING_DIR/.gitignore"
  if [ ! -f "$gitignore" ] || ! grep -qxF '.agent-context/' "$gitignore"; then
    echo '.agent-context/' >> "$gitignore"
    log_info ".agent-context/ added to .gitignore"
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
# "ready-for-agent" in "New" state, scoped to the configured areaPath.
# Prints one Feature ID per line.
query_eligible_features() {
  local wiql="SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.WorkItemType] = 'Feature'"
  if [ -n "$AREA_PATH" ]; then
    wiql+=" AND [Source].[System.AreaPath] UNDER '$AREA_PATH'"
  fi
  wiql+=" AND [Target].[System.Tags] CONTAINS 'ready-for-agent' AND [Target].[System.State] = 'New' AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' MODE (MustContain)"

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
# Scrum → "In Progress"; Agile/CMMI → "Active"; unknown → "In Progress".
get_in_progress_state() {
  case "${PROCESS:-}" in
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

  local payload
  payload=$(jq -n --arg s "$state" '[{"op":"add","path":"/fields/System.State","value":$s}]')

  local url="${ORG}/${PROJECT}/_apis/wit/workitems/${work_item_id}?api-version=7.1"
  _ado_call PATCH "$url" "$payload" "application/json-patch+json" || return 1
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
  if [ -z "$current_tags" ]; then
    new_tags="$tag"
  else
    new_tags="${current_tags}; ${tag}"
  fi

  local payload
  payload=$(jq -n --arg t "$new_tags" '[{"op":"add","path":"/fields/System.Tags","value":$t}]')

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

  if [ -z "$REPO_URL" ]; then
    log_error "create_pull_request: REPO_URL is not set — cannot determine repository for PR creation"
    return 1
  fi

  # Extract repository name from REPO_URL (last path segment after /_git/).
  local repo_id
  repo_id=$(printf '%s' "$REPO_URL" | sed 's|.*/_git/||' | sed 's|[/?].*||')

  if [ -z "$repo_id" ]; then
    log_error "create_pull_request: unable to parse repository name from REPO_URL='$REPO_URL'"
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

  local url="${ORG}/${PROJECT}/_apis/git/repositories/${repo_id}/pullrequests?api-version=7.1"
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

  local pr_web_url="${ORG}/${PROJECT}/_git/${repo_id}/pullrequest/${pr_id}"
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

acquire_lock
ensure_gitignore

# ── Agent dispatcher ───────────────────────────────────────────────────

# Assembles the prompt that will be sent to the AI agent.
# The prompt includes PBI title, description, and acceptance criteria,
# plus instructions to read feature context and signal completion.
# Usage: build_prompt <pbi_title> <pbi_description> <acceptance_criteria>
# Prints the assembled prompt string.
build_prompt() {
  local pbi_title="$1"
  local pbi_description="$2"
  local acceptance_criteria="$3"

  cat <<PROMPT
You are an autonomous software development agent implementing a Product Backlog Item (PBI).

## PBI Details

**Title:** ${pbi_title}

**Description:**
${pbi_description}

**Acceptance Criteria:**
${acceptance_criteria}

## Feature Context

Read the file \`.agent-context/feature.md\` in your working directory for additional context about the parent Feature this PBI belongs to.

## Instructions

1. Implement the PBI described above, satisfying all acceptance criteria.
2. Write, edit, and test code as needed using the tools available to you.
3. Commit your changes with a clear commit message referencing the work done.
4. Push the commit to the remote origin. Do NOT create a pull request.
5. When you have finished implementing and pushing all changes, output the exact string \`AGENT_COMPLETE\` on a line by itself to signal completion.
PROMPT
}

# Dispatches the configured AI provider with the given prompt and captures output.
# Globals set after return:
#   AGENT_INVOKE_EXIT_CODE  — exit code from the agent process
#   AGENT_INVOKE_COMPLETED  — "true" if AGENT_COMPLETE was detected in output, else "false"
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

  case "$PROVIDER" in
    claude-code)
      local model_args=()
      if [ -n "$MODEL" ]; then
        model_args=(--model "$MODEL")
      fi
      output=$(claude -p "$prompt" \
        --output-format json \
        "${model_args[@]}" \
        --allowedTools "Read,Write,Edit,Bash" \
        --max-turns "$MAX_ITERATIONS" 2>&1) || exit_code=$?
      ;;
    cursor-cli)
      output=$(agent -p "$prompt" --force --output-format json 2>&1) || exit_code=$?
      ;;
    *)
      log_error "invoke_agent: unknown provider '$PROVIDER'. Must be 'claude-code' or 'cursor-cli'."
      return 1
      ;;
  esac

  AGENT_INVOKE_EXIT_CODE=$exit_code

  if printf '%s' "$output" | grep -qF 'AGENT_COMPLETE'; then
    AGENT_INVOKE_COMPLETED="true"
  fi

  if [ "$exit_code" -ne 0 ]; then
    log_error "invoke_agent: agent exited with non-zero exit code $exit_code"
  fi

  printf '%s' "$output"
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
# Usage: process_pbi <pbi_id> <pbi_title> <pbi_description> <acceptance_criteria> <feature_branch> <feature_id>
# Returns 0 on success, 1 on failure.
process_pbi() {
  local pbi_id="$1"
  local pbi_title="$2"
  local pbi_description="$3"
  local acceptance_criteria="$4"
  local feature_branch="$5"
  local feature_id="$6"

  log_info "Starting inner loop for PBI $pbi_id: $pbi_title"

  # Set PBI state to the process-appropriate in-progress state before first agent invocation.
  local in_progress_state
  in_progress_state=$(get_in_progress_state)
  update_work_item_state "$pbi_id" "$in_progress_state" || {
    log_error "process_pbi: failed to set PBI $pbi_id to '$in_progress_state' — aborting"
    return 1
  }

  local prompt
  prompt=$(build_prompt "$pbi_title" "$pbi_description" "$acceptance_criteria")

  local iteration=1
  while [ "$iteration" -le "$MAX_ITERATIONS" ]; do
    log_info "Iteration ${iteration}/${MAX_ITERATIONS} for PBI ${pbi_id}"

    local agent_output
    agent_output=$(invoke_agent "$prompt")

    # Capture agent output to the context log for this feature.
    capture_agent_log "$feature_id" "$agent_output"

    # Stop condition: AGENT_COMPLETE signal AND clean+pushed working tree.
    if [ "$AGENT_INVOKE_COMPLETED" = "true" ] && check_clean_and_pushed "$feature_branch"; then
      log_info "PBI $pbi_id completed successfully after $iteration iteration(s)"
      add_work_item_tag "$pbi_id" "agent-done" || log_warn "process_pbi: failed to tag PBI $pbi_id as agent-done"
      return 0
    fi

    # If the agent process itself errored, stop retrying immediately.
    if [ "$AGENT_INVOKE_EXIT_CODE" -ne 0 ]; then
      log_error "process_pbi: agent exited with code $AGENT_INVOKE_EXIT_CODE on iteration $iteration — stopping"
      break
    fi

    iteration=$((iteration + 1))
  done

  log_error "process_pbi: PBI $pbi_id did not complete within $MAX_ITERATIONS iteration(s)"
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

FEATURE_TITLE=$(printf '%s' "$FEATURE_JSON" | jq -r '.fields["System.Title"] // ""')
FEATURE_DESCRIPTION=$(printf '%s' "$FEATURE_JSON" | jq -r '.fields["System.Description"] // ""')

log_info "Processing Feature $FEATURE_ID: $FEATURE_TITLE"

# Step 5: Fetch all child PBIs
log_info "Fetching child PBIs for Feature $FEATURE_ID"
PBIS_JSON=$(get_child_pbis "$FEATURE_ID") || {
  log_error "Failed to fetch child PBIs for Feature $FEATURE_ID"
  exit 1
}

PBI_COUNT=$(printf '%s' "$PBIS_JSON" | jq 'length')
if [ "$PBI_COUNT" -eq 0 ]; then
  log_info "Feature $FEATURE_ID has no child PBIs — nothing to do"
  exit 0
fi
log_info "Found $PBI_COUNT PBI(s) for Feature $FEATURE_ID"

# Step 6: Topologically sort PBIs by dependency
log_info "Sorting PBIs by dependency order"
SORTED_PBIS=$(sort_pbis_by_dependency "$PBIS_JSON") || {
  log_error "Failed to sort PBIs by dependency for Feature $FEATURE_ID"
  exit 1
}

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

# Step 9/10: Process each PBI serially; stop on first failure
FEATURE_SUCCESS=true
for i in $(seq 0 $((PBI_COUNT - 1))); do
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

# Step 11: Create PR only when all PBIs are tagged agent-done
if [ "$FEATURE_SUCCESS" = "true" ]; then
  log_info "All PBIs completed — creating pull request for Feature $FEATURE_ID"
  PR_URL=$(create_pull_request "$FEATURE_TITLE" "$FEATURE_BRANCH" "$SORTED_PBIS") || {
    log_error "Failed to create pull request for Feature $FEATURE_ID"
    exit 1
  }
  log_info "Feature $FEATURE_ID complete — PR: $PR_URL"
  exit 0
else
  log_error "Feature $FEATURE_ID processing failed — one or more PBIs did not complete"
  exit 1
fi
