CREATE OR REPLACE PACKAGE pkg_ingest AS
/* =====================================================================
   PKG_INGEST -- get files into staging. Nothing more.

   Rules this package follows, and you should keep following:
     1. It NEVER interprets business meaning. It lands raw rows.
     2. It NEVER hard-codes a file name. REF_FILE_TYPE drives dispatch.
     3. Every file is registered with a checksum before a row is read.
     4. Bad rows go to err_ tables via LOG ERRORS, never to DBMS_OUTPUT.
   ===================================================================== */

  -- ---------------------------------------------------------------
  -- The entry point. Point it at a directory; it works out what each
  -- file is, skips anything already loaded, and calls the right parser.
  --
  -- Implementation sketch:
  --   for each file name (see note on listing files, below)
  --     match file name against ref_file_type.file_name_pattern
  --       (SQL LIKE works if you store patterns with % as here)
  --     l_file_id := register_file(...)    -- NULL means skip, see below
  --     open a run with pkg_util.start_run(..., p_file_id => l_file_id)
  --     EXECUTE IMMEDIATE 'BEGIN ' || parser_proc || '(:1); END;'
  --       USING l_file_id
  --       (parser_proc is a stored value, not user input -- validate it
  --        against user_procedures before concatenating)
  --     update file_registry with row counts and LOADED / FAILED
  -- ---------------------------------------------------------------
  PROCEDURE process_directory (p_directory  IN VARCHAR2 DEFAULT 'INCI_DATA_IN',
                               p_parent_run IN NUMBER   DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- Register one file and decide whether it should be loaded.
  -- Checksums the file, then looks the checksum up in FILE_REGISTRY:
  --
  --   not found        INSERT a REGISTERED row        -> return file_id
  --   FAILED           RETRY: reuse the same row,      -> return file_id
  --                    attempt_count + 1, status back
  --                    to REGISTERED, row counts and
  --                    error_message reset, and DELETE
  --                    this file_id's rows from its
  --                    staging table so the retry does
  --                    not double-load
  --   LOADED           already done, not an error      -> return NULL
  --   anything else    not handled yet -- see below    -> return NULL
  --
  -- COMMITS before returning. pkg_util.start_run is autonomous and
  -- checks its FK to file_registry from a separate transaction; an
  -- uncommitted registry row would deadlock it (see pkg_util spec).
  --
  -- OPEN QUESTIONS, decide before writing the body:
  --   - A row stuck in LOADING means a crashed session. Retry it like
  --     FAILED, retry only after a timeout, or leave it for a human?
  --   - SKIPPED_DUPLICATE cannot be recorded on the existing row (it is
  --     LOADED) and a second row breaks the unique checksum. Drop the
  --     status, or log duplicates somewhere else?
  -- ---------------------------------------------------------------
  FUNCTION register_file (p_directory IN VARCHAR2,
                          p_file_name IN VARCHAR2) RETURN NUMBER;

  -- ---------------------------------------------------------------
  -- Parsers. One per feed. Each takes a FILE_ID and lands rows in its
  -- staging table.
  -- ---------------------------------------------------------------

  -- JSONL: read the file line by line with UTL_FILE and insert each
  -- line as a CLOB into STG_OBF_PRODUCT. The IS JSON constraint rejects
  -- malformed lines; catch that and count them as rejected.
  --
  -- For anything above ~50k lines, switch to an external table with
  -- RECORDS DELIMITED BY NEWLINE and one CLOB column -- far faster.
  PROCEDURE load_obf_products (p_file_id IN NUMBER);

  -- CSV via external table: INSERT /*+ APPEND */ INTO stg_cosing_ingredient
  -- SELECT ... FROM ext_cosing_ingredient.
  PROCEDURE load_cosing_ingredients (p_file_id IN NUMBER);

  -- XML: read the file into an XMLTYPE, then XMLTABLE it straight into
  -- INGREDIENT_RESTRICTIONS. Resolve INGREDIENT_ID by normalised name;
  -- unresolved ones go to MATCH_REVIEW_QUEUE.
  PROCEDURE load_cosing_annexes (p_file_id IN NUMBER);

  -- XLSX via APEX_DATA_PARSER over a BFILE-loaded BLOB.
  -- If APEX is not installed, raise E_NO_APEX_PARSER and document the
  -- CSV fallback in the README rather than silently doing something else.
  PROCEDURE load_supplier_prices (p_file_id IN NUMBER);

  -- ---------------------------------------------------------------
  -- Promotion: staging -> core.
  -- This is where MERGE lives, and where LOG ERRORS earns its keep.
  -- ---------------------------------------------------------------
  PROCEDURE promote_obf_products (p_file_id IN NUMBER, p_run_id IN NUMBER);
  PROCEDURE promote_cosing_ingredients (p_file_id IN NUMBER, p_run_id IN NUMBER);

END pkg_ingest;
/
