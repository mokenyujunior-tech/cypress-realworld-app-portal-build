#!/bin/bash
# =============================================================================
# fix-backend-urls.sh
# Fixes all hardcoded http://localhost:${backendPort}/... API calls so the
# frontend works in production on Azure (relative URLs) AND still works
# locally in dev (absolute localhost URLs).
#
# Run this from the ROOT of your fork:
#   bash fix-backend-urls.sh
# =============================================================================

set -e

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Sanity check ─────────────────────────────────────────────────────────────
[[ -f "package.json" ]] || error "Run this from the root of the repo (package.json not found)."
[[ -f "src/utils/portUtils.ts" ]] || error "src/utils/portUtils.ts not found — wrong directory?"

info "Starting PayFlow URL fix..."

# =============================================================================
# STEP 1 — Patch src/utils/portUtils.ts
# Add apiBaseUrl export that returns "" in production (relative URLs)
# and "http://localhost:${backendPort}" in development.
# =============================================================================
info "Patching src/utils/portUtils.ts ..."

PORTUTILS="src/utils/portUtils.ts"

# Check if already patched
if grep -q "apiBaseUrl" "$PORTUTILS"; then
  warn "apiBaseUrl already exists in portUtils.ts — skipping Step 1."
else
  # Append the new export after the existing exports
  cat >> "$PORTUTILS" << 'EOF'

// ---------------------------------------------------------------------------
// apiBaseUrl — use this for ALL frontend API calls instead of
// `http://localhost:${backendPort}/...`
//
// In production (Azure) the frontend and backend share the same domain,
// so relative URLs ("/login", "/users", etc.) are correct.
// In development Vite proxies don't apply to XHR/fetch in XState machines,
// so we need the full localhost URL.
// ---------------------------------------------------------------------------
export const apiBaseUrl: string = import.meta.env.PROD
  ? ""
  : `http://localhost:${backendPort}`;
EOF
  info "  ✓ apiBaseUrl added to portUtils.ts"
fi

# =============================================================================
# STEP 2 — Update imports in all machine files to pull in apiBaseUrl
# =============================================================================
MACHINE_FILES=(
  "src/machines/authMachine.ts"
  "src/machines/bankAccountsMachine.ts"
  "src/machines/contactsTransactionsMachine.ts"
  "src/machines/createTransactionMachine.ts"
  "src/machines/notificationsMachine.ts"
  "src/machines/personalTransactionsMachine.ts"
  "src/machines/publicTransactionsMachine.ts"
  "src/machines/transactionDetailMachine.ts"
  "src/machines/usersMachine.ts"
)

info "Updating imports in machine files..."

for FILE in "${MACHINE_FILES[@]}"; do
  if [[ ! -f "$FILE" ]]; then
    warn "  File not found, skipping: $FILE"
    continue
  fi

  # Already has apiBaseUrl imported?
  if grep -q "apiBaseUrl" "$FILE"; then
    warn "  Already patched: $FILE"
    continue
  fi

  # Replace: import { backendPort } from "../utils/portUtils";
  # With:    import { backendPort, apiBaseUrl } from "../utils/portUtils";
  # Also handles:  import { ..., backendPort } (with other named imports)
  if grep -q 'from "\.\./utils/portUtils"' "$FILE"; then
    sed -i 's/import { backendPort } from "\.\.\/utils\/portUtils"/import { backendPort, apiBaseUrl } from "..\/utils\/portUtils"/' "$FILE"
    # Handle cases where backendPort is imported alongside other things
    sed -i 's/import { \(.*\)backendPort\(.*\) } from "\.\.\/utils\/portUtils"/import { \1backendPort\2, apiBaseUrl } from "..\/utils\/portUtils"/' "$FILE"
    info "  ✓ Import updated: $FILE"
  else
    warn "  No portUtils import found in $FILE — manual check needed"
  fi
done

# =============================================================================
# STEP 3 — Replace all hardcoded localhost API call patterns
#
# Patterns found in the screenshots:
#   `http://localhost:${backendPort}/...`
#   'http://localhost:${backendPort}/...'  (single-quote template — rare)
#
# Replace with:
#   `${apiBaseUrl}/...`
# =============================================================================
info "Replacing hardcoded localhost URLs in machine files..."

for FILE in "${MACHINE_FILES[@]}"; do
  if [[ ! -f "$FILE" ]]; then
    continue
  fi

  # Replace backtick template literals:
  # `http://localhost:${backendPort}/anything`
  # →  `${apiBaseUrl}/anything`
  sed -i 's|`http://localhost:\${backendPort}|`${apiBaseUrl}|g' "$FILE"

  info "  ✓ URLs replaced: $FILE"
done

# =============================================================================
# STEP 4 — Fix backend/app.ts CORS (Image 1, line 32)
# Change:  origin: process.env.FRONTEND_URL || `http://localhost:${frontendPort}`
# To:      origin: process.env.FRONTEND_URL || `http://localhost:${frontendPort}`
#          (already has FRONTEND_URL fallback — ensure it is present)
#
# On Azure, set FRONTEND_URL env var = https://payflow-staging.azurewebsites.net
# The code already handles this correctly IF FRONTEND_URL is set.
# We just add a comment to make this obvious.
# =============================================================================
info "Checking backend/app.ts CORS config..."

APPFILE="backend/app.ts"
if [[ -f "$APPFILE" ]]; then
  if grep -q "CORS_NOTE_ADDED" "$APPFILE"; then
    warn "  CORS note already added — skipping."
  else
    sed -i 's|origin: process.env.FRONTEND_URL || `http://localhost:\${frontendPort}`|// CORS_NOTE_ADDED: Set FRONTEND_URL env var in Azure App Service to your frontend URL\n    origin: process.env.FRONTEND_URL \|\| `http://localhost:${frontendPort}`|' "$APPFILE"
    info "  ✓ CORS note added to backend/app.ts"
  fi
else
  warn "  backend/app.ts not found — skipping CORS step."
fi

# =============================================================================
# STEP 5 — Verification: grep for any remaining raw localhost:${backendPort}
# =============================================================================
info "Verifying — checking for any remaining hardcoded localhost calls..."

REMAINING=$(grep -rn 'http://localhost:\${backendPort}' src/machines/ 2>/dev/null || true)

if [[ -z "$REMAINING" ]]; then
  echo -e "\n${GREEN}✅ All done! Zero remaining hardcoded localhost API calls in src/machines/.${NC}"
else
  echo -e "\n${YELLOW}⚠️  Some instances were not replaced automatically:${NC}"
  echo "$REMAINING"
  echo ""
  warn "Fix these manually — replace the pattern with \`\${apiBaseUrl}/...\`"
fi

# =============================================================================
# STEP 6 — Reminder: what to do next
# =============================================================================
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN} NEXT STEPS${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  1. Run locally to confirm nothing broke:"
echo "       yarn dev"
echo "     Test login, signup, transactions. All should work as before."
echo ""
echo "  2. Set FRONTEND_URL in your Azure App Service environment variables:"
echo "       FRONTEND_URL = https://payflow-staging.azurewebsites.net"
echo "     (or your actual staging URL)"
echo ""
echo "  3. Commit and push:"
echo "       git add src/utils/portUtils.ts src/machines/ backend/app.ts"
echo "       git commit -m 'fix: use relative API URLs in production for Azure deployment'"
echo "       git push origin develop"
echo ""
echo "  4. GitHub Actions will pick it up and deploy to Azure."
echo "     Watch the Actions tab — the frontend should now call /login, /users"
echo "     instead of localhost:3001/login."
echo ""
