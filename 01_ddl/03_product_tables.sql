-- =====================================================================
-- 01_ddl/03_product_tables.sql
-- Products, their parsed ingredient lists, and compliance verdicts.
--
-- Design note: PRODUCTS and PRODUCT_VARIANTS are separate even though
-- this project has one variant per product. In the larger platform a
-- product has many shades/sizes, each with its own barcode and stock.
-- Splitting later is a schema migration; splitting now is free.
-- =====================================================================

CREATE TABLE products (
  product_id       NUMBER GENERATED ALWAYS AS IDENTITY,
  barcode          VARCHAR2(20),
  product_name     VARCHAR2(500) NOT NULL,
  brand_id         NUMBER,
  category_id      NUMBER,
  product_type_id  NUMBER,
  inci_raw         CLOB,                       -- the original messy string
  inci_source      VARCHAR2(30),               -- OBF, SEPHORA, SUPPLIER, MANUAL
  parse_status     VARCHAR2(20) DEFAULT 'PENDING' NOT NULL,
  parsed_at        TIMESTAMP,
  token_count      NUMBER,
  unmatched_count  NUMBER,
  source_code      VARCHAR2(30)  NOT NULL,
  source_ref       VARCHAR2(100),              -- the id in the source system
  file_id          NUMBER,
  first_seen_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  last_updated_at  TIMESTAMP,
  status           VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
  CONSTRAINT products_pk  PRIMARY KEY (product_id),
  -- Barcode is UNIQUE but NOT the primary key -- deliberately. Some source
  -- records have no barcode at all (a unique constraint allows many NULLs),
  -- and later a product has many variants each with their own.
  CONSTRAINT products_uk  UNIQUE (barcode),
  CONSTRAINT products_fk1 FOREIGN KEY (brand_id)        REFERENCES brands (brand_id),
  CONSTRAINT products_fk2 FOREIGN KEY (category_id)     REFERENCES categories (category_id),
  CONSTRAINT products_fk3 FOREIGN KEY (product_type_id) REFERENCES product_types (product_type_id),
  CONSTRAINT products_fk4 FOREIGN KEY (file_id)         REFERENCES file_registry (file_id),
  CONSTRAINT products_ck1 CHECK (parse_status IN ('PENDING','PARSED','PARTIAL','FAILED','NO_INCI')),
  CONSTRAINT products_ck2 CHECK (status IN ('ACTIVE','DISCONTINUED','BLOCKED'))
);

CREATE INDEX products_ix1 ON products (brand_id);
CREATE INDEX products_ix2 ON products (parse_status);

CREATE TABLE product_variants (
  variant_id    NUMBER GENERATED ALWAYS AS IDENTITY,
  product_id    NUMBER        NOT NULL,
  variant_code  VARCHAR2(50)  NOT NULL,
  shade_name    VARCHAR2(200),
  shade_code    VARCHAR2(50),
  undertone     VARCHAR2(20),        -- COOL, WARM, NEUTRAL, OLIVE
  size_value    NUMBER(10,3),
  size_uom      VARCHAR2(10),        -- ML, G, OZ
  barcode       VARCHAR2(20),
  active_flag   CHAR(1) DEFAULT 'Y' NOT NULL,
  CONSTRAINT product_variants_pk  PRIMARY KEY (variant_id),
  CONSTRAINT product_variants_uk  UNIQUE (product_id, variant_code),
  CONSTRAINT product_variants_fk1 FOREIGN KEY (product_id) REFERENCES products (product_id),
  CONSTRAINT product_variants_ck1 CHECK (active_flag IN ('Y','N')),
  CONSTRAINT product_variants_ck2 CHECK (undertone IN ('COOL','WARM','NEUTRAL','OLIVE'))
);

