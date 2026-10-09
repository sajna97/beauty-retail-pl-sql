CREATE OR REPLACE PACKAGE pkg_ingest AS
/* =====================================================================
   PKG_INGEST -- get files into staging. Nothing more.

   Rules this package follows, and you should keep following:
     1. It NEVER interprets business meaning. It lands raw rows.
     2. It NEVER hard-codes a file name. REF_FILE_TYPE drives dispatch.
     3. Every file is registered with a checksum before a row is read.
     4. Bad rows go to err_ tables via LOG ERRORS at promotion, never to
        DBMS_OUTPUT. A parser that meets a bad record fails the whole
        file instead: a short load that looks complete is worse.
   ===================================================================== */

  -- ---------------------------------------------------------------
  -- The entry point. Point it at a directory; it works out what each
  -- file is, skips anything already loaded, and calls the right parser.
  --
  -- Listing files: PL/SQL has no call for it. EXT_INBOUND_LISTING runs
  -- list_dir.sh as a PREPROCESSOR and returns one file name per row;
  -- EXTERNAL MODIFY points it at p_directory's .inci_listing marker.
  -- A directory without the marker cannot be listed.
  --
  -- Per file, in listing order:
  --   no ACTIVE file type matches    skipped, named in the batch message
  --                                  (a stray file or a parked feed is
  --                                  not a failure)
  --   register_file returns NULL     duplicate: a WARNING run with the
  --                                  E_DUPLICATE_FILE text, no file_id
  --   otherwise                      child run with file_id; registry
  --                                  LOADING (committed), parser called
  --                                  dynamically, registry LOADED with
  --                                  the parser's counts, COMMIT
  --
  -- Each file is its own transaction. If its parser fails: ROLLBACK
  -- (removing any partial staging rows), log_error, registry FAILED
  -- with the message, run FAILED -- then carry on with the next file.
  -- One bad file must not hold up the others.
  --
  -- After the last file: if any file failed, the batch run ends FAILED
  -- and E_PARSER_FAILED is raised, so the caller (and the scheduler)
  -- still sees the failure. Otherwise SUCCESS, or WARNING if anything
  -- was skipped or duplicate.
  --
  -- PARSER_PROC is stored data, not user input, but is still checked
  -- against USER_PROCEDURES before it is concatenated into the call.
  -- ---------------------------------------------------------------
  PROCEDURE process_directory (p_directory  IN VARCHAR2 DEFAULT 'INCI_DATA_IN',
                               p_parent_run IN NUMBER   DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- Register one file and decide whether it should be loaded.
  -- Matches the name to exactly one ACTIVE REF_FILE_TYPE pattern
  -- (none: E_UNKNOWN_FILE_TYPE; several: E_AMBIGUOUS_FILE_TYPE).
  -- Checksums the file, then looks the checksum up in FILE_REGISTRY:
  --
  --   not found        INSERT a REGISTERED row        -> return file_id
  --   FAILED,          RETRY: reuse the same row,      -> return file_id
  --   LOADING or       attempt_count + 1, status back
  --   REGISTERED       to REGISTERED, row counts and
  --                    error_message reset, and DELETE
  --                    this file_id's rows from its
  --                    staging table so the retry does
  --                    not double-load
  --   LOADED           duplicate -- already done, not  -> return NULL
  --                    an error
  --
  -- LOADING and REGISTERED are retried because, found at registration
  -- time, both mean a session died without recording an outcome --
  -- REGISTERED before the load started, LOADING part-way through. The
  -- same case as FAILED, minus the error message. Clearing the staging
  -- rows is harmless for REGISTERED (there are none) and keeps one code
  -- path for all three.
  --
  -- ASSUMPTION: only one loader runs at a time (a single DBMS_SCHEDULER
  -- job). A second concurrent loader would see the first one's genuine
  -- REGISTERED or LOADING row, retry it, and load the file twice. If
  -- loaders ever run in parallel, lock the registry row (SELECT ... FOR
  -- UPDATE NOWAIT) for the whole load before relying on this rule.
  --
  -- The retry DELETE targets REF_FILE_TYPE.TARGET_TABLE, which must
  -- have a FILE_ID column; anything else is refused (E_INVALID_PARAM)
  -- rather than guessed at.
  --
  -- Duplicates have no status of their own: the existing row is LOADED
  -- and the unique checksum forbids a second row. The caller records
  -- the skip on a run of its own -- status WARNING, message from
  -- E_DUPLICATE_FILE naming the file -- so a re-sent file still leaves
  -- a trace. That run has no file_id: NULL is all this returns.
  --
  -- COMMITS before returning. pkg_util.start_run is autonomous and
  -- checks its FK to file_registry from a separate transaction; an
  -- uncommitted registry row would deadlock it (see pkg_util spec).
  -- ---------------------------------------------------------------
  FUNCTION register_file (p_directory IN VARCHAR2,
                          p_file_name IN VARCHAR2) RETURN NUMBER;

  -- ---------------------------------------------------------------
  -- Parsers. One per feed. Each takes a FILE_ID and lands rows in its
  -- staging table.
  --
  -- Contract with process_directory, which calls them and owns the run:
  --   - write ROWS_READ / ROWS_LOADED / ROWS_REJECTED to FILE_REGISTRY
  --     for p_file_id
  --   - never COMMIT: the caller commits on success and rolls back on
  --     failure, which is what keeps a failed file out of staging
  --   - no run of their own: there is no parent-run parameter, and a
  --     parentless run would break the run tree
  --
  -- Parsers not built yet raise E_NOT_IMPLEMENTED; their feeds are
  -- inactive in REF_FILE_TYPE, so process_directory never calls them.
  -- ---------------------------------------------------------------

  -- JSONL: read the file line by line with UTL_FILE and insert each
  -- line as a CLOB into STG_OBF_PRODUCT. The IS JSON constraint rejects
  -- malformed lines; catch that and count them as rejected.
  --
  -- For anything above ~50k lines, switch to an external table with
  -- RECORDS DELIMITED BY NEWLINE and one CLOB column -- far faster.
  PROCEDURE load_obf_products (p_file_id IN NUMBER);

  -- CSV via external table, one set-based statement:
  --   INSERT INTO stg_cosing_ingredient
  --   SELECT ... FROM ext_cosing_ingredient
  --          EXTERNAL MODIFY (LOCATION ('<registered file name>')
  --                           REJECT LIMIT 0)
  -- EXTERNAL MODIFY reads the dispatched file for this one query; ALTER
  -- TABLE would be DDL (an implicit commit) and affect every session.
  -- REJECT LIMIT 0 because data/cosing_ingredients.py writes and checks
  -- this file: a reject is a bug, so the file fails, details in the
  -- .bad/.log files in INCI_DATA_BAD. No APPEND hint: at ~34k rows it
  -- buys nothing, and it locks the table.
  PROCEDURE load_cosing_ingredients (p_file_id IN NUMBER);

  -- CSV (data/download.sh, one file per annex). Not implemented yet;
  -- needs its own design -- two title rows above the header, a column
  -- set per annex, and a staging table, since INGREDIENT_RESTRICTIONS
  -- has no FILE_ID for a retry to clear.
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
