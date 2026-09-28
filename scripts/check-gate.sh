#!/usr/bin/env bash
# Reproduces the Scaffold-HBAR template bounty eligibility gate:
#   scaffold -> template files -> install -> lint -> build -> boot + core routes -> no committed secrets.
#
# Usage:
#   scripts/check-gate.sh owner/repo[#ref]   scaffold from GitHub, exactly as judges do
#   scripts/check-gate.sh --local            scaffold from this checkout's committed files (before pushing)
#
# Needs: node >= 20.18.3, npm, git, make, Foundry (forge), curl.
set -euo pipefail

TARGET="${1:?usage: scripts/check-gate.sh owner/repo[#ref] | --local}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)"
PORT="${GATE_PORT:-3123}"
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1"; exit 1; }
pass() { printf '\033[32m✓ %s\033[0m\n' "$1"; }

step "Template manifest and required files"
node -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (!m.name) throw new Error("template.json: missing name");
  const c = m["create-scaffold-hbar"] ?? {};
  if (!c.capabilities || !c.defaults) throw new Error("template.json: missing capabilities/defaults");
' "$REPO_ROOT/template.json" || fail "template.json invalid"
for f in README.md AGENTS.md LICENCE; do [ -f "$REPO_ROOT/$f" ] || fail "$f missing"; done
pass "template.json valid; README.md, AGENTS.md, LICENCE present"

step "Scaffold"
if [ "$TARGET" = "--local" ]; then
  # Only committed files, as a GitHub download would see them.
  mkdir "$WORK/template"
  git -C "$REPO_ROOT" archive HEAD | tar -x -C "$WORK/template"
  export CREATE_SCAFFOLD_HBAR_TEMPLATE_DIR="$WORK/template"
  TEMPLATE="blank" # capabilities come from the manifest check above; files come from the local tree
else
  TEMPLATE="$TARGET"
fi
(cd "$WORK" && npx --yes create-scaffold-hbar@latest app -t "$TEMPLATE" -f nextjs-app -s foundry \
  --package-manager npm --skip-hedera-skills --ci) || fail "scaffold failed"
APP="$WORK/app"
[ -f "$APP/README.md" ] && [ -f "$APP/AGENTS.md" ] || fail "README.md / AGENTS.md missing from scaffold"
[ -d "$APP/node_modules" ] || fail "install did not run"
pass "scaffolded and installed"

step "No committed secrets"
if git -C "$APP" ls-files | grep -E '(^|/)\.env(\.local)?$'; then fail ".env file committed"; fi
if git -C "$APP" grep -nE '^(DEPLOYER_)?PRIVATE_KEY=.+' -- ':!*.example' >/dev/null; then fail "private key committed"; fi
pass "no .env or private keys tracked"

step "Lint"
(cd "$APP" && npm run lint) || fail "lint failed"
pass "lint clean"

step "Contracts: unit tests"
(cd "$APP" && npm run foundry:test) || fail "forge tests failed"
pass "forge tests pass"

step "Build"
(cd "$APP" && npm run next:build) || fail "build failed"
pass "next build clean"

step "Boot and probe core routes"
(cd "$APP/packages/nextjs" && npx next start -p "$PORT" >"$WORK/server.log" 2>&1) &
SERVER_PID=$!
for _ in $(seq 1 60); do curl -fs "http://localhost:$PORT" >/dev/null && break; sleep 1; done
for route in / /debug /blockexplorer; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT$route")
  [ "$code" = "200" ] || { cat "$WORK/server.log"; fail "GET $route -> $code"; }
  pass "GET $route -> 200"
done
# Without PYTH_API_KEY the Pyth proxy must answer 501 (documented degraded mode), never 500.
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/api/pyth-update?id=0x$(printf '0%.0s' $(seq 1 64))")
[ "$code" = "501" ] || [ "$code" = "200" ] || fail "GET /api/pyth-update -> $code"
pass "GET /api/pyth-update -> $code"

printf '\n\033[32m\033[1mGate passed.\033[0m\n'
