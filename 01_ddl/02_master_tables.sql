-- =====================================================================
-- 01_ddl/02_master_tables.sql
-- Reference and regulatory masters.
--
-- These tables move into the larger retail platform UNCHANGED. Treat
-- them as the permanent core of the schema.
--
-- Effective dating convention, used by every regulatory table here:
-- valid_from is INCLUSIVE, valid_to is EXCLUSIVE. A rule applies on day
-- d when valid_from <= d AND d < valid_to. Half-open ranges mean a rule
-- that ends on the day its replacement starts never overlaps it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- REGULATION_SCHEMES
-- A rule book. Several markets can share one (EU + Norway + Iceland all
-- follow EC 1223/2009), so restrictions and allergens hang off the
-- scheme, not the market. Adding Norway is one MARKETS row, zero rules.
-- ---------------------------------------------------------------------
CREATE TABLE regulation_schemes (
  regulation_scheme_id NUMBER GENERATED ALWAYS AS IDENTITY,
  scheme_code          VARCHAR2(30)  NOT NULL,   -- EU_1223_2009, UK_SI_2019, IN_BIS, US_FDA
  scheme_name          VARCHAR2(200) NOT NULL,
  legal_ref            VARCHAR2(200),
  active_flag          CHAR(1) DEFAULT 'Y' NOT NULL,
  CONSTRAINT regulation_schemes_pk  PRIMARY KEY (regulation_scheme_id),
  CONSTRAINT regulation_schemes_uk  UNIQUE (scheme_code),
  CONSTRAINT regulation_schemes_ck1 CHECK (active_flag IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- MARKETS
-- A market is a dimension, not a CHAR(2) column scattered everywhere.
-- It is where you SELL; the scheme is which rules apply there.
-- ---------------------------------------------------------------------
CREATE TABLE markets (
  market_id            NUMBER GENERATED ALWAYS AS IDENTITY,
  market_code          VARCHAR2(10)  NOT NULL,
  market_name          VARCHAR2(100) NOT NULL,
  iso_country_code     CHAR(2),
  region               VARCHAR2(50),
  regulation_scheme_id NUMBER        NOT NULL,
  currency_code        CHAR(3),
  active_flag          CHAR(1) DEFAULT 'Y' NOT NULL,
  CONSTRAINT markets_pk  PRIMARY KEY (market_id),
  CONSTRAINT markets_uk  UNIQUE (market_code),
  CONSTRAINT markets_fk1 FOREIGN KEY (regulation_scheme_id) REFERENCES regulation_schemes (regulation_scheme_id),
  CONSTRAINT markets_ck1 CHECK (active_flag IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- PRODUCT_TYPES
-- Matters more than it looks: EU Annex III limits differ for rinse-off
-- vs leave-on, and some substances are banned in products for children
-- under three. The compliance engine reads these flags.
-- ---------------------------------------------------------------------
CREATE TABLE product_types (
  product_type_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  product_type_code VARCHAR2(30)  NOT NULL,
  product_type_name VARCHAR2(100) NOT NULL,
  rinse_off_flag    CHAR(1) DEFAULT 'N' NOT NULL,
  oral_care_flag    CHAR(1) DEFAULT 'N' NOT NULL,
  eye_area_flag     CHAR(1) DEFAULT 'N' NOT NULL,
  children_flag     CHAR(1) DEFAULT 'N' NOT NULL,
  CONSTRAINT product_types_pk  PRIMARY KEY (product_type_id),
  CONSTRAINT product_types_uk  UNIQUE (product_type_code),
  CONSTRAINT product_types_ck1 CHECK (rinse_off_flag IN ('Y','N')),
  CONSTRAINT product_types_ck2 CHECK (oral_care_flag IN ('Y','N')),
  CONSTRAINT product_types_ck3 CHECK (eye_area_flag  IN ('Y','N')),
  CONSTRAINT product_types_ck4 CHECK (children_flag  IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- CATEGORIES -- self-referencing hierarchy (makeup > face > foundation)
-- ---------------------------------------------------------------------
CREATE TABLE categories (
  category_id        NUMBER GENERATED ALWAYS AS IDENTITY,
  category_code      VARCHAR2(50)  NOT NULL,
  category_name      VARCHAR2(150) NOT NULL,
  parent_category_id NUMBER,
  product_type_id    NUMBER,
  level_no           NUMBER(2),
  CONSTRAINT categories_pk  PRIMARY KEY (category_id),
  CONSTRAINT categories_uk  UNIQUE (category_code),
  CONSTRAINT categories_fk1 FOREIGN KEY (parent_category_id) REFERENCES categories (category_id),
  CONSTRAINT categories_fk2 FOREIGN KEY (product_type_id)    REFERENCES product_types (product_type_id)
);

-- ---------------------------------------------------------------------
-- BRANDS + BRAND_ALIASES
-- NORMALISED_NAME is a virtual column so the matcher never has to
-- remember to normalise -- the database guarantees it.
--
-- Normalisation = keep only A-Z a-z 0-9, then uppercase. It MUST give
-- the same result as pkg_util.normalise, or tokens stop joining.
--
-- Why nested TRANSLATE and not REGEXP_REPLACE(x,'[^A-Za-z0-9]',''):
-- on this database REGEXP_REPLACE is rejected in a virtual column
-- (ORA-54002, "only pure functions") -- its character ranges follow the
-- session collation, so its result is not fixed by its input alone.
-- COLLATE BINARY would pin that, but needs MAX_STRING_SIZE=EXTENDED
-- (ORA-43929). TRANSLATE does no collation-sensitive comparison at all.
--
-- How it works, reading inside out:
--   1. inner TRANSLATE(x, 'A' || <allowed chars>, 'A') deletes every
--      allowed character, leaving only the junk characters in x.
--      'A' is an anchor: it maps to itself, so the replacement string
--      is never empty (TRANSLATE with an empty 'to' returns NULL).
--   2. outer TRANSLATE(x, 'A' || <junk>, 'A') deletes that junk from x,
--      leaving only allowed characters. The anchor again maps to itself.
--   3. UPPER, then CAST to fix the declared width. Without the CAST
--      Oracle infers 4 bytes per source character (ORA-12899 against a
--      200 declaration). The CAST cannot truncate: what survives is
--      single-byte ASCII and no longer than the source column.
-- ---------------------------------------------------------------------
CREATE TABLE brands (
  brand_id          NUMBER GENERATED ALWAYS AS IDENTITY,
  brand_code        VARCHAR2(50)  NOT NULL,
  brand_name        VARCHAR2(200) NOT NULL,
  normalised_name   VARCHAR2(200 BYTE) GENERATED ALWAYS AS
                      (CAST(UPPER(TRANSLATE(brand_name,
                         'A' || TRANSLATE(brand_name, 'AABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'A'),
                         'A')) AS VARCHAR2(200 BYTE))) VIRTUAL,
  parent_company    VARCHAR2(200),
  country_of_origin CHAR(2),
  is_verified       CHAR(1) DEFAULT 'N' NOT NULL,
  created_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT brands_pk  PRIMARY KEY (brand_id),
  CONSTRAINT brands_uk  UNIQUE (brand_code),
  CONSTRAINT brands_ck1 CHECK (is_verified IN ('Y','N'))
);

CREATE INDEX brands_ix1 ON brands (normalised_name);

CREATE TABLE brand_aliases (
  alias_id         NUMBER GENERATED ALWAYS AS IDENTITY,
  brand_id         NUMBER        NOT NULL,
  alias_name       VARCHAR2(200) NOT NULL,
  -- same expression as BRANDS.normalised_name: see the header above
  normalised_alias VARCHAR2(200 BYTE) GENERATED ALWAYS AS
                     (CAST(UPPER(TRANSLATE(alias_name,
                        'A' || TRANSLATE(alias_name, 'AABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'A'),
                        'A')) AS VARCHAR2(200 BYTE))) VIRTUAL,
  source_code      VARCHAR2(30),
  match_method     VARCHAR2(20),   -- EXACT, NORMALISED, FUZZY, MANUAL
  match_score      NUMBER(5,2),
  created_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT brand_aliases_pk  PRIMARY KEY (alias_id),
  CONSTRAINT brand_aliases_fk1 FOREIGN KEY (brand_id) REFERENCES brands (brand_id),
  CONSTRAINT brand_aliases_ck1 CHECK (match_method IN ('EXACT','NORMALISED','FUZZY','MANUAL'))
);

CREATE INDEX brand_aliases_ix1 ON brand_aliases (normalised_alias);

-- ---------------------------------------------------------------------
-- INGREDIENTS  -- loaded from CosIng
-- NORMALISED_NAME is the join key for matching parsed INCI tokens.
-- The unique constraint on it is an assumption that CosIng never has two
-- names differing only in punctuation; verify against the real file
-- before trusting it (rejects land in ERR_INGREDIENTS, not on the floor).
-- ---------------------------------------------------------------------
CREATE TABLE ingredients (
  ingredient_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  inci_name         VARCHAR2(500) NOT NULL,
  -- same expression as BRANDS.normalised_name: see the BRANDS header
  normalised_name   VARCHAR2(500 BYTE) GENERATED ALWAYS AS
                      (CAST(UPPER(TRANSLATE(inci_name,
                         'A' || TRANSLATE(inci_name, 'AABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'A'),
                         'A')) AS VARCHAR2(500 BYTE))) VIRTUAL,
  cosing_ref_no     VARCHAR2(30),
  inn_name          VARCHAR2(500),
  ph_eur_name       VARCHAR2(500),
  cas_number        VARCHAR2(100),
  ec_number         VARCHAR2(100),
  chemical_desc     VARCHAR2(4000),
  restriction_flag  CHAR(1) DEFAULT 'N' NOT NULL,  -- denormalised for speed
  source_code       VARCHAR2(30) DEFAULT 'COSING' NOT NULL,
  created_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at        TIMESTAMP,
  CONSTRAINT ingredients_pk  PRIMARY KEY (ingredient_id),
  CONSTRAINT ingredients_uk  UNIQUE (normalised_name),
  CONSTRAINT ingredients_ck1 CHECK (restriction_flag IN ('Y','N'))
);

CREATE INDEX ingredients_ix1 ON ingredients (cas_number);

-- ---------------------------------------------------------------------
-- INGREDIENT_FUNCTIONS -- many-to-many (an ingredient can be both a
-- preservative and a fragrance)
-- ---------------------------------------------------------------------
CREATE TABLE ingredient_functions (
  function_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  function_code VARCHAR2(50)  NOT NULL,
  function_name VARCHAR2(200) NOT NULL,
  CONSTRAINT ingredient_functions_pk PRIMARY KEY (function_id),
  CONSTRAINT ingredient_functions_uk UNIQUE (function_code)
);

CREATE TABLE ingredient_function_map (
  ingredient_function_map_id NUMBER GENERATED ALWAYS AS IDENTITY,
  ingredient_id              NUMBER NOT NULL,
  function_id                NUMBER NOT NULL,
  CONSTRAINT ingredient_function_map_pk  PRIMARY KEY (ingredient_function_map_id),
  CONSTRAINT ingredient_function_map_uk  UNIQUE (ingredient_id, function_id),
  CONSTRAINT ingredient_function_map_fk1 FOREIGN KEY (ingredient_id) REFERENCES ingredients (ingredient_id),
  CONSTRAINT ingredient_function_map_fk2 FOREIGN KEY (function_id)   REFERENCES ingredient_functions (function_id)
);

-- ---------------------------------------------------------------------
-- INGREDIENT_RESTRICTIONS
-- The heart of the compliance engine.
--
--   PRODUCT_TYPE_ID NULL  = applies to all product types
--   MAX_CONCENTRATION NULL = an outright ban (restriction_type BANNED)
--
-- Keyed to the regulation scheme, not the market: one EU rule row
-- serves every market on EU_1223_2009.
--
-- Effective-dated from day one. Regulations change; retrofitting
-- valid_from/valid_to onto live data is genuinely miserable.
-- ---------------------------------------------------------------------
CREATE TABLE ingredient_restrictions (
  restriction_id       NUMBER GENERATED ALWAYS AS IDENTITY,
  ingredient_id        NUMBER        NOT NULL,
  regulation_scheme_id NUMBER        NOT NULL,
  restriction_type     VARCHAR2(20)  NOT NULL,
  annex_ref            VARCHAR2(30),        -- 'II/1234', 'III/98', 'V/12'
  product_type_id      NUMBER,              -- NULL = all types
  max_concentration    NUMBER(7,4),         -- percent
  condition_text       VARCHAR2(2000),
  label_warning_text   VARCHAR2(2000),
  valid_from           DATE DEFAULT DATE '2000-01-01' NOT NULL,
  valid_to             DATE DEFAULT DATE '9999-12-31' NOT NULL,
  source_code          VARCHAR2(30) DEFAULT 'COSING' NOT NULL,
  CONSTRAINT ingredient_restrictions_pk  PRIMARY KEY (restriction_id),
  CONSTRAINT ingredient_restrictions_fk1 FOREIGN KEY (ingredient_id)        REFERENCES ingredients (ingredient_id),
  CONSTRAINT ingredient_restrictions_fk2 FOREIGN KEY (regulation_scheme_id) REFERENCES regulation_schemes (regulation_scheme_id),
  CONSTRAINT ingredient_restrictions_fk3 FOREIGN KEY (product_type_id)      REFERENCES product_types (product_type_id),
  CONSTRAINT ingredient_restrictions_ck1 CHECK (restriction_type IN
        ('BANNED','RESTRICTED','PRESERVATIVE','COLOURANT','UV_FILTER','WARNING_ONLY')),
  CONSTRAINT ingredient_restrictions_ck2 CHECK (valid_to > valid_from),
  CONSTRAINT ingredient_restrictions_ck3 CHECK (max_concentration IS NULL OR max_concentration > 0)
);

CREATE INDEX ingredient_restrictions_ix1 ON ingredient_restrictions (ingredient_id, regulation_scheme_id);

COMMENT ON COLUMN ingredient_restrictions.valid_to IS 'Exclusive upper bound: applies while valid_from <= d < valid_to';

-- ---------------------------------------------------------------------
-- ALLERGENS -- declarable fragrance allergens, per regulation scheme
--
-- One row per allergen ENTRY in the rule book, not per ingredient.
-- Regulation (EU) 2023/1545 grew the EU list from 26 to ~80 entries,
-- and several entries (essential oils, extracts) cover more than one
-- INCI name -- so the ingredient link lives in ALLERGEN_INGREDIENTS.
--
-- valid_from has no default on purpose: the 2023/1545 entries start on
-- a specific transition date, and a silent 2000-01-01 would backdate
-- them. Thresholds have no default for the same reason -- they are
-- regulatory values and belong in the seed data, visibly.
-- ---------------------------------------------------------------------
CREATE TABLE allergens (
  allergen_id          NUMBER GENERATED ALWAYS AS IDENTITY,
  regulation_scheme_id NUMBER        NOT NULL,
  allergen_name        VARCHAR2(500) NOT NULL,
  annex_ref            VARCHAR2(30),            -- 'III/45'
  threshold_leave_on   NUMBER(7,5)   NOT NULL,  -- percent
  threshold_rinse_off  NUMBER(7,5)   NOT NULL,  -- percent
  regulation_ref       VARCHAR2(100),           -- 'Regulation (EU) 2023/1545'
  valid_from           DATE          NOT NULL,
  valid_to             DATE DEFAULT DATE '9999-12-31' NOT NULL,
  CONSTRAINT allergens_pk  PRIMARY KEY (allergen_id),
  CONSTRAINT allergens_uk  UNIQUE (regulation_scheme_id, allergen_name, valid_from),
  CONSTRAINT allergens_fk1 FOREIGN KEY (regulation_scheme_id) REFERENCES regulation_schemes (regulation_scheme_id),
  CONSTRAINT allergens_ck1 CHECK (valid_to > valid_from),
  CONSTRAINT allergens_ck2 CHECK (threshold_leave_on > 0 AND threshold_rinse_off > 0)
);

COMMENT ON COLUMN allergens.valid_to IS 'Exclusive upper bound: applies while valid_from <= d < valid_to';

CREATE TABLE allergen_ingredients (
  allergen_ingredient_id NUMBER GENERATED ALWAYS AS IDENTITY,
  allergen_id            NUMBER NOT NULL,
  ingredient_id          NUMBER NOT NULL,
  CONSTRAINT allergen_ingredients_pk  PRIMARY KEY (allergen_ingredient_id),
  CONSTRAINT allergen_ingredients_uk  UNIQUE (allergen_id, ingredient_id),
  CONSTRAINT allergen_ingredients_fk1 FOREIGN KEY (allergen_id)   REFERENCES allergens (allergen_id),
  CONSTRAINT allergen_ingredients_fk2 FOREIGN KEY (ingredient_id) REFERENCES ingredients (ingredient_id)
);

-- The matcher arrives with an ingredient_id and asks "is this an
-- allergen?" -- the unique key leads on allergen_id, so it cannot help.
CREATE INDEX allergen_ingredients_ix1 ON allergen_ingredients (ingredient_id);

-- ---------------------------------------------------------------------
-- SUPPLIERS -- for the .xlsx price-list feed
-- ---------------------------------------------------------------------
CREATE TABLE suppliers (
  supplier_id    NUMBER GENERATED ALWAYS AS IDENTITY,
  supplier_code  VARCHAR2(30)  NOT NULL,
  supplier_name  VARCHAR2(200) NOT NULL,
  currency_code  CHAR(3) DEFAULT 'EUR' NOT NULL,
  contact_email  VARCHAR2(200),
  active_flag    CHAR(1) DEFAULT 'Y' NOT NULL,
  CONSTRAINT suppliers_pk  PRIMARY KEY (supplier_id),
  CONSTRAINT suppliers_uk  UNIQUE (supplier_code),
  CONSTRAINT suppliers_ck1 CHECK (active_flag IN ('Y','N'))
);
