create or replace TABLE ECOMMERCE.ANALYTICS.DIM_RETURN_REASON (
	RETURN_REASON_SK NUMBER(38,0) NOT NULL autoincrement start 0 increment 1 noorder COMMENT 'Surrogate key',
	REASON_CODE VARCHAR(16777216) NOT NULL COMMENT 'Natural key - reason code',
	REASON_DESC VARCHAR(16777216) NOT NULL COMMENT 'Human-readable reason',
	REASON_CATEGORY VARCHAR(16777216) NOT NULL COMMENT 'Reason grouping (Quality, Fit, Changed Mind, etc.)',
	ETL_LOADED_AT TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'Row load timestamp',
	ETL_SOURCE VARCHAR(16777216) DEFAULT 'SEED' COMMENT 'Source system identifier',
	constraint PK_DIM_RETURN_REASON primary key (RETURN_REASON_SK)
)COMMENT='Return reason dimension for returns analysis'
;