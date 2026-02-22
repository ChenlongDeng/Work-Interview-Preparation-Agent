#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VIBE_DIR="$ROOT_DIR/.vibe-coding-config"

# MCP source files.
MCP_TEMPLATE_FILE="$VIBE_DIR/mcp/mcp.template.json"
MCP_LEGACY_TEMPLATE_FILE="$VIBE_DIR/mcp/mcp.example.json"
MCP_HISTORY_FILE="$VIBE_DIR/mcp/mcp-add-history.sh"
ENV_FILE="$VIBE_DIR/.env.mcp.local"

# MCP targets.
CLAUDE_PROJECT_MCP_FILE="$ROOT_DIR/.mcp.json"
CODEX_PROJECT_CONFIG="$ROOT_DIR/.codex/config.toml"

# Memory source file.
MEMORY_FILE="$VIBE_DIR/memory/AGENTS.md"

# Skills and agents.
SKILLS_SOURCE_DIR="$VIBE_DIR/skills"
CODEX_SKILLS_LINK="$ROOT_DIR/.agents/skills"
CODEX_SKILLS_LINK_TARGET="../.vibe-coding-config/skills"
CLAUDE_AGENTS_DIR="$ROOT_DIR/.claude/agents"
CODEX_AGENT_SOURCE_FILE="$VIBE_DIR/agents.toml"
CODEX_PROFILE_SOURCE_DIR="$VIBE_DIR/agent-profiles"
CODEX_PROFILE_TARGET_DIR="$ROOT_DIR/.codex/agents/profiles"

MCP_BEGIN="# >>> vibe-coding-config mcp >>>"
MCP_END="# <<< vibe-coding-config mcp <<<"
AGENTS_BEGIN="# >>> vibe-coding-config agents >>>"
AGENTS_END="# <<< vibe-coding-config agents <<<"
MANAGED_MARKER="<!-- managed-by: vibe-coding-config -->"

MODE="all"
IMPORT_HISTORY=false

usage() {
  cat <<'TXT'
Usage:
  sync-configs.sh mcp
  sync-configs.sh memory
  sync-configs.sh skills
  sync-configs.sh agents
  sync-configs.sh all
  sync-configs.sh dry-run

Options:
  --import-history   Import '# @mcp-add {...}' entries from mcp-add-history.sh
TXT
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 1
  fi
}

load_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

