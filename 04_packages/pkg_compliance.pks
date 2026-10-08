CREATE OR REPLACE PACKAGE pkg_compliance AS
/* =====================================================================
   PKG_COMPLIANCE -- given a parsed product and a market, decide whether
   it can be sold, and say exactly why not.

   The rules are DATA, not code. Adding a market on an existing rule
   book is one MARKETS row; adding a new rule book is a
   REGULATION_SCHEMES row plus its INGREDIENT_RESTRICTIONS and ALLERGENS.
   If you ever find yourself writing IF market_code = 'EU' THEN, stop
   and put it in a table.

   A market is where you sell; its regulation scheme is which rules
   apply. Every rule lookup goes market -> regulation_scheme_id -> rules.
   ===================================================================== */

  -- ---------------------------------------------------------------
  -- Assess one product against one market, as the rules stood on
  -- p_as_of. Defaults to today; pass a past date to answer "was this
  -- compliant when we shipped it in March?".
  --
  -- Verdict precedence, highest wins:
  --   BLOCKED          any ingredient with restriction_type = 'BANNED'
  --                    in the market's scheme, effective on p_as_of
  --   BLOCKED          a RESTRICTED ingredient whose stated
  --                    concentration exceeds max_concentration
  --   REVIEW_REQUIRED  a RESTRICTED ingredient with NO stated
  --                    concentration -- you cannot prove compliance,
  --                    so do not claim it
  --   REVIEW_REQUIRED  more than half the tokens are unmatched
  --   LABEL_WARNING    a declarable allergen is present, or a
  --                    restriction carries label_warning_text
  --   COMPLIANT        none of the above
  --
  -- Restrictions are matched on:
  --   ingredient_id
  --   regulation_scheme_id  (taken from the market, never the market itself)
  --   product_type_id       (NULL in the restriction = applies to all types)
  --   valid_from <= p_as_of AND p_as_of < valid_to
  --
  -- Allergens are matched through ALLERGEN_INGREDIENTS on the same
  -- scheme and the same half-open date test. Use the threshold column
  -- that matches products.product_type_id -> product_types.rinse_off_flag.
  --
  -- Never BETWEEN on validity dates: valid_to is exclusive, and BETWEEN
  -- would fire a rule and its replacement together on the changeover day.
  --
  -- OPEN QUESTION, do not implement until answered: how do tokens with
  -- is_conditional = 'Y' ("May contain:") affect the verdict? A banned
  -- colourant in a "May contain" list may be in some shades and not
  -- others. That is a regulatory call, not a coding one.
  --
  -- Pipelined so it is queryable and testable without writing rows.
  -- ---------------------------------------------------------------
  FUNCTION assess (p_product_id IN NUMBER,
                   p_market_id  IN NUMBER,
                   p_as_of      IN DATE DEFAULT TRUNC(SYSDATE))
    RETURN t_compliance_finding_tab PIPELINED;

  -- Same, resolving the market by code -- convenience for demos.
  FUNCTION assess_by_code (p_product_id  IN NUMBER,
                           p_market_code IN VARCHAR2,
                           p_as_of       IN DATE DEFAULT TRUNC(SYSDATE))
    RETURN t_compliance_finding_tab PIPELINED;

  -- ---------------------------------------------------------------
  -- Persist assessments for a whole run.
  -- Deletes prior results for the products in scope, then inserts.
  -- Use FORALL over a collection of findings.
  --
  -- Always assesses as of today. Persisting a historical (p_as_of)
  -- assessment needs an as-of column on COMPLIANCE_RESULTS first, or a
  -- stored March verdict is indistinguishable from today's.
  -- ---------------------------------------------------------------
  PROCEDURE assess_all (p_market_code IN VARCHAR2 DEFAULT NULL,  -- NULL = every active market
                        p_run_id      IN NUMBER   DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- The DQ engine. Reads DQ_RULES, builds a predicate per rule, runs it
  -- with EXECUTE IMMEDIATE, writes violations to DQ_RESULTS.
  --
  -- Build the SQL as, roughly:
  --   SELECT <pk_column>, <target_column>
  --     FROM <target_table>
  --    WHERE NOT ( <predicate> )
  --
  -- with <predicate> derived from rule_type:
  --   NOT_NULL  ->  col IS NOT NULL
  --   PATTERN   ->  col IS NULL OR REGEXP_LIKE(col, :expr)
  --   RANGE     ->  col IS NULL OR col BETWEEN :lo AND :hi
  --   LOOKUP    ->  EXISTS (SELECT 1 FROM <t> WHERE <c> = col)
  --   SQL       ->  the expression verbatim
  --
  -- SECURITY: bind the values, never concatenate them. Table and column
  -- names cannot be bound, so validate them against USER_TAB_COLUMNS
  -- before concatenating -- that check is what makes this safe, and
  -- saying so out loud in an interview is worth real points.
  -- ---------------------------------------------------------------
  PROCEDURE run_dq_rules (p_target_table IN VARCHAR2 DEFAULT NULL,  -- NULL = all
                          p_run_id       IN NUMBER   DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- Outbound files, all via pkg_util.open_out / write_line / close_out
  -- ---------------------------------------------------------------

  -- CSV: product, market, verdict, offending ingredient, reason
  PROCEDURE write_compliance_report (p_run_id    IN NUMBER,
                                     p_directory IN VARCHAR2 DEFAULT 'INCI_DATA_OUT');

  -- Human-readable label sheet for one product in one market:
  -- the ordered ingredient list, allergen declarations, warnings.
  PROCEDURE write_label_sheet (p_product_id  IN NUMBER,
                               p_market_code IN VARCHAR2,
                               p_directory   IN VARCHAR2 DEFAULT 'INCI_DATA_OUT');

  -- JSON: every token that failed to match, with its best candidate.
  -- This is the file you would send to a data steward.
  PROCEDURE write_unmatched_json (p_run_id    IN NUMBER,
                                  p_directory IN VARCHAR2 DEFAULT 'INCI_DATA_OUT');

END pkg_compliance;
/