-- ---------------------------------------------------------------------
-- PRODUCT_INGREDIENTS
-- One row per token parsed out of the INCI string, IN ORDER.
-- Order matters: INCI lists are descending by concentration, and
-- anything after "Parfum" is usually a declared allergen.
--
-- INGREDIENT_ID is nullable on purpose: an unmatched token is still a
-- fact worth keeping, and it feeds the review queue.
--
-- IS_CONDITIONAL = 'Y' for tokens after "May contain:" / "+/-". They are
-- shade-dependent colourants, not certainly present, so the compliance
-- engine must be able to tell them apart from the main list.
-- ---------------------------------------------------------------------
CREATE TABLE product_ingredients (
  product_ingredient_id NUMBER GENERATED ALWAYS AS IDENTITY,
  product_id            NUMBER        NOT NULL,
  position_no           NUMBER(4)     NOT NULL,
  raw_token             VARCHAR2(500) NOT NULL,
  normalised_token      VARCHAR2(500),
  ingredient_id         NUMBER,
  match_method          VARCHAR2(20),   -- EXACT, NORMALISED, FUZZY, SYNONYM, NONE
  match_score           NUMBER(5,2),
  concentration_pct     NUMBER(7,4),    -- when the source states one
  is_allergen           CHAR(1) DEFAULT 'N' NOT NULL,
  is_conditional        CHAR(1) DEFAULT 'N' NOT NULL,
  created_at            TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT product_ingredients_pk  PRIMARY KEY (product_ingredient_id),
  CONSTRAINT product_ingredients_uk  UNIQUE (product_id, position_no),
  CONSTRAINT product_ingredients_fk1 FOREIGN KEY (product_id)    REFERENCES products (product_id),
  CONSTRAINT product_ingredients_fk2 FOREIGN KEY (ingredient_id) REFERENCES ingredients (ingredient_id),
  CONSTRAINT product_ingredients_ck1 CHECK (match_method IN ('EXACT','NORMALISED','FUZZY','SYNONYM','NONE')),
  CONSTRAINT product_ingredients_ck2 CHECK (is_allergen IN ('Y','N')),
  CONSTRAINT product_ingredients_ck3 CHECK (is_conditional IN ('Y','N'))
);

CREATE INDEX product_ingredients_ix1 ON product_ingredients (ingredient_id);
CREATE INDEX product_ingredients_ix2 ON product_ingredients (product_id, is_allergen);

-- ---------------------------------------------------------------------
-- COMPLIANCE_RESULTS
-- One row per product x market x finding. A compliant product gets a
-- single COMPLIANT row; a non-compliant one gets a row per violation,
-- so the label sheet can list every reason.
-- ---------------------------------------------------------------------
CREATE TABLE compliance_results (
  result_id       NUMBER GENERATED ALWAYS AS IDENTITY,
  run_id          NUMBER        NOT NULL,
  product_id      NUMBER        NOT NULL,
  market_id       NUMBER        NOT NULL,
  verdict         VARCHAR2(20)  NOT NULL,
  severity        VARCHAR2(10)  NOT NULL,
  ingredient_id   NUMBER,
  restriction_id  NUMBER,
  reason_code     VARCHAR2(50),
  reason_text     VARCHAR2(2000),
  evaluated_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT compliance_results_pk  PRIMARY KEY (result_id),
  CONSTRAINT compliance_results_fk1 FOREIGN KEY (run_id)         REFERENCES job_run_log (run_id),
  CONSTRAINT compliance_results_fk2 FOREIGN KEY (product_id)     REFERENCES products (product_id),
  CONSTRAINT compliance_results_fk3 FOREIGN KEY (market_id)      REFERENCES markets (market_id),
  CONSTRAINT compliance_results_fk4 FOREIGN KEY (ingredient_id)  REFERENCES ingredients (ingredient_id),
  CONSTRAINT compliance_results_fk5 FOREIGN KEY (restriction_id) REFERENCES ingredient_restrictions (restriction_id),
  CONSTRAINT compliance_results_ck1 CHECK (verdict IN
        ('COMPLIANT','BLOCKED','LABEL_WARNING','REVIEW_REQUIRED','NOT_ASSESSED')),
  CONSTRAINT compliance_results_ck2 CHECK (severity IN ('INFO','WARN','ERROR'))
);

CREATE INDEX compliance_results_ix1 ON compliance_results (product_id, market_id);
CREATE INDEX compliance_results_ix2 ON compliance_results (run_id, verdict);

-- ---------------------------------------------------------------------
-- SUPPLIER_PRICE_LIST -- landing table for the .xlsx feed
-- ---------------------------------------------------------------------
CREATE TABLE supplier_price_list (
  price_list_id  NUMBER GENERATED ALWAYS AS IDENTITY,
  supplier_id    NUMBER        NOT NULL,
  file_id        NUMBER,
  barcode        VARCHAR2(20),
  product_name   VARCHAR2(500),
  brand_name     VARCHAR2(200),
  cost_price     NUMBER(12,4),
  currency_code  CHAR(3),
  launch_date    DATE,
  product_id     NUMBER,       -- resolved after matching
  loaded_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT supplier_price_list_pk  PRIMARY KEY (price_list_id),
  CONSTRAINT supplier_price_list_fk1 FOREIGN KEY (supplier_id) REFERENCES suppliers (supplier_id),
  CONSTRAINT supplier_price_list_fk2 FOREIGN KEY (file_id)     REFERENCES file_registry (file_id),
  CONSTRAINT supplier_price_list_fk3 FOREIGN KEY (product_id)  REFERENCES products (product_id)
);
