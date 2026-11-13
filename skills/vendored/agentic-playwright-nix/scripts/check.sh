#!/usr/bin/env bash
# Read-only check: is Agentic Playwright wired into this Nix project?
#
# Run from the repository root. Exits 0 when the essentials are present and 1 when
# something must be fixed. It does not edit anything and does not start the test server.
set -uo pipefail

root=$(pwd)
fail=0

note() { printf '%s\n' "$*"; }
ok() { printf '  ok    %s\n' "$*"; }
miss() { printf '  MISS  %s\n' "$*"; fail=1; }
warn() { printf '  warn  %s\n' "$*"; }

note "Agentic Playwright check in $root"

if [ ! -f flake.nix ]; then
  miss "no flake.nix here; this check is for Nix projects"
fi
if ! command -v nix >/dev/null 2>&1; then
  miss "nix is not on PATH"
fi

runner=()
if command -v direnv >/dev/null 2>&1 && direnv exec . true >/dev/null 2>&1; then
  runner=(direnv exec .)
elif command -v nix >/dev/null 2>&1 && nix develop --command true >/dev/null 2>&1; then
  runner=(nix develop --command)
fi

if [ ${#runner[@]} -eq 0 ]; then
  miss "cannot enter the devshell with 'direnv exec .' or 'nix develop'"
else
  ok "devshell entry: ${runner[*]}"

  if out=$("${runner[@]}" playwright --version 2>/dev/null); then
    ok "playwright: $out"
  else
    miss "playwright is not on the devshell PATH; add pkgs.playwright-test"
  fi

  config=""
  for candidate in e2e/playwright.config.ts e2e/playwright.config.js \
    playwright.config.ts playwright.config.js; do
    if [ -f "$candidate" ]; then
      config=$candidate
      break
    fi
  done

  if [ -n "$config" ]; then
    ok "config: $config"
    listing=$("${runner[@]}" playwright test --list --config "$config" 2>&1) || true
    if printf '%s' "$listing" | grep -qi 'Cannot find module\|ERR_MODULE_NOT_FOUND'; then
      miss "@playwright/test does not resolve from the runner"
    elif printf '%s' "$listing" | grep -qi 'No tests found'; then
      warn "the config loads but there are no tests yet"
    else
      ok "the runner can list tests"
    fi
  else
    miss "no e2e/playwright.config.ts or playwright.config.ts"
  fi

  browsers=$("${runner[@]}" bash -c 'printf %s "${PLAYWRIGHT_BROWSERS_PATH:-}"' 2>/dev/null)
  if [ -n "$browsers" ] && [ -d "$browsers" ]; then
    ok "browsers: $browsers"
  else
    miss "PLAYWRIGHT_BROWSERS_PATH is unset or not a directory"
  fi
fi

# Claude Code's project-scoped MCP server.
if [ -f .mcp.json ]; then
  if grep -q '"playwright-test"' .mcp.json; then
    if grep -q '"npx"' .mcp.json; then
      miss ".mcp.json launches the MCP server with npx; use the flake's playwright"
    elif grep -q 'run-test-mcp-server' .mcp.json; then
      ok ".mcp.json: playwright-test wired"
    else
      miss ".mcp.json names playwright-test but not run-test-mcp-server"
    fi
  else
    warn ".mcp.json exists but has no playwright-test server"
  fi
else
  warn "no .mcp.json for Claude Code"
fi

# OpenCode's project config. A global server also works; verify it with
# `opencode mcp list` and accept a connected server there.
opencode_config=""
for candidate in opencode.json opencode.jsonc .opencode/opencode.json .opencode/opencode.jsonc; do
  if [ -f "$candidate" ]; then
    opencode_config=$candidate
    break
  fi
done
if [ -n "$opencode_config" ]; then
  if grep -q 'playwright-test' "$opencode_config" &&
    grep -q 'run-test-mcp-server' "$opencode_config"; then
    ok "OpenCode config: playwright-test wired ($opencode_config)"
  else
    warn "OpenCode config present but no playwright-test server"
  fi
else
  warn "no OpenCode project config; add one if you use OpenCode here"
fi

# The three agent definitions are useful but regenerable; missing is a warning.
agents_missing=0
for agent in planner generator healer; do
  if [ ! -f ".claude/agents/playwright-test-$agent.md" ]; then
    agents_missing=1
  fi
done
if [ "$agents_missing" -eq 0 ]; then
  ok "agents: planner, generator, healer"
else
  warn "agent definitions missing; run playwright init-agents --loop=claude -c <config>"
fi

# A cache-first worker plus unversioned assets is the stale-CSS trap. This is a
# heuristic: the real check is a page whose stylesheet URL carries `?v=`.
worker=""
for candidate in crates/qr-server/assets/sw.js public/sw.js static/sw.js src/sw.js; do
  if [ -f "$candidate" ]; then
    worker=$candidate
    break
  fi
done
if [ -n "$worker" ]; then
  if grep -Rqs --exclude-dir=target --exclude-dir=node_modules --exclude-dir=.git \
    '?v=' .; then
    ok "source mentions versioned asset URLs"
  else
    warn "a service worker caches assets but no '?v=' appears in the source; see the cache section"
  fi
fi

note ""
if [ "$fail" -eq 0 ]; then
  note "PASS: Agentic Playwright looks wired up."
  note "Prove it with a 390x844 screenshot that you open and describe before trusting it."
  exit 0
fi

note "FAIL: fix the MISS lines, or follow agentic-playwright-nix."
exit 1
