#!/usr/bin/env bash
# test-skill.sh — Validate the dimensional modeling skill against the live ECOMMERCE schema
# Usage: ./scripts/test-skill.sh
#
# SQL execution backends (tried in order):
#   1. snow sql          (Snowflake CLI / SnowSQL)
#   2. cortex sql        (Cortex Code CLI)
#   3. snowsql           (Legacy SnowSQL)
#
# Each backend must accept a query and return CSV with the result in the last row.
set -euo pipefail

echo "=== Testing snowflake-dimensional-modeling skill against ECOMMERCE.ANALYTICS ==="
echo ""

# --- Detect SQL backend ---
detect_backend() {
  if command -v snow &>/dev/null; then
    echo "snow"
  elif command -v cortex &>/dev/null; then
    echo "cortex"
  elif command -v snowsql &>/dev/null; then
    echo "snowsql"
  else
    echo "none"
  fi
}

BACKEND=$(detect_backend)

run_sql() {
  local sql="$1"
  case "$BACKEND" in
    snow)
      snow sql -q "$sql" --format csv 2>/dev/null | tail -1 | cut -d',' -f1
      ;;
    cortex)
      cortex sql -q "$sql" --format csv 2>/dev/null | tail -1 | cut -d',' -f1
      ;;
    snowsql)
      snowsql -q "$sql" -o output_format=csv -o header=false -o friendly=false 2>/dev/null | tail -1 | tr -d '[:space:]'
      ;;
    *)
      echo "ERROR"
      ;;
  esac
}

if [[ "$BACKEND" == "none" ]]; then
  echo "ERROR: No SQL backend found. Install one of: snow (Snowflake CLI), cortex, snowsql"
  echo ""
  echo "Alternatively, run these checks directly via Snowflake SQL:"
  echo "  -- Table count"
  echo "  SELECT COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='ANALYTICS';"
  echo "  -- Constraint count"
  echo "  SELECT CONSTRAINT_TYPE, COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLE_CONSTRAINTS"
  echo "    WHERE TABLE_SCHEMA='ANALYTICS' GROUP BY CONSTRAINT_TYPE;"
  exit 1
fi

echo "Using backend: $BACKEND"
echo ""

PASS=0
FAIL=0

run_check() {
  local label="$1"
  local sql="$2"
  local expect_min="$3"

  local result
  result=$(run_sql "$sql" || echo "ERROR")

  if [[ "$result" == "ERROR" || -z "$result" ]]; then
    echo "  [FAIL] $label — query error"
    ((FAIL++))
    return
  fi

  if [[ "$result" -ge "$expect_min" ]] 2>/dev/null; then
    echo "  [PASS] $label — got $result (expected >= $expect_min)"
    ((PASS++))
  else
    echo "  [FAIL] $label — got $result (expected >= $expect_min)"
    ((FAIL++))
  fi
}

# --- Table existence ---
echo "## Table Existence"

EXPECTED_TABLES=(
  DIM_DATE DIM_CUSTOMER DIM_PRODUCT DIM_GEOGRAPHY
  DIM_PAYMENT_METHOD DIM_WAREHOUSE DIM_RETURN_REASON DIM_TRAFFIC_SOURCE
  FACT_ORDER_LINE FACT_RETURN FACT_INVENTORY_SNAPSHOT FACT_CUSTOMER_SESSION
)

for TBL in "${EXPECTED_TABLES[@]}"; do
  COUNT=$(run_sql "SELECT COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='ANALYTICS' AND TABLE_NAME='$TBL'" || echo "0")
  if [[ "$COUNT" == "1" ]]; then
    echo "  [PASS] $TBL exists"
    ((PASS++))
  else
    echo "  [FAIL] $TBL missing"
    ((FAIL++))
  fi
done

# --- Row counts ---
echo ""
echo "## Row Counts"
run_check "DIM_DATE rows"                "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.DIM_DATE" 2000
run_check "DIM_CUSTOMER rows"            "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.DIM_CUSTOMER" 20
run_check "DIM_PRODUCT rows"             "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.DIM_PRODUCT" 20
run_check "FACT_ORDER_LINE rows"         "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_ORDER_LINE" 100
run_check "FACT_RETURN rows"             "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_RETURN" 50
run_check "FACT_INVENTORY_SNAPSHOT rows" "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_INVENTORY_SNAPSHOT" 1000
run_check "FACT_CUSTOMER_SESSION rows"   "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_CUSTOMER_SESSION" 100

# --- Constraint integrity (fact-checked: 12 PK + 16 FK = 28) ---
echo ""
echo "## Constraints"
run_check "Primary keys count"   "SELECT COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='ANALYTICS' AND CONSTRAINT_TYPE='PRIMARY KEY'" 12
run_check "Foreign keys count"   "SELECT COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='ANALYTICS' AND CONSTRAINT_TYPE='FOREIGN KEY'" 16
run_check "Total constraints"    "SELECT COUNT(*) FROM ECOMMERCE.INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='ANALYTICS'" 28

# --- Zero-value rows ---
echo ""
echo "## Zero-Value Dimension Rows"

