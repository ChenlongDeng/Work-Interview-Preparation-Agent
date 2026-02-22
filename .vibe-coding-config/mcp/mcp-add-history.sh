#!/usr/bin/env bash
# MCP command history ledger.
# This file is NOT executed during normal sync.
# `sync-configs.sh --import-history mcp` only imports lines with `# @mcp-add`.

# 2026-02-22 codex
# codex mcp add lark-mcp -- npx -y @larksuiteoapi/lark-mcp mcp -a '$LARK_MCP_APP_ID' -s '$LARK_MCP_APP_SECRET' --oauth
# @mcp-add {"name":"lark-mcp","command":"npx","args":["-y","@larksuiteoapi/lark-mcp","mcp","-a","${LARK_MCP_APP_ID}","-s","${LARK_MCP_APP_SECRET}","--oauth"],"env":{},"enabled":true}

# 2026-02-22 gemini
# gemini mcp add chrome-devtools -- npx chrome-devtools-mcp@latest
# @mcp-add {"name":"chrome-devtools","command":"npx","args":["chrome-devtools-mcp@latest"],"env":{},"enabled":true}

