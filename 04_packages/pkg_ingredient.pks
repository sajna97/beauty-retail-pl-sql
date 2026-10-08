CREATE OR REPLACE PACKAGE pkg_ingredient AS
/* =====================================================================
   PKG_INGREDIENT -- turn a free-text INCI string into identified,
   ordered ingredients. This is the hardest and most valuable code in
   the project, and it is the piece that transfers wholesale into the
   larger retail platform.

   DESIGN RULE, and it matters: parse_inci is PURE. It takes a string
   and returns a collection. It does not read tables, write tables, or
   know what a product is. Persistence lives in parse_product, a thin
   wrapper. Keep it that way and the parser stays testable, callable
   from SQL, and reusable anywhere.
   ===================================================================== */

  -- ---------------------------------------------------------------
  -- STAGE 1: split
  --
  -- Real INCI strings you will meet in Open Beauty Facts:
  --   "Aqua, Glycerin, Parfum (Linalool, Limonene), CI 77491"
  --   "AQUA/WATER/EAU, GLYCERIN, BUTYLENE GLYCOL"
  --   "Ingredients: Water (Aqua), Glycerin. May contain: CI 77491."
  --   "Aqua • Glycerin • Parfum"
  --   "水, 甘油"                       <- give up gracefully
  --
  -- Handle, in this order:
  --   1. strip a leading "Ingredients:" / "INCI:" label
  --   2. split off a trailing "May contain:" / "+/-" section and mark
  --      those tokens as conditional (position continues, flag set)
  --   3. clean_text to kill unicode noise
  --   4. split_top_level on ',' -- then, if that yields one token,
  --      retry on ';' then on the bullet character
  --   5. per token: strip a trailing '.', pull out a concentration if
  --      one is stated ("Niacinamide 5%"), collapse "AQUA/WATER/EAU"
  --      to its first synonym
  --
  -- Pipelined so you can debug it straight from SQL:
  --   SELECT * FROM TABLE(pkg_ingredient.parse_inci('Aqua, Glycerin'));
  -- ---------------------------------------------------------------
  FUNCTION parse_inci (p_inci IN CLOB) RETURN t_inci_token_tab PIPELINED;

  -- ---------------------------------------------------------------
  -- STAGE 2: match each token to CosIng.
  --
  -- Try in order, stopping at the first hit:
  --   EXACT      normalised_token = ingredients.normalised_name
  --   SYNONYM    token found in an ingredient synonym table (add later)
  --   FUZZY      pkg_util.similarity >= p_fuzzy_threshold, best score
  --   NONE       no match; ingredient_id stays NULL
  --
  -- Anything matched FUZZY below p_review_threshold goes to
  -- MATCH_REVIEW_QUEUE. Do not silently accept a 78% match.
  --
  -- Performance note: match token-by-token while you are learning, then
  -- rewrite as a single set-based MERGE over the GTT once it works. The
  -- README should show both, with timings. That comparison is the part
  -- an interviewer will ask about.
  -- ---------------------------------------------------------------
  FUNCTION match_tokens (p_tokens           IN t_inci_token_tab,
                         p_fuzzy_threshold  IN NUMBER DEFAULT 88,
                         p_review_threshold IN NUMBER DEFAULT 95)
    RETURN t_matched_token_tab PIPELINED;

  -- ---------------------------------------------------------------
  -- STAGE 3: persist.
  --
  --   parse into GTT_INCI_TOKEN
  --   match in place (UPDATE the GTT, or MERGE from ingredients)
  --   DELETE existing product_ingredients for the product
  --   INSERT ... SELECT from the GTT   (LOG ERRORS INTO err_product_ingredients)
  --   UPDATE products SET parse_status, token_count, unmatched_count, parsed_at
  --
  -- Do the whole thing in one transaction. A half-parsed ingredient
  -- list is worse than none.
  -- ---------------------------------------------------------------
  PROCEDURE parse_product (p_product_id IN NUMBER, p_run_id IN NUMBER DEFAULT NULL);

  -- Bulk driver. Use BULK COLLECT ... LIMIT 500 over unparsed products
  -- and FORALL where you can; commit every N products so a failure
  -- halfway does not lose an hour of work.
  PROCEDURE parse_pending (p_limit  IN NUMBER DEFAULT NULL,
                           p_run_id IN NUMBER DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- Convenience: the demo query.
  --   SELECT * FROM TABLE(pkg_ingredient.inspect('Aqua, Glycerin, Parfum'));
  -- Parses and matches in one call without touching any table. This is
  -- what you show someone in the first thirty seconds.
  -- ---------------------------------------------------------------
  FUNCTION inspect (p_inci IN CLOB) RETURN t_matched_token_tab PIPELINED;

END pkg_ingredient;
/
