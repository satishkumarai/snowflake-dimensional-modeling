---
name: snowflake-dimensional-modeling
description: "Design, review, and expand dimensional models (star/snowflake schemas) on Snowflake. Use when: designing a new data model, reviewing an existing schema, expanding a model with new fact tables, creating fact/dimension tables, modeling for analytics. Triggers: dimensional modeling, star schema, snowflake schema, fact table, dimension table, data model, design schema, review schema, model my data, design warehouse, analytical model, expand model, add fact table, inventory snapshot, returns model, customer sessions."
---

# Snowflake Dimensional Modeling

Design new dimensional models from natural language, review and improve existing schemas, or expand models with additional fact tables. Produces Snowflake-optimized DDL with clustering keys, constraints, sample data, and documentation.

## Workflow

### Step 1: Determine Mode

Ask the user which mode they need:

- **Design New**: User describes the business process or data they want to model
- **Review & Improve**: User provides table names or a database/schema to evaluate and fix
- **Expand**: User has an existing dimensional model and wants to add more fact tables or dimensions

If unclear from context, ask:

```
What would you like to do?
1. Design New — describe the business process to model
2. Review & Improve — provide existing tables or schema to evaluate
3. Expand — add more fact tables to an existing dimensional model
```

**⚠️ STOP**: Confirm mode and gather input before proceeding.

**For Design New mode**, collect:
- Business process to model (e.g., "sales orders", "customer support tickets")
- Key business questions the model should answer
- Known source systems or tables (if any)
- Expected query patterns (e.g., "aggregate by region and month")
- Target database.schema for the new tables (or confirm a default)

**For Review & Improve mode**, collect:
- Target database.schema or specific table names
- Known pain points (e.g., "queries are slow", "hard to join", "too many columns")

**For Expand mode**, collect:
- Target database.schema of the existing dimensional model
- Which business processes to add (e.g., "returns", "inventory", "web sessions")
- Key business questions the new facts should answer

### Step 2: Discover and Inspect Sources

**For Design New mode:**
- If the user named source tables, use `snowflake-object-discovery` to locate them
- Run `cortex search table-details "DB.SCHEMA.TABLE"` on each source to get columns, types, and relationships
- If no sources named, proceed to Step 3 with the business description alone

**For Review & Improve mode:**
- Use `snowflake-object-discovery` to find the tables
- Inspect each table with `cortex search table-details`
- Run the following diagnostics via SQL:

```sql
-- Full table inventory
SHOW TABLES IN SCHEMA <DB>.<SCHEMA>;

-- Column details with comments
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COMMENT
FROM <DB>.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '<SCHEMA>'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- Constraints inventory
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM <DB>.INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = '<SCHEMA>'
ORDER BY TABLE_NAME, CONSTRAINT_TYPE;

-- Row counts and key uniqueness per table
SELECT COUNT(*) AS ROW_COUNT,
       COUNT(DISTINCT <CANDIDATE_KEY>) AS DISTINCT_KEYS
FROM <TABLE>;
```

- **Audit checklist** — check each table for:

| Check | Severity | Description |
|-------|----------|-------------|
| Orphan tables | 🔴 | Tables with no FK relationships, no surrogate keys, no audit columns — not part of the star schema |
| Missing natural keys | 🟡 | Dimensions without a business key column (only surrogate key) |
| Missing constraints | 🟡 | Fact tables without FK constraints, dimensions without PK |
| Low data retention | 🟡 | `DATA_RETENTION_TIME_IN_DAYS = 1` on dimensional tables (should be 7+ for Time Travel) |
| Missing search optimization | 🟡 | Point-lookup dimensions (date, customer) without search optimization |
| Embedded dimensions | 🟢 | Attributes on a dimension that should be a separate conformed dimension (e.g., geography embedded in customer) |
| Missing measures | 🟢 | Common business measures absent from fact tables (e.g., shipping cost, tax) |
| Grain violations | 🔴 | Fact table rows not matching the stated grain |
| Missing comments | 🟡 | Tables or key columns without COMMENT metadata |

Present findings as a severity-ranked report with specific fix recommendations, then ask which fixes to apply.

**For Expand mode:**
- Run the same inspection as Review mode to understand the existing model
- Identify existing conformed dimensions that new facts can reuse
- Identify dimension gaps — which new dimensions are needed for the new business processes
- Map which existing dimensions each new fact will reference

