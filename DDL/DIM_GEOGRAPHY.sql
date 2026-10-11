create or replace TABLE ECOMMERCE.ANALYTICS.DIM_GEOGRAPHY (
	GEOGRAPHY_SK NUMBER(38,0) NOT NULL autoincrement start 0 increment 1 noorder COMMENT 'Surrogate key',
	CITY VARCHAR(16777216) NOT NULL COMMENT 'City name',
	STATE VARCHAR(16777216) COMMENT 'State or province',
	COUNTRY VARCHAR(16777216) NOT NULL COMMENT 'Country code',
	REGION VARCHAR(16777216) NOT NULL COMMENT 'Sales region',
	ETL_LOADED_AT TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'Row load timestamp',
	ETL_SOURCE VARCHAR(16777216) DEFAULT 'SEED' COMMENT 'Source system identifier',
	constraint PK_DIM_GEOGRAPHY primary key (GEOGRAPHY_SK)
)COMMENT='Conformed geography dimension for regional analysis without customer join'
;