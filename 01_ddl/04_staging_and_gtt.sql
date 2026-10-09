-- =====================================================================
-- 01_ddl/04_staging_and_gtt.sql
-- Staging tables, DBMS_ERRLOG shadow tables, and the global temporary
-- table used as the INCI parser's working set.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STG_OBF_PRODUCT
-- Open Beauty Facts arrives as JSONL -- one JSON object per line.
-- Land the raw payload first, parse second. Never parse during load:
-- if the parse logic changes you want to re-run it without re-reading
-- the file.
--
-- The IS JSON check constraint means a malformed line is rejected by
-- the database, not by your code.
-- ---------------------------------------------------------------------
CREATE TABLE stg_obf_product (
  stg_id      NUMBER GENERATED ALWAYS AS IDENTITY,
  file_id     NUMBER NOT NULL,
  line_no     NUMBER NOT NULL,
  payload     CLOB   NOT NULL,
  loaded_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT stg_obf_product_pk  PRIMARY KEY (stg_id),
  CONSTRAINT stg_obf_product_fk1 FOREIGN KEY (file_id) REFERENCES file_registry (file_id),
  CONSTRAINT stg_obf_product_ck1 CHECK (payload IS JSON)
);

CREATE INDEX stg_obf_product_ix1 ON stg_obf_product (file_id);

-- ---------------------------------------------------------------------
-- STG_COSING_INGREDIENT
-- Landing table matching the CosIng export layout. All VARCHAR2 --
-- staging tables never enforce types; that is what the DQ layer is for.
-- ---------------------------------------------------------------------
CREATE TABLE stg_cosing_ingredient (
  stg_id         NUMBER GENERATED ALWAYS AS IDENTITY,
  file_id        NUMBER,
  cosing_ref_no  VARCHAR2(100),
  inci_name      VARCHAR2(1000),
  inn_name       VARCHAR2(1000),
  ph_eur_name    VARCHAR2(1000),
  cas_no         VARCHAR2(500),
  ec_no          VARCHAR2(500),
  chem_desc      VARCHAR2(4000),
  restriction    VARCHAR2(4000),
  functions      VARCHAR2(2000),
  update_date    VARCHAR2(50),
  -- 'Active' or NULL in the source. NULL is kept, not defaulted: whether
  -- an ingredient with no status is current is for promotion to decide.
  status         VARCHAR2(50),
  loaded_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT stg_cosing_ingredient_pk  PRIMARY KEY (stg_id),
  CONSTRAINT stg_cosing_ingredient_fk1 FOREIGN KEY (file_id) REFERENCES file_registry (file_id)
);

-- ---------------------------------------------------------------------
-- STG_SUPPLIER_PRICE -- landing for the .xlsx feed
-- ---------------------------------------------------------------------
CREATE TABLE stg_supplier_price (
  stg_id        NUMBER GENERATED ALWAYS AS IDENTITY,
  file_id       NUMBER,
  row_no        NUMBER,
  col_barcode   VARCHAR2(100),
  col_product   VARCHAR2(1000),
  col_brand     VARCHAR2(500),
  col_cost      VARCHAR2(100),
  col_currency  VARCHAR2(20),
  col_launch    VARCHAR2(50),
  loaded_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT stg_supplier_price_pk  PRIMARY KEY (stg_id),
  CONSTRAINT stg_supplier_price_fk1 FOREIGN KEY (file_id) REFERENCES file_registry (file_id)
);

-- ---------------------------------------------------------------------
-- GTT_INCI_TOKEN
-- The parser's working set. ON COMMIT PRESERVE ROWS so you can parse,
-- inspect, then persist -- and so a caller can run several products in
-- one transaction.
--
-- This is the global temporary table pattern: heavy intermediate work
-- with no redo on the table itself and no cross-session interference.
-- ---------------------------------------------------------------------
CREATE GLOBAL TEMPORARY TABLE gtt_inci_token (
  product_id        NUMBER,
  position_no       NUMBER(4),
  raw_token         VARCHAR2(500),
  normalised_token  VARCHAR2(500),
  ingredient_id     NUMBER,
  match_method      VARCHAR2(20),
  match_score       NUMBER(5,2),
  concentration_pct NUMBER(7,4),
  is_allergen       CHAR(1),
  is_conditional    CHAR(1)
) ON COMMIT PRESERVE ROWS;

-- ---------------------------------------------------------------------
-- DBMS_ERRLOG shadow tables
-- Created by the supplied procedure so the column layout always matches
-- the base table. Run these AFTER the base tables exist.
--
-- With these in place you can write:
--   INSERT INTO products (...) SELECT ... FROM stg_obf_product
--   LOG ERRORS INTO err_products ('load OBF') REJECT LIMIT UNLIMITED;
-- and a bad row lands in err_products instead of killing the statement.
--
-- One block per table, on purpose: in a single block the first failure
-- aborts the rest, and every later err_ table silently never exists.
-- Separate blocks fail loudly and independently.
-- ---------------------------------------------------------------------

-- skip_unsupported: DBMS_ERRLOG cannot shadow a CLOB, so without it
-- this fails with ORA-20069 on INCI_RAW. ERR_PRODUCTS is built without
-- that column; a rejected row's raw INCI text is still in
-- STG_OBF_PRODUCT, traceable through file_id / source_ref.
BEGIN
  dbms_errlog.create_error_log(dml_table_name     => 'PRODUCTS',
                               err_log_table_name => 'ERR_PRODUCTS',
                               skip_unsupported   => TRUE);
END;
/

BEGIN
  dbms_errlog.create_error_log(dml_table_name     => 'INGREDIENTS',
                               err_log_table_name => 'ERR_INGREDIENTS');
END;
/

BEGIN
  dbms_errlog.create_error_log(dml_table_name     => 'PRODUCT_INGREDIENTS',
                               err_log_table_name => 'ERR_PRODUCT_INGREDIENTS');
END;
/

BEGIN
  dbms_errlog.create_error_log(dml_table_name     => 'INGREDIENT_RESTRICTIONS',
                               err_log_table_name => 'ERR_INGREDIENT_RESTRICTIONS');
END;
/

BEGIN
  dbms_errlog.create_error_log(dml_table_name     => 'SUPPLIER_PRICE_LIST',
                               err_log_table_name => 'ERR_SUPPLIER_PRICE_LIST');
END;
/