**⚠️ STOP** (Review & Expand modes): Present audit findings or expansion design before making changes.

### Step 3: Design the Model

Apply Kimball dimensional modeling principles tailored to Snowflake:

#### 3a: Identify the Grain

- Determine the most atomic level of detail for the fact table
- State the grain as a clear business sentence (e.g., "One row per order line item per day")

#### 3b: Identify Dimensions

For each dimension:

| Attribute | Decision |
|-----------|----------|
| Name | `DIM_<BUSINESS_CONCEPT>` |
| Surrogate key | `<DIM>_SK` (INTEGER AUTOINCREMENT) |
| Natural key | Original business key, kept as attribute |
| SCD type | Type 1 (overwrite) unless the user needs history, then Type 2 with `EFFECTIVE_FROM`, `EFFECTIVE_TO`, `IS_CURRENT` |
| Key attributes | Columns used for grouping/filtering |

**Date dimension**: If no date dimension exists, offer to generate a standard `DIM_DATE` spanning a configurable range (default: 10 years) with calendar and fiscal attributes (year, quarter, month, week, day of week, is_holiday, fiscal_year, fiscal_quarter).

Snowflake-specific considerations:
- Use `VARCHAR` without length limits (Snowflake stores only actual bytes)
- Use `TIMESTAMP_NTZ` for timestamps unless timezone needed
- Use `NUMBER(38,0)` for surrogate keys
- Add `COMMENT` on table and key columns for documentation

#### 3c: Identify Facts

For each fact table:

| Attribute | Decision |
|-----------|----------|
| Name | `FACT_<BUSINESS_PROCESS>` |
| Grain | One sentence stating the grain |
| Measures | Additive, semi-additive, or non-additive classification |
| Foreign keys | References to each dimension's surrogate key |
| Degenerate dimensions | Order numbers, transaction IDs kept on fact |

Fact table types to consider:
- **Transaction fact**: One row per event (most common)
  - Example: `FACT_ORDER_LINE` — one row per order line item; measures: quantity, unit_price, discount, line_total, tax, shipping_cost
  - Example: `FACT_RETURN` — one row per returned item; measures: quantity_returned, refund_amount, restocking_fee
  - Example: `FACT_CUSTOMER_SESSION` — one row per web session; measures: page_views, session_duration, products_viewed, added_to_cart; flags: is_bounce, is_converted
- **Periodic snapshot**: One row per entity per time period — measures are **semi-additive** (can SUM across non-time dimensions, but AVG or latest across time)
  - Example: `FACT_INVENTORY_SNAPSHOT` — one row per product per warehouse per day; measures: quantity_on_hand, quantity_available, days_of_supply; flag: is_stockout
- **Accumulating snapshot**: One row per process instance with milestone dates
  - Example: `FACT_ORDER_FULFILLMENT` — one row per order with ORDER_DATE_SK, SHIP_DATE_SK, DELIVERY_DATE_SK as role-playing dimension FKs to DIM_DATE

**Semi-additive measure guidance**: When a fact table uses periodic snapshots, mark semi-additive measures in COMMENT (e.g., `COMMENT 'Units in stock (semi-additive: SUM across products, AVG across time)'`). This prevents incorrect aggregation in BI tools.

#### 3d: Snowflake Optimization

Apply these Snowflake-specific optimizations:

- **Clustering keys**: Recommend based on common filter/join columns. Prefer 2-4 columns max. Date columns first for time-series queries.
- **Search optimization**: Recommend `ALTER TABLE ... ADD SEARCH OPTIMIZATION` for point-lookup dimensions.
- **Constraints**: Add `NOT NULL` on foreign keys and surrogate keys. Use informational `PRIMARY KEY` and `FOREIGN KEY` for documentation (Snowflake does not enforce them but BI tools read them).
- **Zero-value dimension rows**: Include a default "Unknown" row (SK = 0) in each dimension to handle late-arriving facts.
- **Transient vs permanent**: Recommend `TRANSIENT` for staging/intermediate tables; permanent for final dimensional tables with `DATA_RETENTION_TIME_IN_DAYS` set to 7+ days.

#### 3e: Conformed Dimensions and Cross-Fact Joins

When multiple fact tables exist, enforce conformed dimensions:

