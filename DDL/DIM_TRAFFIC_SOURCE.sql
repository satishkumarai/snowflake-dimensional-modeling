create or replace TABLE ECOMMERCE.ANALYTICS.DIM_TRAFFIC_SOURCE (
	TRAFFIC_SOURCE_SK NUMBER(38,0) NOT NULL autoincrement start 0 increment 1 noorder COMMENT 'Surrogate key',
	SOURCE_NAME VARCHAR(16777216) NOT NULL COMMENT 'Traffic source name',
	SOURCE_MEDIUM VARCHAR(16777216) NOT NULL COMMENT 'Medium (organic, cpc, email, referral, direct, social)',
	SOURCE_CAMPAIGN VARCHAR(16777216) COMMENT 'Campaign name if applicable',
	ETL_LOADED_AT TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'Row load timestamp',
	ETL_SOURCE VARCHAR(16777216) DEFAULT 'SEED' COMMENT 'Source system identifier',
	constraint PK_DIM_TRAFFIC_SOURCE primary key (TRAFFIC_SOURCE_SK)
)COMMENT='Web traffic source dimension for session and conversion analysis'
;