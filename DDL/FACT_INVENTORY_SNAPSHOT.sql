create or replace TABLE ECOMMERCE.ANALYTICS.FACT_INVENTORY_SNAPSHOT cluster by (DATE_SK, WAREHOUSE_SK)(
	SNAPSHOT_SK NUMBER(38,0) NOT NULL autoincrement start 1 increment 1 noorder COMMENT 'Surrogate key',
	DATE_SK NUMBER(38,0) NOT NULL COMMENT 'FK to DIM_DATE - snapshot date',
	PRODUCT_SK NUMBER(38,0) NOT NULL COMMENT 'FK to DIM_PRODUCT',
	WAREHOUSE_SK NUMBER(38,0) NOT NULL COMMENT 'FK to DIM_WAREHOUSE',
	QUANTITY_ON_HAND NUMBER(10,0) NOT NULL COMMENT 'Units in stock (semi-additive: SUM across products, AVG across time)',
	QUANTITY_ON_ORDER NUMBER(10,0) NOT NULL DEFAULT 0 COMMENT 'Units on purchase order (semi-additive)',
	QUANTITY_RESERVED NUMBER(10,0) NOT NULL DEFAULT 0 COMMENT 'Units reserved for open orders (semi-additive)',
	QUANTITY_AVAILABLE NUMBER(10,0) NOT NULL COMMENT 'on_hand - reserved (semi-additive)',
	REORDER_POINT NUMBER(10,0) NOT NULL COMMENT 'Threshold to trigger reorder',
	IS_STOCKOUT BOOLEAN NOT NULL COMMENT 'True when quantity_available <= 0',
	DAYS_OF_SUPPLY NUMBER(5,1) COMMENT 'Estimated days of stock remaining',
	ETL_LOADED_AT TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'Row load timestamp',
	ETL_SOURCE VARCHAR(16777216) DEFAULT 'SEED' COMMENT 'Source system identifier',
	constraint PK_FACT_INVENTORY primary key (SNAPSHOT_SK),
	constraint FK_INV_DATE foreign key (DATE_SK) references ECOMMERCE.ANALYTICS.DIM_DATE(DATE_SK),
	constraint FK_INV_PRODUCT foreign key (PRODUCT_SK) references ECOMMERCE.ANALYTICS.DIM_PRODUCT(PRODUCT_SK),
	constraint FK_INV_WAREHOUSE foreign key (WAREHOUSE_SK) references ECOMMERCE.ANALYTICS.DIM_WAREHOUSE(WAREHOUSE_SK)
)COMMENT='Inventory periodic snapshot | Grain: one row per product per warehouse per day | Measures are semi-additive'
;