- **Reuse existing dimensions** across all fact tables that share a business concept. Never create a one-off copy of DIM_DATE or DIM_CUSTOMER for a single fact.
- **Conformed geography**: Extract geographic attributes (city, state, country, region) into a shared `DIM_GEOGRAPHY` rather than embedding them in `DIM_CUSTOMER`. This allows geographic analysis on any fact table without routing through customer.
- **Role-playing dimensions**: A single `DIM_DATE` can serve multiple roles on one fact table (ORDER_DATE_SK, SHIP_DATE_SK, DELIVERY_DATE_SK). Each FK is a separate role-playing reference to the same dimension.
- **New dimensions for new facts**: When expanding, identify which new concepts need their own dimension (e.g., `DIM_WAREHOUSE` for inventory, `DIM_RETURN_REASON` for returns, `DIM_TRAFFIC_SOURCE` for web sessions). Each new dimension gets the standard treatment: surrogate key, natural key, zero-value row, audit columns.
- **Cross-fact drill-across**: Design fact tables so that shared conformed dimensions enable drill-across queries. Example: joining `FACT_ORDER_LINE` and `FACT_RETURN` on `DIM_PRODUCT` for net revenue = gross revenue - refunds.

**⚠️ STOP**: Present the model design summary before generating DDL.

### Step 4: Present the Design

Present the model as:

1. **Model summary table:**

```
| Table | Type | Grain | Key Columns | Clustering Key |
|-------|------|-------|-------------|----------------|
| FACT_SALES | Transaction Fact | One row per order line | ORDER_SK, PRODUCT_SK, DATE_SK | (ORDER_DATE, REGION_SK) |
| DIM_CUSTOMER | Dimension (SCD1) | One row per customer | CUSTOMER_SK | None |
| ... | ... | ... | ... | ... |
```

2. **Relationship summary**: Which facts reference which dimensions
3. **Design rationale**: Key decisions and trade-offs made
4. **Recommendations** (Review mode only): What to change and why

**⚠️ STOP**: Get user approval or change requests before generating DDL.

### Step 5: Generate DDL

Produce complete Snowflake DDL following these templates. All `<PLACEHOLDERS>` should be substituted with actual values.

```sql
CREATE OR REPLACE TABLE <DB>.<SCHEMA>.DIM_<NAME> (
    <NAME>_SK        NUMBER(38,0) NOT NULL AUTOINCREMENT START 0 INCREMENT 1
                     COMMENT 'Surrogate key',
    <NATURAL_KEY>    <TYPE> NOT NULL
                     COMMENT 'Natural business key from source',
    <ATTRIBUTES...>
    -- SCD Type 2 columns (if applicable)
    EFFECTIVE_FROM   TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
                     COMMENT 'Row effective start',
    EFFECTIVE_TO     TIMESTAMP_NTZ DEFAULT '9999-12-31'::TIMESTAMP_NTZ
                     COMMENT 'Row effective end',
    IS_CURRENT       BOOLEAN NOT NULL DEFAULT TRUE
                     COMMENT 'Current version flag',
    -- Audit columns
    ETL_LOADED_AT    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
                     COMMENT 'Row load timestamp',
    ETL_SOURCE       VARCHAR
                     COMMENT 'Source system identifier',
    CONSTRAINT PK_DIM_<NAME> PRIMARY KEY (<NAME>_SK)
)
COMMENT = '<BUSINESS_DESCRIPTION>'
CLUSTER BY (<CLUSTERING_COLUMNS>)  -- only if recommended
;
```

```sql
CREATE OR REPLACE TABLE <DB>.<SCHEMA>.FACT_<NAME> (
    <NAME>_SK        NUMBER(38,0) NOT NULL AUTOINCREMENT START 0 INCREMENT 1
                     COMMENT 'Surrogate key',
    <DIM>_SK         NUMBER(38,0) NOT NULL
                     COMMENT 'FK to DIM_<DIM>',
    <MEASURES...>
    -- Degenerate dimensions
    <DEGENERATE_DIM> VARCHAR COMMENT 'Degenerate dimension',
    -- Audit columns
    ETL_LOADED_AT    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ETL_SOURCE       VARCHAR,
    CONSTRAINT PK_FACT_<NAME> PRIMARY KEY (<NAME>_SK),
    CONSTRAINT FK_FACT_<NAME>_DIM_<DIM> FOREIGN KEY (<DIM>_SK) REFERENCES DIM_<DIM>(<DIM>_SK)
)
COMMENT = '<BUSINESS_DESCRIPTION> | Grain: <GRAIN_STATEMENT>'
CLUSTER BY (<DATE_COLUMN>, <HIGH_CARDINALITY_FK>)
;
```

