#!/usr/bin/env bash
# lint-skill.sh — Lint and validate a Cortex Code SKILL.md file
# Usage: ./scripts/lint-skill.sh [path/to/SKILL.md]
set -euo pipefail

SKILL_FILE="${1:-SKILL.md}"
ERRORS=0
WARNINGS=0

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "ERROR: $SKILL_FILE not found"
  exit 1
fi

echo "=== Linting: $SKILL_FILE ==="
echo ""

# --- Frontmatter checks ---
echo "## Frontmatter"

if ! head -1 "$SKILL_FILE" | grep -q '^---$'; then
  echo "  [CRITICAL] Missing YAML frontmatter opening ---"
  ((ERRORS++))
fi

if ! grep -q '^name:' "$SKILL_FILE"; then
  echo "  [CRITICAL] Missing 'name' field in frontmatter"
  ((ERRORS++))
else
  NAME=$(grep '^name:' "$SKILL_FILE" | head -1 | sed 's/name: *//' | tr -d '"')
  if ! echo "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "  [CRITICAL] name '$NAME' is not kebab-case"
    ((ERRORS++))
  else
    echo "  [OK] name: $NAME"
  fi
fi

if ! grep -q '^description:' "$SKILL_FILE"; then
  echo "  [CRITICAL] Missing 'description' field"
  ((ERRORS++))
else
  if ! grep -qi 'triggers\?:' "$SKILL_FILE"; then
    echo "  [WARNING] description lacks trigger keywords"
    ((WARNINGS++))
  else
    echo "  [OK] description with triggers"
  fi
fi

# --- Structure checks ---
echo ""
echo "## Structure"

LINE_COUNT=$(wc -l < "$SKILL_FILE")
echo "  Lines: $LINE_COUNT"
if [[ $LINE_COUNT -gt 500 ]]; then
  echo "  [WARNING] Exceeds 500-line guideline ($LINE_COUNT lines)"
  ((WARNINGS++))
else
  echo "  [OK] Under 500-line limit"
fi

if ! grep -q '^## Workflow' "$SKILL_FILE"; then
  echo "  [CRITICAL] Missing '## Workflow' section"
  ((ERRORS++))
else
  echo "  [OK] Workflow section present"
fi

if ! grep -q '^## Stopping Points' "$SKILL_FILE"; then
  echo "  [CRITICAL] Missing '## Stopping Points' section"
  ((ERRORS++))
else
  echo "  [OK] Stopping Points section present"
fi

if ! grep -q '^## Output' "$SKILL_FILE"; then
  echo "  [WARNING] Missing '## Output' section"
  ((WARNINGS++))
else
  echo "  [OK] Output section present"
fi

# --- Workflow checks ---
echo ""
echo "## Workflow Quality"

STEP_COUNT=$(grep -cE '^### Step [0-9]' "$SKILL_FILE" || true)
echo "  Steps found: $STEP_COUNT"

STOP_COUNT=$(grep -c '⚠️ STOP' "$SKILL_FILE" || true)
echo "  Checkpoints (⚠️ STOP): $STOP_COUNT"
if [[ $STOP_COUNT -eq 0 ]]; then
  echo "  [CRITICAL] No ⚠️ STOP checkpoints found"
  ((ERRORS++))
fi

# Check for old-style STOP markers without emoji
OLD_STOP=$(grep -cE '\*\*STOP\*\*' "$SKILL_FILE" || true)
EMOJI_STOP=$(grep -c '⚠️ STOP' "$SKILL_FILE" || true)
if [[ $OLD_STOP -gt $EMOJI_STOP ]]; then
  echo "  [CRITICAL] Found **STOP** markers without ⚠️ emoji — use **⚠️ STOP**:"
  ((ERRORS++))
fi

HAND_COUNT=$(grep -c '✋' "$SKILL_FILE" || true)
echo "  Stopping point markers (✋): $HAND_COUNT"

# --- Linting checks ---
echo ""
echo "## Linting"

# Unclosed code fences
FENCE_COUNT=$(grep -c '```' "$SKILL_FILE" || true)
if (( FENCE_COUNT % 2 != 0 )); then
  echo "  [CRITICAL] Odd number of code fences ($FENCE_COUNT) — likely unclosed"
  ((ERRORS++))
else
  echo "  [OK] Code fences balanced ($FENCE_COUNT)"
fi

# Placeholder consistency
LOWER_PH=$(grep -oE '<[a-z_]+>' "$SKILL_FILE" | sort -u | wc -l || true)
UPPER_PH=$(grep -oE '<[A-Z_]+>' "$SKILL_FILE" | sort -u | wc -l || true)
if [[ $LOWER_PH -gt 0 && $UPPER_PH -gt 0 ]]; then
  echo "  [WARNING] Mixed placeholder styles: $LOWER_PH lowercase, $UPPER_PH uppercase"
  ((WARNINGS++))
else
  echo "  [OK] Consistent placeholder style"
fi

# Doubled words (use perl-compatible regex for backreference)
DOUBLES=$(grep -oPi '\b(\w+)\s+\1\b' "$SKILL_FILE" 2>/dev/null | head -5 || true)
if [[ -n "$DOUBLES" ]]; then
  echo "  [WARNING] Possible doubled words:"
  echo "$DOUBLES" | sed 's/^/    /'
  ((WARNINGS++))
else
  echo "  [OK] No doubled words"
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "  Errors:   $ERRORS"
echo "  Warnings: $WARNINGS"

if [[ $ERRORS -gt 0 ]]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
