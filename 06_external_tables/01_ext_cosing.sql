-- =====================================================================
-- 06_external_tables/01_ext_cosing.sql
--
-- External tables let you SELECT from a flat file as if it were a
-- table. No loader process, no intermediate copy, and the file can be
-- swapped without touching the definition.
--
-- Two things bite everyone the first time:
--   1. The directory must be readable by the ORACLE OS user, not you.
--   2. Column order here must match the file exactly. Check the header
--      row before you assume.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CosIng ingredient export (CSV)
-- Adjust the field list to whatever your download actually contains --
-- the export layout has changed over the years.
-- ---------------------------------------------------------------------
CREATE TABLE ext_cosing_ingredient (
  cosing_ref_no  VARCHAR2(100),
  inci_name      VARCHAR2(1000),
  inn_name       VARCHAR2(1000),
  ph_eur_name    VARCHAR2(1000),
  cas_no         VARCHAR2(500),
  ec_no          VARCHAR2(500),
  chem_desc      VARCHAR2(4000),
  restriction    VARCHAR2(4000),
  functions      VARCHAR2(2000),
  update_date    VARCHAR2(50)
)
ORGANIZATION EXTERNAL (
  TYPE oracle_loader
  DEFAULT DIRECTORY inci_data_in
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET AL32UTF8
    BADFILE  inci_data_bad : 'cosing_ingredient.bad'
    LOGFILE  inci_data_bad : 'cosing_ingredient.log'
    SKIP 1                                  -- header row
    FIELDS TERMINATED BY ','
           OPTIONALLY ENCLOSED BY '"'
           LRTRIM
           MISSING FIELD VALUES ARE NULL
    REJECT ROWS WITH ALL NULL FIELDS
    (
      cosing_ref_no  CHAR(100),
      inci_name      CHAR(1000),
      inn_name       CHAR(1000),
      ph_eur_name    CHAR(1000),
      cas_no         CHAR(500),
      ec_no          CHAR(500),
      chem_desc      CHAR(4000),
      restriction    CHAR(4000),
      functions      CHAR(2000),
      update_date    CHAR(50)
    )
  )
  LOCATION ('COSING_INGREDIENTS.csv')
)
REJECT LIMIT UNLIMITED;

-- ---------------------------------------------------------------------
-- Open Beauty Facts JSONL as one CLOB per line.
--
-- This is far faster than reading the file with UTL_FILE in PL/SQL, and
-- it lets you use JSON_TABLE directly against the external table:
--
--   SELECT jt.*
--     FROM ext_obf_jsonl e,
--          JSON_TABLE(e.payload, '$'
--            COLUMNS (
--              barcode      VARCHAR2(20)  PATH '$.code',
--              product_name VARCHAR2(500) PATH '$.product_name',
--              brand_name   VARCHAR2(200) PATH '$.brands',
--              categories   VARCHAR2(500) PATH '$.categories',
--              inci_text    VARCHAR2(4000) PATH '$.ingredients_text'
--            )) jt;
--
-- Note the field size: a JSONL line can exceed 4000 bytes, so the
-- column is a CLOB and the access parameter reads to end of line.
-- ---------------------------------------------------------------------
CREATE TABLE ext_obf_jsonl (
  payload CLOB
)
ORGANIZATION EXTERNAL (
  TYPE oracle_loader
  DEFAULT DIRECTORY inci_data_in
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET AL32UTF8
    BADFILE inci_data_bad : 'obf_products.bad'
    LOGFILE inci_data_bad : 'obf_products.log'
    FIELDS
    (
      payload CHAR(100000)
    )
  )
  LOCATION ('OBF_PRODUCTS.jsonl')
)
REJECT LIMIT UNLIMITED;

-- ---------------------------------------------------------------------
-- Sanity checks to run right after creating these
-- ---------------------------------------------------------------------
-- SELECT COUNT(*) FROM ext_cosing_ingredient;
-- SELECT * FROM ext_obf_jsonl FETCH FIRST 3 ROWS ONLY;
--
-- If you get ORA-29913 / KUP-04040, the file is not where Oracle thinks
-- it is, or the OS permissions are wrong. Check the .log file in
-- INCI_DATA_BAD first -- it almost always says exactly what happened.
