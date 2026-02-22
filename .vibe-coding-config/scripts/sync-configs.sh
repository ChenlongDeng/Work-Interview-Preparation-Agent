#!/usr/bin/env bash
set -euo pipefail

# Project-local source of truth files.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_FILE="$ROOT_DIR/.vibe-coding-config/mcp/mcp.json"
MEMORY_FILE="$ROOT_DIR/.vibe-coding-config/memory/AGENTS.md"
ENV_FILE="$ROOT_DIR/.vibe-coding-config/.env.mcp.local"
CLAUDE_PROJECT_MCP_FILE="$ROOT_DIR/.mcp.json"
GEMINI_PROJECT_SETTINGS="$ROOT_DIR/.gemini/settings.json"

# Target config files for each tool.
CODEX_CONFIG="$HOME/.codex/config.toml"
GEMINI_CONFIG="$HOME/.gemini/settings.json"
CLAUDE_CONFIG="$HOME/.claude.json"

MODE="${1:-all}"
SCOPE="project"

usage() {
  cat <<'EOF'
Usage:
  sync-configs.sh [--scope project|global] mcp
  sync-configs.sh [--scope project|global] memory
  sync-configs.sh [--scope project|global] all
  sync-configs.sh [--scope project|global] dry-run

Default scope: project
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 1
  fi
}