resolve_env_placeholders() {
  jq -e '
    def resolve:
      if type == "string" and test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$") then
        .[2:-1] as $k
        | (env[$k] // error("Missing env var: " + $k)) as $v
        | if ($v | length) == 0 then error("Empty env var: " + $k) else $v end
      elif type == "array" then map(resolve)
      elif type == "object" then with_entries(.value |= resolve)
      else . end;
    resolve
  '
}

history_servers_json() {
  if [[ "$IMPORT_HISTORY" != "true" || ! -f "$MCP_HISTORY_FILE" ]]; then
    echo "{}"
    return
  fi

  local lines parsed
  lines="$(awk '/^# @mcp-add / { sub(/^# @mcp-add /, ""); print }' "$MCP_HISTORY_FILE" || true)"
  if [[ -z "$lines" ]]; then
    echo "{}"
    return
  fi

  if ! parsed="$(printf '%s\n' "$lines" | jq -cs '
      map(fromjson? | select(type == "object" and (.name | type == "string")))
      | map({ key: .name, value: (del(.name)) })
      | from_entries
    ')"; then
    echo "warn: failed to parse $MCP_HISTORY_FILE, skip history import" >&2
    echo "{}"
    return
  fi

  echo "$parsed"
}

load_mcp_servers() {
  require_jq
  load_env_file

  local template_file
  if [[ -f "$MCP_TEMPLATE_FILE" ]]; then
    template_file="$MCP_TEMPLATE_FILE"
  elif [[ -f "$MCP_LEGACY_TEMPLATE_FILE" ]]; then
    template_file="$MCP_LEGACY_TEMPLATE_FILE"
    echo "warn: using legacy template file $MCP_LEGACY_TEMPLATE_FILE" >&2
  else
    echo "error: missing MCP template file" >&2
    echo "expected: $MCP_TEMPLATE_FILE" >&2
    exit 1
  fi

  local base_servers history_servers merged
  base_servers="$(jq -e '.mcpServers // error("missing mcpServers in template file")' "$template_file")"
  history_servers="$(history_servers_json)"

  merged="$(jq -n \
    --argjson base "$base_servers" \
    --argjson history "$history_servers" \
    '$base * $history')"

  printf '%s' "$merged" | resolve_env_placeholders
}

render_codex_mcp_block() {
  local servers_json="$1"
  printf '%s' "$servers_json" | jq -r '
    to_entries
    | sort_by(.key)
    | map(
        "[mcp_servers.\(.key | @json)]\n"
        + (if .value.command then "command = \(.value.command | @json)\n" else "" end)
        + (if .value.url then "url = \(.value.url | @json)\n" else "" end)
        + (if (.value.args | type) == "array" then "args = \(.value.args | @json)\n" else "" end)
        + (if .value.bearer_token_env_var then "bearer_token_env_var = \(.value.bearer_token_env_var | @json)\n" else "" end)
        + (
            if ((.value.env // {}) | length) > 0 then
              "[mcp_servers.\(.key | @json).env]\n"
              + (
                  (.value.env // {})
                  | to_entries
                  | sort_by(.key)
                  | map("\(.key) = \(.value | @json)")
                  | join("\n")
                ) + "\n"
            else
              ""
            end
          )
      )
    | join("\n")
  '
}

replace_managed_block() {
  local target="$1"
  local begin="$2"
  local end="$3"
  local block="$4"
  local stripped tmp target_dir

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  [[ -f "$target" ]] || : >"$target"

  stripped="$(mktemp "$target_dir/.vbc-strip.XXXXXX")"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$target" >"$stripped"

  tmp="$(mktemp "$target_dir/.vbc-out.XXXXXX")"
  cat "$stripped" >"$tmp"
  [[ -s "$tmp" ]] && echo >>"$tmp"
  echo "$begin" >>"$tmp"
  [[ -n "$block" ]] && printf '%s\n' "$block" >>"$tmp"
  echo "$end" >>"$tmp"
  mv "$tmp" "$target"
  rm -f "$stripped"
}

write_json() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  jq . >"$target"
}

sync_mcp() {
  local servers claude_servers codex_block
  servers="$(load_mcp_servers)"
  claude_servers="$(printf '%s' "$servers" | jq '
    with_entries(
      .value |= (
        if ((.type // "") == "" and has("command")) then
          . + { type: "stdio" }
        else
          .
        end
      )
    )')"

  jq -n --argjson servers "$claude_servers" '{ mcpServers: $servers }' | write_json "$CLAUDE_PROJECT_MCP_FILE"
  echo "ok: updated $CLAUDE_PROJECT_MCP_FILE"

  codex_block="$(render_codex_mcp_block "$servers")"
  replace_managed_block "$CODEX_PROJECT_CONFIG" "$MCP_BEGIN" "$MCP_END" "$codex_block"
  echo "ok: updated $CODEX_PROJECT_CONFIG (mcp block)"
}

sync_memory() {
  mkdir -p "$(dirname "$MEMORY_FILE")"
  [[ -f "$MEMORY_FILE" ]] || : >"$MEMORY_FILE"

  ln -sfn ".vibe-coding-config/memory/AGENTS.md" "$ROOT_DIR/AGENTS.md"
  ln -sfn ".vibe-coding-config/memory/AGENTS.md" "$ROOT_DIR/CLAUDE.md"
  if [[ -L "$ROOT_DIR/GEMINI.md" ]]; then
    rm -f "$ROOT_DIR/GEMINI.md"
    echo "ok: removed legacy GEMINI.md symlink"
  fi
  echo "ok: linked AGENTS.md / CLAUDE.md"
}

is_managed_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  IFS= read -r first_line <"$file" || true
  [[ "$first_line" == "$MANAGED_MARKER" ]]
}

yaml_single_quote() {
  local value="$1"
  value="$(printf '%s' "$value" | sed "s/'/''/g")"
  printf "'%s'" "$value"
}

extract_codex_agents_to_tmp() {
  local source_file="$1"
  local out_dir="$2"
  [[ -f "$source_file" ]] || return 0

  awk -v out="$out_dir" '
function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}

function unescape_basic(s, t) {
  t = s
  gsub(/\\\\/, "\001", t)
  gsub(/\\"/, "\"", t)
  gsub(/\\n/, "\n", t)
  gsub(/\\t/, "\t", t)
  gsub(/\001/, "\\", t)
  return t
}

function write_tools(path, tools_buf, n, i, parts) {
  n = split(tools_buf, parts, /\n/)
  for (i = 1; i <= n; i++) {
    if (parts[i] != "") print parts[i] > path
  }
  close(path)
}

function flush_agent(safe, prefix) {
  if (current_name == "") return
  safe = current_name
  gsub(/[^A-Za-z0-9._-]/, "_", safe)

  if (current_desc == "") current_desc = current_name
  if (current_prompt == "") current_prompt = "You are " current_name "."

  prefix = out "/" safe
  print current_name > (prefix ".name")
  close(prefix ".name")
  print current_desc > (prefix ".desc")
  close(prefix ".desc")
  printf "%s", current_prompt > (prefix ".prompt")
  close(prefix ".prompt")
  print current_model > (prefix ".model")
  close(prefix ".model")
  if (current_tools != "") write_tools(prefix ".tools", current_tools)

  current_desc = ""
  current_prompt = ""
  current_model = ""
  current_tools = ""
}

BEGIN {
  in_prompt = 0
  prompt_buf = ""
  current_name = ""
}

{
  line = $0
  sub(/\r$/, "", line)

  if (in_prompt) {
    marker_pos = index(line, "\"\"\"")
    if (marker_pos > 0) {
      prompt_buf = prompt_buf substr(line, 1, marker_pos - 1)
      current_prompt = prompt_buf
      prompt_buf = ""
      in_prompt = 0
    } else {
      prompt_buf = prompt_buf line "\n"
    }
    next
  }

  stripped = line
  sub(/^[ \t]+/, "", stripped)
  if (stripped == "" || stripped ~ /^#/) next

  if (match(stripped, /^\[agents\.[A-Za-z0-9._-]+\][ \t]*$/)) {
    flush_agent()
    current_name = stripped
    sub(/^\[agents\./, "", current_name)
    sub(/\][ \t]*$/, "", current_name)
    next
  }

  if (current_name == "") next

  if (match(stripped, /^description[ \t]*=[ \t]*".*"([ \t]*#.*)?$/)) {
    value = stripped
    sub(/^description[ \t]*=[ \t]*"/, "", value)
    sub(/"[ \t]*(#.*)?$/, "", value)
    current_desc = unescape_basic(value)
    next
  }

  if (match(stripped, /^model[ \t]*=[ \t]*".*"([ \t]*#.*)?$/)) {
    value = stripped
    sub(/^model[ \t]*=[ \t]*"/, "", value)
    sub(/"[ \t]*(#.*)?$/, "", value)
    current_model = unescape_basic(value)
    next
  }

  if (match(stripped, /^prompt[ \t]*=[ \t]*"""/)) {
    value = stripped
    sub(/^prompt[ \t]*=[ \t]*"""/, "", value)
    marker_pos = index(value, "\"\"\"")
    if (marker_pos > 0) {
      current_prompt = substr(value, 1, marker_pos - 1)
    } else {
      in_prompt = 1
      prompt_buf = value
      if (prompt_buf != "") prompt_buf = prompt_buf "\n"
    }
    next
  }

  if (match(stripped, /^prompt[ \t]*=[ \t]*".*"([ \t]*#.*)?$/)) {
    value = stripped
    sub(/^prompt[ \t]*=[ \t]*"/, "", value)
    sub(/"[ \t]*(#.*)?$/, "", value)
    current_prompt = unescape_basic(value)
    next
  }

  if (match(stripped, /^tools[ \t]*=[ \t]*\[.*\][ \t]*$/)) {
    value = stripped
    sub(/^tools[ \t]*=[ \t]*\[/, "", value)
    sub(/\][ \t]*$/, "", value)
    current_tools = ""
    while (match(value, /"([^"\\]|\\.)*"/)) {
      item = substr(value, RSTART + 1, RLENGTH - 2)
      item = unescape_basic(item)
      if (current_tools == "") current_tools = item
      else current_tools = current_tools "\n" item
      value = substr(value, RSTART + RLENGTH)
    }
    next
  }
}

END {
  if (in_prompt) {
    print "error: unterminated triple-quoted prompt in " FILENAME > "/dev/stderr"
    exit 1
  }
  flush_agent()
}
  ' "$source_file"
}

sync_skills() {
  mkdir -p "$SKILLS_SOURCE_DIR" "$(dirname "$CODEX_SKILLS_LINK")"

  if [[ -e "$CODEX_SKILLS_LINK" && ! -L "$CODEX_SKILLS_LINK" ]]; then
    rm -rf "$CODEX_SKILLS_LINK"
  fi
  ln -sfn "$CODEX_SKILLS_LINK_TARGET" "$CODEX_SKILLS_LINK"
  echo "ok: linked $CODEX_SKILLS_LINK -> $CODEX_SKILLS_LINK_TARGET"

  # Bridge to Claude slash commands is disabled.
  # We only clean up command files previously generated by this script.
  if [[ -d "$ROOT_DIR/.claude/commands" ]]; then
    shopt -s nullglob
    local existing
    for existing in "$ROOT_DIR/.claude/commands"/*.md; do
      is_managed_file "$existing" || continue
      rm -f "$existing"
      echo "ok: removed managed claude command $existing"
    done
    shopt -u nullglob
  fi
}

sync_agents() {
  mkdir -p "$(dirname "$CODEX_PROJECT_CONFIG")" "$CLAUDE_AGENTS_DIR" "$CODEX_PROFILE_SOURCE_DIR" "$CODEX_PROFILE_TARGET_DIR"

  # Mirror codex agent profiles to runtime location with staging swap.
  local profiles_parent profiles_stage profiles_old
  profiles_parent="$(dirname "$CODEX_PROFILE_TARGET_DIR")"
  mkdir -p "$profiles_parent"
  profiles_stage="$(mktemp -d "$profiles_parent/.profiles-stage.XXXXXX")"

  if find "$CODEX_PROFILE_SOURCE_DIR" -mindepth 1 -print -quit | grep -q .; then
    cp -R "$CODEX_PROFILE_SOURCE_DIR"/. "$profiles_stage"/
  fi

  profiles_old=""
  if [[ -e "$CODEX_PROFILE_TARGET_DIR" ]]; then
    profiles_old="$(mktemp -d "$profiles_parent/.profiles-old.XXXXXX")"
    mv "$CODEX_PROFILE_TARGET_DIR" "$profiles_old/profiles"
  fi
  if mv "$profiles_stage" "$CODEX_PROFILE_TARGET_DIR"; then
    [[ -n "$profiles_old" ]] && rm -rf "$profiles_old"
  else
    rm -rf "$profiles_stage"
    if [[ -n "$profiles_old" && -e "$profiles_old/profiles" ]]; then
      mv "$profiles_old/profiles" "$CODEX_PROFILE_TARGET_DIR"
      rm -rf "$profiles_old"
    fi
    echo "error: failed to swap profiles into $CODEX_PROFILE_TARGET_DIR" >&2
    exit 1
  fi
  echo "ok: synced codex profiles to $CODEX_PROFILE_TARGET_DIR"

  local codex_agents_block=""
  if [[ -f "$CODEX_AGENT_SOURCE_FILE" ]]; then
    codex_agents_block="$(cat "$CODEX_AGENT_SOURCE_FILE")"
  fi
  replace_managed_block "$CODEX_PROJECT_CONFIG" "$AGENTS_BEGIN" "$AGENTS_END" "$codex_agents_block"
  echo "ok: updated $CODEX_PROJECT_CONFIG (agents block)"

  local keep_file
  keep_file="$(mktemp)"
  local extract_dir
  extract_dir="$(mktemp -d)"

  if [[ -f "$CODEX_AGENT_SOURCE_FILE" ]]; then
    if ! extract_codex_agents_to_tmp "$CODEX_AGENT_SOURCE_FILE" "$extract_dir"; then
      rm -rf "$extract_dir"
      rm -f "$keep_file"
      echo "error: failed to parse $CODEX_AGENT_SOURCE_FILE" >&2
      exit 1
    fi
  fi

  shopt -s nullglob
  local name_file key name desc prompt model target
  local tools_file tool_line
  for name_file in "$extract_dir"/*.name; do
    key="$(basename "$name_file" .name)"
    name="$(cat "$name_file")"
    desc="$(cat "$extract_dir/$key.desc" 2>/dev/null || true)"
    prompt="$(cat "$extract_dir/$key.prompt" 2>/dev/null || true)"
    model="$(cat "$extract_dir/$key.model" 2>/dev/null || true)"
    tools_file="$extract_dir/$key.tools"

    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "warn: skip agent with unsupported name '$name' (only [A-Za-z0-9._-])" >&2
      continue
    fi
    target="$CLAUDE_AGENTS_DIR/${name}.md"

    # Do not overwrite user's unmanaged file with the same name.
    if [[ -f "$target" ]] && ! is_managed_file "$target"; then
      echo "warn: skip unmanaged file $target" >&2
      continue
    fi

    {
      echo "$MANAGED_MARKER"
      echo "---"
      echo "name: $(yaml_single_quote "$name")"
      echo "description: $(yaml_single_quote "${desc:-$name}")"
      if [[ -n "$model" ]]; then
        echo "model: $(yaml_single_quote "$model")"
      fi
      if [[ -f "$tools_file" && -s "$tools_file" ]]; then
        echo "tools:"
        while IFS= read -r tool_line; do
          [[ -n "$tool_line" ]] || continue
          echo "  - $(yaml_single_quote "$tool_line")"
        done <"$tools_file"
      fi
      echo "---"
      echo "${prompt:-You are $name.}"
    } >"$target"

    echo "$(basename "$target")" >>"$keep_file"
    echo "ok: exported claude agent $target"
  done

  local existing file_base
  for existing in "$CLAUDE_AGENTS_DIR"/*.md; do
    is_managed_file "$existing" || continue
    file_base="$(basename "$existing")"
    if ! grep -Fxq "$file_base" "$keep_file"; then
      rm -f "$existing"
      echo "ok: removed stale managed agent $existing"
    fi
  done

  shopt -u nullglob
  rm -rf "$extract_dir"
  rm -f "$keep_file"
}

dry_run() {
  local template_file
  template_file="$MCP_TEMPLATE_FILE"
  [[ -f "$template_file" ]] || template_file="$MCP_LEGACY_TEMPLATE_FILE"

  echo "dry-run: no files changed"
  echo "mode: project-only (no home directory writes)"
  echo "mcp template: $template_file"
  echo "env file: $ENV_FILE (optional)"
  echo "history import: $IMPORT_HISTORY"
  echo "memory source: $MEMORY_FILE"
  echo "skills source: $SKILLS_SOURCE_DIR"
  echo "codex agent source: $CODEX_AGENT_SOURCE_FILE"
  echo "codex profile source: $CODEX_PROFILE_SOURCE_DIR"
  echo "targets:"
  echo "- $CLAUDE_PROJECT_MCP_FILE"
  echo "- $CODEX_PROJECT_CONFIG (managed blocks only)"
  echo "- $CODEX_PROFILE_TARGET_DIR (mirrored from source)"
  echo "- $CODEX_SKILLS_LINK"
  echo "- $CLAUDE_AGENTS_DIR/*.md (managed marker only)"
  echo "- $ROOT_DIR/AGENTS.md"
  echo "- $ROOT_DIR/CLAUDE.md"

  local servers
  if servers="$(load_mcp_servers 2>/dev/null)"; then
    echo "mcp servers:"
    printf '%s' "$servers" | jq -r 'keys[]?' | sed 's/^/- /'
  else
    echo "mcp servers: <unable to resolve, check template/env>"
  fi
}

import_history() {
  IMPORT_HISTORY=true
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    MODE="all"
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --import-history)
        import_history
        ;;
      mcp|memory|skills|agents|all|dry-run)
        MODE="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

parse_args "$@"
case "$MODE" in
  mcp) sync_mcp ;;
  memory) sync_memory ;;
  skills) sync_skills ;;
  agents) sync_agents ;;
  all) sync_mcp; sync_memory; sync_skills; sync_agents ;;
  dry-run) dry_run ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
