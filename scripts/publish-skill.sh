#!/usr/bin/env bash
# publish-skill.sh — Lint, test, and publish the dimensional modeling skill
# Usage: ./scripts/publish-skill.sh [--dry-run] [--roles ROLE1,ROLE2]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
ROLES="PUBLIC"
DISCOVERABLE="--discoverable"

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)    DRY_RUN=true; shift ;;
    --roles)      ROLES="$2"; shift 2 ;;
    --private)    DISCOVERABLE="--no-discoverable"; shift ;;
    -h|--help)
      echo "Usage: publish-skill.sh [--dry-run] [--roles ROLE1,ROLE2] [--private]"
      echo ""
      echo "Options:"
      echo "  --dry-run   Lint and test only, do not publish"
      echo "  --roles     Comma-separated roles to grant READ (default: PUBLIC)"
      echo "  --private   Hide from skill catalog (private link only)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "============================================"
echo " Publish: snowflake-dimensional-modeling"
echo "============================================"
echo ""

# --- Step 1: Lint ---
echo ">>> Step 1: Linting SKILL.md"
if bash "$SCRIPT_DIR/lint-skill.sh" "$SKILL_DIR/SKILL.md"; then
  echo ""
  echo ">>> Lint: PASSED"
else
  echo ""
  echo ">>> Lint: FAILED — fix errors before publishing"
  exit 1
fi

# --- Step 2: Test (optional, skip if no connection) ---
echo ""
echo ">>> Step 2: Testing against ECOMMERCE.ANALYTICS"
if command -v cortex &>/dev/null; then
  if bash "$SCRIPT_DIR/test-skill.sh"; then
    echo ""
    echo ">>> Tests: PASSED"
  else
    echo ""
    echo ">>> Tests: FAILED — fix schema before publishing"
    exit 1
  fi
else
  echo "  [SKIP] cortex CLI not available — skipping integration tests"
fi

# --- Step 3: Publish ---
echo ""
if $DRY_RUN; then
  echo ">>> Step 3: DRY RUN — would publish with:"
  echo "  Directory:    $SKILL_DIR"
  echo "  Roles:        $ROLES"
  echo "  Discoverable: $DISCOVERABLE"
  echo ""
  echo "  Command: cortex skill catalog publish $SKILL_DIR $DISCOVERABLE --roles $ROLES"
  echo ""
  echo ">>> Dry run complete. No changes made."
  exit 0
fi

echo ">>> Step 3: Publishing to Snowflake account"

# Build role flags
ROLE_FLAGS=""
IFS=',' read -ra ROLE_ARR <<< "$ROLES"
for R in "${ROLE_ARR[@]}"; do
  ROLE_FLAGS+=" --roles $(echo "$R" | xargs)"
done

# Build description
DESCRIPTION='Design, review, and expand dimensional models (star/snowflake schemas) on Snowflake. Produces optimized DDL with clustering keys, constraints, and documentation.'

echo "  Publishing..."
cortex skill catalog publish "$SKILL_DIR" \
  $DISCOVERABLE \
  $ROLE_FLAGS \
  --description "$DESCRIPTION"

echo ""
echo ">>> Published successfully!"
echo ""
echo "Users can install by pasting the share URI into Cortex Code."