Also generate:
- `INSERT` statement for the zero-value "Unknown" row in each dimension
- `ALTER TABLE ... ADD SEARCH OPTIMIZATION` where recommended

Present the full DDL but **do not execute** until the user confirms.

**⚠️ STOP**: Ask user to review DDL. Execute only on explicit approval.

### Step 6: Execute and Verify

On user approval:

1. Execute each DDL statement via `snowflake_sql_execute`
2. Run verification:
   ```sql
   SHOW TABLES LIKE '%DIM_%' IN SCHEMA <DB>.<SCHEMA>;
   SHOW TABLES LIKE '%FACT_%' IN SCHEMA <DB>.<SCHEMA>;
   ```
3. Confirm all tables created, constraints registered, and clustering keys applied
4. Present final summary of what was created

If a DDL statement fails, present the error, diagnose the cause (missing schema, insufficient privileges, name conflict), and suggest a fix before retrying. Maximum 2 retries per statement.

### Step 7: Generate Sample Data (Optional)

If the user requests sample data or the model was created from scratch with no source tables:

**Dimensions:**
- Insert zero-value "Unknown" row (SK = 0) in every dimension first
- Generate realistic seed data with 10-25 rows per dimension
- Use `SELECT column1, column2, ... FROM VALUES (...)` syntax for inserts with explicit SK values

**DIM_DATE generation pattern:**
```sql
WITH date_series AS (
    SELECT DATEADD(DAY, SEQ4(), '<START_DATE>'::DATE) AS DT
    FROM TABLE(GENERATOR(ROWCOUNT => <DAYS>))
)
SELECT
    TO_NUMBER(TO_CHAR(DT, 'YYYYMMDD')) AS DATE_SK,
    DT AS FULL_DATE,
    -- derive all calendar and fiscal attributes from DT
FROM date_series;
```

**Fact tables:**
- Generate 100-500 rows for transaction facts using `UNIFORM()` for random FK selection
- For periodic snapshots, use `CROSS JOIN` of date range x products x warehouses for full coverage
- Compute derived measures inline (e.g., `LINE_TOTAL = QUANTITY * UNIT_PRICE - DISCOUNT`)
- Use `UNIFORM(min, max, RANDOM())` for realistic variance — note that Snowflake requires constant bounds for `UNIFORM()`, so pre-compute random values in a CTE when bounds are dynamic

**Cross-fact consistency:**
- Returns should reference existing orders (sample from `FACT_ORDER_LINE`)
- Session conversion orders should reference existing `ORDER_NUMBER` values
- Inventory snapshot dates should overlap with order date ranges

**⚠️ STOP**: Ask if user wants sample data before generating.

## Stopping Points

- ✋ Step 1: Mode and input confirmed
- ✋ Step 2: Audit findings presented (Review & Expand modes) — user selects fixes
- ✋ Step 3: Model design presented — user approves or requests changes
- ✋ Step 4: Design summary reviewed
- ✋ Step 5: DDL generated — user approves before execution
- ✋ Step 6: Final verification presented
- ✋ Step 7: Ask before generating sample data

## Design Principles

These guide every decision in the skill:

1. **Grain first**: Always define the grain before choosing dimensions or measures
2. **Conformed dimensions**: Reuse dimensions across fact tables; do not create one-off copies
3. **Snowflake-native**: Leverage VARIANT for semi-structured attributes, AUTOINCREMENT for surrogate keys, and clustering for performance — not indexes
4. **Queryable documentation**: Use COMMENT on every table and key column so `SHOW TABLES` and `DESCRIBE TABLE` serve as a living data dictionary
5. **Auditability**: Every table gets `ETL_LOADED_AT` and `ETL_SOURCE` columns
6. **Defensive defaults**: Zero-value dimension rows, NOT NULL on keys and FKs, informational constraints for BI tool compatibility

## Output

- Model design summary table with grain, keys, and clustering recommendations
- Star schema relationship diagram (ASCII art showing dimension-to-fact connections)
- Complete Snowflake DDL (CREATE TABLE, constraints, clustering, search optimization)
- Zero-value dimension inserts
- Sample data generation (optional, on request)
- Cross-fact verification queries (e.g., net revenue = orders - returns, conversion funnel by source)
- Audit report with severity-ranked findings (Review & Expand modes)