declare -A DIM_SK_MAP=(
  [DIM_CUSTOMER]=CUSTOMER_SK
  [DIM_PRODUCT]=PRODUCT_SK
  [DIM_GEOGRAPHY]=GEOGRAPHY_SK
  [DIM_PAYMENT_METHOD]=PAYMENT_METHOD_SK
  [DIM_WAREHOUSE]=WAREHOUSE_SK
  [DIM_RETURN_REASON]=RETURN_REASON_SK
  [DIM_TRAFFIC_SOURCE]=TRAFFIC_SOURCE_SK
)

for DIM in "${!DIM_SK_MAP[@]}"; do
  SK_COL="${DIM_SK_MAP[$DIM]}"
  COUNT=$(run_sql "SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.$DIM WHERE $SK_COL = 0" || echo "0")
  if [[ "$COUNT" == "1" ]]; then
    echo "  [PASS] $DIM has zero-value row (${SK_COL}=0)"
    ((PASS++))
  else
    echo "  [FAIL] $DIM missing zero-value row (${SK_COL}=0)"
    ((FAIL++))
  fi
done

# --- Orphan FK check (fact rows referencing non-existent dimension keys) ---
echo ""
echo "## Referential Integrity (Orphan FKs)"

declare -A ORPHAN_CHECKS=(
  ["FACT_ORDER_LINE→DATE"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_ORDER_LINE f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_DATE d ON f.DATE_SK=d.DATE_SK WHERE d.DATE_SK IS NULL"
  ["FACT_ORDER_LINE→CUSTOMER"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_ORDER_LINE f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_CUSTOMER d ON f.CUSTOMER_SK=d.CUSTOMER_SK WHERE d.CUSTOMER_SK IS NULL"
  ["FACT_ORDER_LINE→PRODUCT"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_ORDER_LINE f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_PRODUCT d ON f.PRODUCT_SK=d.PRODUCT_SK WHERE d.PRODUCT_SK IS NULL"
  ["FACT_RETURN→DATE"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_RETURN f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_DATE d ON f.RETURN_DATE_SK=d.DATE_SK WHERE d.DATE_SK IS NULL"
  ["FACT_RETURN→PRODUCT"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_RETURN f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_PRODUCT d ON f.PRODUCT_SK=d.PRODUCT_SK WHERE d.PRODUCT_SK IS NULL"
  ["FACT_INVENTORY→DATE"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_INVENTORY_SNAPSHOT f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_DATE d ON f.DATE_SK=d.DATE_SK WHERE d.DATE_SK IS NULL"
  ["FACT_SESSION→CUSTOMER"]="SELECT COUNT(*) FROM ECOMMERCE.ANALYTICS.FACT_CUSTOMER_SESSION f LEFT JOIN ECOMMERCE.ANALYTICS.DIM_CUSTOMER d ON f.CUSTOMER_SK=d.CUSTOMER_SK WHERE d.CUSTOMER_SK IS NULL"
)

for CHECK_LABEL in "${!ORPHAN_CHECKS[@]}"; do
  COUNT=$(run_sql "${ORPHAN_CHECKS[$CHECK_LABEL]}" || echo "ERROR")
  if [[ "$COUNT" == "0" ]]; then
    echo "  [PASS] $CHECK_LABEL — no orphans"
    ((PASS++))
  else
    echo "  [FAIL] $CHECK_LABEL — $COUNT orphan rows"
    ((FAIL++))
  fi
done

# --- Cross-fact join test (pre-aggregated to avoid fan-out) ---
echo ""
echo "## Cross-Fact Joins"
CROSS_RESULT=$(run_sql "
SELECT COUNT(*) FROM (
  SELECT p.PRODUCT_SK,
         COALESCE(o.REV, 0) - COALESCE(r.REF, 0) AS NET
  FROM ECOMMERCE.ANALYTICS.DIM_PRODUCT p
  LEFT JOIN (SELECT PRODUCT_SK, SUM(LINE_TOTAL) AS REV FROM ECOMMERCE.ANALYTICS.FACT_ORDER_LINE GROUP BY PRODUCT_SK) o ON p.PRODUCT_SK = o.PRODUCT_SK
  LEFT JOIN (SELECT PRODUCT_SK, SUM(REFUND_AMOUNT) AS REF FROM ECOMMERCE.ANALYTICS.FACT_RETURN GROUP BY PRODUCT_SK) r ON p.PRODUCT_SK = r.PRODUCT_SK
  WHERE p.PRODUCT_SK > 0
)" || echo "0")

if [[ "$CROSS_RESULT" -ge 1 ]] 2>/dev/null; then
  echo "  [PASS] Cross-fact drill-across (pre-aggregated, no fan-out) — $CROSS_RESULT products"
  ((PASS++))
else
  echo "  [FAIL] Cross-fact join returned no results"
  ((FAIL++))
fi

# --- Summary ---
echo ""
echo "=== Test Summary ==="
echo "  Backend: $BACKEND"
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: ALL TESTS PASSED"
  exit 0
fi
