CREATE OR REPLACE PACKAGE pkg_util AS
/* =====================================================================
   PKG_UTIL -- shared plumbing. Everything else calls into this.

   Build this FIRST and never let another package duplicate what lives
   here. In the larger retail platform this package is lifted across
   unchanged, which is only true if it stays free of domain logic.
   ===================================================================== */

  -- ---------------------------------------------------------------
  -- Run logging
  -- Every package entry point opens a run and closes it. Nest child
  -- runs under a parent so a nightly chain reads as a tree.
  --
  -- Both run as AUTONOMOUS TRANSACTIONS and commit their own row, so a
  -- run survives the rollback of the work it describes.
  --
  -- Two consequences callers must respect:
  --   1. p_file_id must already be COMMITTED. The autonomous insert
  --      checks the FK against file_registry from a separate
  --      transaction; if the caller's file_registry row is still
  --      uncommitted, the autonomous transaction waits on the caller's
  --      lock while the caller waits for it to return -- ORA-00060
  --      deadlock, in a single session.
  --   2. Never UPDATE job_run_log directly in the caller's transaction.
  --      end_run would then wait on the caller's row lock: same deadlock.
  --
  -- end_run leaves any argument passed as NULL unchanged, message
  -- included.
  -- ---------------------------------------------------------------
  FUNCTION start_run (p_job_name    IN VARCHAR2,
                      p_module_name IN VARCHAR2 DEFAULT NULL,
                      p_parent_run  IN NUMBER   DEFAULT NULL,
                      p_file_id     IN NUMBER   DEFAULT NULL) RETURN NUMBER;

  PROCEDURE end_run (p_run_id    IN NUMBER,
                     p_status    IN VARCHAR2 DEFAULT 'SUCCESS',
                     p_rows      IN NUMBER   DEFAULT NULL,
                     p_rejected  IN NUMBER   DEFAULT NULL,
                     p_message   IN VARCHAR2 DEFAULT NULL);

  -- ---------------------------------------------------------------
  -- Error handling
  -- log_error runs as an AUTONOMOUS TRANSACTION, so the log entry
  -- survives the rollback of whatever failed. Call it from the
  -- WHEN OTHERS handler, then re-raise.
  -- ---------------------------------------------------------------
  PROCEDURE log_error (p_module  IN VARCHAR2,
                       p_context IN VARCHAR2 DEFAULT NULL,
                       p_run_id  IN NUMBER   DEFAULT NULL);

  -- Raise a registered error by name, substituting %s placeholders
  -- left to right, literally (no regex). A NULL argument is written as
  -- '(null)' so later arguments never shift into the wrong slot. An
  -- unregistered name raises -20000.
  PROCEDURE raise_error (p_error_name IN VARCHAR2,
                         p_arg1       IN VARCHAR2 DEFAULT NULL,
                         p_arg2       IN VARCHAR2 DEFAULT NULL);

  -- The message raise_error would carry, returned instead of raised.
  -- For outcomes that are recorded but are not exceptions -- e.g. a
  -- duplicate file, logged as a WARNING run. Same substitution rules;
  -- an unregistered name still raises -20000.
  FUNCTION error_text (p_error_name IN VARCHAR2,
                       p_arg1       IN VARCHAR2 DEFAULT NULL,
                       p_arg2       IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

  -- ---------------------------------------------------------------
  -- String helpers -- the workhorses of the INCI parser
  -- ---------------------------------------------------------------

  -- Uppercase, strip everything that is not A-Z or 0-9. Matches the
  -- virtual columns on BRANDS and INGREDIENTS, so a token normalised
  -- here joins straight to INGREDIENTS.NORMALISED_NAME.
  FUNCTION normalise (p_text IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC;

  -- Collapse whitespace, strip zero-width and non-breaking characters,
  -- normalise curly quotes and dashes. Run this BEFORE splitting.
  FUNCTION clean_text (p_text IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC;

  -- Split on a delimiter, but ONLY at nesting depth zero, so
  -- "Parfum (Linalool, Limonene)" stays one token.
  FUNCTION split_top_level (p_text  IN VARCHAR2,
                            p_delim IN VARCHAR2 DEFAULT ',')
    RETURN sys.odcivarchar2list;

  -- Jaro-Winkler similarity 0..100, NULL-safe.
  FUNCTION similarity (p_a IN VARCHAR2, p_b IN VARCHAR2) RETURN NUMBER DETERMINISTIC;

  -- ---------------------------------------------------------------
  -- File helpers
  -- ---------------------------------------------------------------
  FUNCTION file_exists  (p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN BOOLEAN;
  FUNCTION file_size    (p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN NUMBER;
  FUNCTION file_checksum(p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN VARCHAR2;

  -- Simple buffered writer for the outbound files.
  PROCEDURE open_out  (p_directory IN VARCHAR2, p_file_name IN VARCHAR2);
  PROCEDURE write_line(p_line IN VARCHAR2);
  PROCEDURE close_out;

END pkg_util;
/