load_mcp_servers() {
  # We keep one JSON schema in repo and always read from `mcpServers`.
  # If a string is like ${VAR}, it is resolved from environment variables.
  jq -e '
    def resolve:
      if type == "string" and test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$") then
        .[2:-1] as $k
        | (env[$k] // error("Missing env var: " + $k)) as $v
        | if ($v | length) == 0 then error("Empty env var: " + $k) else $v end
      elif type == "array" then map(resolve)
      elif type == "object" then with_entries(.value |= resolve)
      else . end;
    (.mcpServers // error("missing mcpServers in mcp.json")) | resolve
  ' "$MCP_FILE"
}

render_codex_mcp_block() {
  # Codex uses TOML, so we render from JSON -> TOML text block.
  local servers_json="$1"
  printf '%s' "$servers_json" | jq -r '
    to_entries
    | map(
        "[mcp_servers.\(.key)]\n"
        + "command = \(.value.command | @json)\n"
        + "args = \((.value.args // []) | @json)\n"
        + (
            if ((.value.env // {}) | length) > 0 then
              "[mcp_servers.\(.key).env]\n"
              + (
                  (.value.env // {})
                  | to_entries
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

rewrite_codex_config() {
  local servers_json="$1"
  local block stripped tmp
  local begin="# >>> vibe-coding-config mcp >>>"
  local end="# <<< vibe-coding-config mcp <<<"

  mkdir -p "$(dirname "$CODEX_CONFIG")"
  [[ -f "$CODEX_CONFIG" ]] || : >"$CODEX_CONFIG"

  stripped="$(mktemp)"
  # Keep user's existing config, but replace only our managed block.
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$CODEX_CONFIG" >"$stripped"

  block="$(render_codex_mcp_block "$servers_json")"

  tmp="$(mktemp)"
  cat "$stripped" >"$tmp"
  [[ -s "$tmp" ]] && echo >>"$tmp"
  echo "$begin" >>"$tmp"
  [[ -n "$block" ]] && printf '%s\n' "$block" >>"$tmp"
  echo "$end" >>"$tmp"
  mv "$tmp" "$CODEX_CONFIG"
  rm -f "$stripped"
  echo "ok: updated $CODEX_CONFIG"
}

rewrite_json_key() {
  # For JSON configs we only overwrite the `mcpServers` key.
  local target="$1"
  local servers_json="$2"
  local expr="$3"
  local tmp

  mkdir -p "$(dirname "$target")"
  [[ -f "$target" ]] || echo "{}" >"$target"

  tmp="$(mktemp)"
  jq --argjson servers "$servers_json" "$expr" "$target" >"$tmp"
  mv "$tmp" "$target"
  echo "ok: updated $target"
}

sync_mcp() {
  # Sync one repo file to all three MCP targets.
  require_jq
  [[ -f "$MCP_FILE" ]] || { echo "error: missing $MCP_FILE" >&2; exit 1; }
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi

  local servers
  servers="$(load_mcp_servers)"

  if [[ "$SCOPE" == "global" ]]; then
    rewrite_codex_config "$servers"
    rewrite_json_key "$GEMINI_CONFIG" "$servers" '.mcpServers = $servers'
    rewrite_json_key "$CLAUDE_CONFIG" "$servers" '.mcpServers = ($servers | with_entries(.value |= (. + {type: "stdio"})))'
  else
    mkdir -p "$(dirname "$CLAUDE_PROJECT_MCP_FILE")"
    mkdir -p "$(dirname "$GEMINI_PROJECT_SETTINGS")"

    rewrite_json_key "$CLAUDE_PROJECT_MCP_FILE" "$servers" '.mcpServers = ($servers | with_entries(.value |= (. + {type: "stdio"})))'
    rewrite_json_key "$GEMINI_PROJECT_SETTINGS" "$servers" '.mcpServers = $servers'
    echo "note: codex MCP project scope is not persisted by config file; skipped in project scope."
    echo "note: use --scope global if you want to update ~/.codex/config.toml"
  fi
}

sync_memory() {
  # Root files are compatibility entrypoints only (symlinks).
  mkdir -p "$(dirname "$MEMORY_FILE")"
  [[ -f "$MEMORY_FILE" ]] || : >"$MEMORY_FILE"

  ln -sfn "$MEMORY_FILE" "$ROOT_DIR/AGENTS.md"
  ln -sfn "$MEMORY_FILE" "$ROOT_DIR/CLAUDE.md"
  ln -sfn "$MEMORY_FILE" "$ROOT_DIR/GEMINI.md"
  echo "ok: linked AGENTS.md / CLAUDE.md / GEMINI.md"
}

dry_run() {
  # Preview mode for quick sanity check before writing to home configs.
  require_jq
  echo "dry-run: no files changed"
  echo "scope: $SCOPE"
  echo "mcp source: $MCP_FILE"
  echo "env file: $ENV_FILE (optional)"
  echo "memory source: $MEMORY_FILE"
  echo "targets:"
  if [[ "$SCOPE" == "global" ]]; then
    echo "- $CODEX_CONFIG"
    echo "- $GEMINI_CONFIG"
    echo "- $CLAUDE_CONFIG"
  else
    echo "- $CLAUDE_PROJECT_MCP_FILE"
    echo "- $GEMINI_PROJECT_SETTINGS"
    echo "- codex skipped in project scope"
  fi
  echo "- $ROOT_DIR/AGENTS.md"
  echo "- $ROOT_DIR/CLAUDE.md"
  echo "- $ROOT_DIR/GEMINI.md"
  echo "mcp servers:"
  jq -r '.mcpServers | keys[]?' "$MCP_FILE" | sed 's/^/- /'
}

parse_args() {
  local args=("$@")
  local idx=0
  while [[ $idx -lt ${#args[@]} ]]; do
    case "${args[$idx]}" in
      --scope)
        idx=$((idx + 1))
        if [[ $idx -ge ${#args[@]} ]]; then
          echo "error: --scope requires value: project|global" >&2
          exit 1
        fi
        SCOPE="${args[$idx]}"
        ;;
      mcp|memory|all|dry-run)
        MODE="${args[$idx]}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: ${args[$idx]}" >&2
        usage
        exit 1
        ;;
    esac
    idx=$((idx + 1))
  done

  if [[ "$SCOPE" != "project" && "$SCOPE" != "global" ]]; then
    echo "error: invalid scope: $SCOPE (expected project|global)" >&2
    exit 1
  fi
}

parse_args "$@"
case "$MODE" in
  mcp) sync_mcp ;;
  memory) sync_memory ;;
  all) sync_mcp; sync_memory ;;
  dry-run) dry_run ;;
  -h|--help) usage ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
