-- =====================================================================
-- 03_types/01_types.sql
-- SQL object types, so pipelined functions can be queried from SQL.
--
-- Why SQL types and not just PL/SQL records? Because
--   SELECT * FROM TABLE(pkg_ingredient.parse_inci('Aqua, Glycerin'))
-- only works if the type is visible to the SQL engine.
-- =====================================================================

-- One parsed token out of an INCI string --------------------------------
CREATE OR REPLACE TYPE t_inci_token AS OBJECT (
  position_no       NUMBER,
  raw_token         VARCHAR2(500),
  normalised_token  VARCHAR2(500),
  concentration_pct NUMBER,
  is_conditional    CHAR(1)         -- 'Y' after "May contain:" / "+/-"
);
/

CREATE OR REPLACE TYPE t_inci_token_tab AS TABLE OF t_inci_token;
/

-- A token after it has been matched to CosIng ---------------------------
CREATE OR REPLACE TYPE t_matched_token AS OBJECT (
  position_no       NUMBER,
  raw_token         VARCHAR2(500),
  normalised_token  VARCHAR2(500),
  ingredient_id     NUMBER,
  inci_name         VARCHAR2(500),
  match_method      VARCHAR2(20),
  match_score       NUMBER,
  is_allergen       CHAR(1),
  is_conditional    CHAR(1)
);
/

CREATE OR REPLACE TYPE t_matched_token_tab AS TABLE OF t_matched_token;
/

-- A single compliance finding -------------------------------------------
CREATE OR REPLACE TYPE t_compliance_finding AS OBJECT (
  product_id      NUMBER,
  market_id       NUMBER,
  market_code     VARCHAR2(10),
  verdict         VARCHAR2(20),
  severity        VARCHAR2(10),
  ingredient_id   NUMBER,
  inci_name       VARCHAR2(500),
  restriction_id  NUMBER,
  reason_code     VARCHAR2(50),
  reason_text     VARCHAR2(2000)
);
/

CREATE OR REPLACE TYPE t_compliance_finding_tab AS TABLE OF t_compliance_finding;
/
