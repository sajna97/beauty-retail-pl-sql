CREATE OR REPLACE PACKAGE BODY pkg_util AS

  -- Package state for the buffered file writer -------------------------
  g_out_file  utl_file.file_type;
  g_out_open  BOOLEAN := FALSE;

  -- =====================================================================
  -- Run logging
  --
  -- AUTONOMOUS for the same reason log_error is. When the caller rolls
  -- back, a non-autonomous run row would vanish with it -- while the
  -- exception_log row written for that very failure survives, pointing
  -- at a run_id that no longer exists. The failed run is exactly the
  -- one you need to see.
  -- =====================================================================
  FUNCTION start_run (p_job_name    IN VARCHAR2,
                      p_module_name IN VARCHAR2 DEFAULT NULL,
                      p_parent_run  IN NUMBER   DEFAULT NULL,
                      p_file_id     IN NUMBER   DEFAULT NULL) RETURN NUMBER
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_run_id NUMBER;
  BEGIN
    INSERT INTO job_run_log (parent_run_id, job_name, module_name, file_id, status)
    VALUES (p_parent_run, p_job_name, p_module_name, p_file_id, 'RUNNING')
    RETURNING run_id INTO l_run_id;

    -- An autonomous block must commit or roll back before it returns,
    -- otherwise ORA-06519.
    COMMIT;
    RETURN l_run_id;
  END start_run;


  PROCEDURE end_run (p_run_id    IN NUMBER,
                     p_status    IN VARCHAR2 DEFAULT 'SUCCESS',
                     p_rows      IN NUMBER   DEFAULT NULL,
                     p_rejected  IN NUMBER   DEFAULT NULL,
                     p_message   IN VARCHAR2 DEFAULT NULL)
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    -- NVL on message too, matching the row counts: closing a run without
    -- a message must not wipe one written earlier.
    UPDATE job_run_log
       SET ended_at       = systimestamp,
           status         = p_status,
           rows_processed = NVL(p_rows, rows_processed),
           rows_rejected  = NVL(p_rejected, rows_rejected),
           message        = NVL(SUBSTR(p_message, 1, 4000), message)
     WHERE run_id = p_run_id;

    COMMIT;
  END end_run;


  -- =====================================================================
  -- Error handling
  --
  -- PRAGMA AUTONOMOUS_TRANSACTION is the whole point: the caller is
  -- almost certainly about to ROLLBACK, and you still want the log row.
  -- =====================================================================
  PROCEDURE log_error (p_module  IN VARCHAR2,
                       p_context IN VARCHAR2 DEFAULT NULL,
                       p_run_id  IN NUMBER   DEFAULT NULL)
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    -- SQLCODE and SQLERRM are PL/SQL-only functions: inside the INSERT
    -- they raise ORA-00984. Capturing them in the declarations also
    -- freezes the caller's error before anything in here can replace it.
    l_code NUMBER         := SQLCODE;
    l_msg  VARCHAR2(4000) := SUBSTR(SQLERRM, 1, 4000);
  BEGIN
    INSERT INTO exception_log (run_id, module_name, error_code, error_message,
                               error_stack, call_stack, context_info)
    VALUES (p_run_id,
            p_module,
            l_code,
            l_msg,
            dbms_utility.format_error_backtrace,
            dbms_utility.format_call_stack,
            SUBSTR(p_context, 1, 4000));
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;   -- logging must never mask the original error
  END log_error;


  -- ---------------------------------------------------------------
  -- Literal replace of the FIRST occurrence only. REPLACE does every
  -- occurrence; REGEXP_REPLACE does one but reads backslashes in the
  -- replacement as backreferences, so an argument containing \1 was
  -- silently mangled. INSTR + SUBSTR has no special characters at all.
  -- ---------------------------------------------------------------
  FUNCTION replace_first (p_text IN VARCHAR2,
                          p_find IN VARCHAR2,
                          p_with IN VARCHAR2) RETURN VARCHAR2
  IS
    l_pos PLS_INTEGER := NVL(INSTR(p_text, p_find), 0);
  BEGIN
    IF l_pos = 0 THEN
      RETURN p_text;
    END IF;
    RETURN SUBSTR(p_text, 1, l_pos - 1) || p_with || SUBSTR(p_text, l_pos + LENGTH(p_find));
  END replace_first;


  PROCEDURE raise_error (p_error_name IN VARCHAR2,
                         p_arg1       IN VARCHAR2 DEFAULT NULL,
                         p_arg2       IN VARCHAR2 DEFAULT NULL)
  IS
    l_code NUMBER;
    -- Wider than message_text (500): substituted arguments can push it
    -- past 500, and an ORA-06502 here would hide the real error.
    l_msg  VARCHAR2(4000);
  BEGIN
    SELECT error_code, message_text
      INTO l_code, l_msg
      FROM error_codes
     WHERE error_name = p_error_name;

    -- Always substitute both, in order. Skipping a NULL arg1 shifted arg2
    -- into the first slot: 'Parser %s failed for file %s' came out as
    -- 'Parser <file> failed for file %s'.
    l_msg := replace_first(l_msg, '%s', NVL(p_arg1, '(null)'));
    l_msg := replace_first(l_msg, '%s', NVL(p_arg2, '(null)'));

    -- 2048 bytes is the most raise_application_error will carry.
    raise_application_error(l_code, SUBSTRB(l_msg, 1, 2048));
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- The one bare error code in the repo, and deliberately so: the
      -- registry lookup itself failed, so the registry cannot report it.
      raise_application_error(-20000, 'Unregistered error name: ' || p_error_name);
  END raise_error;


  -- =====================================================================
  -- String helpers
  -- =====================================================================
  -- ---------------------------------------------------------------
  -- Must be character-for-character the same expression as the virtual
  -- columns in 01_ddl/02_master_tables.sql (see the BRANDS header there
  -- for how the nested TRANSLATE works). The allowed-character literal
  -- is duplicated, not shared via a package constant, because a virtual
  -- column expression cannot reference a package.
  --
  -- Why not REGEXP_REPLACE here, where it would compile: its character
  -- ranges follow the session collation, the virtual columns' TRANSLATE
  -- does not. Under a linguistic NLS_SORT the two could disagree, and a
  -- token would silently stop matching its ingredient.
  -- ---------------------------------------------------------------
  FUNCTION normalise (p_text IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC
  IS
  BEGIN
    RETURN UPPER(TRANSLATE(p_text,
             'A' || TRANSLATE(p_text, 'AABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'A'),
             'A'));
  END normalise;


  FUNCTION clean_text (p_text IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC
  IS
    l_out VARCHAR2(32767) := p_text;
  BEGIN
    IF l_out IS NULL THEN
      RETURN NULL;
    END IF;

    -- Curly quotes and unusual dashes -> plain ASCII
    l_out := REPLACE(l_out, UNISTR('\2019'), '''');
    l_out := REPLACE(l_out, UNISTR('\2018'), '''');
    l_out := REPLACE(l_out, UNISTR('\201C'), '"');
    l_out := REPLACE(l_out, UNISTR('\201D'), '"');
    l_out := REPLACE(l_out, UNISTR('\2013'), '-');
    l_out := REPLACE(l_out, UNISTR('\2014'), '-');

    -- Zero-width space, non-breaking space, BOM
    l_out := REPLACE(l_out, UNISTR('\200B'), '');
    l_out := REPLACE(l_out, UNISTR('\00A0'), ' ');
    l_out := REPLACE(l_out, UNISTR('\FEFF'), '');

    -- Tabs / newlines -> space, then collapse runs of whitespace
    l_out := REGEXP_REPLACE(l_out, '[' || CHR(9) || CHR(10) || CHR(13) || ']', ' ');
    l_out := REGEXP_REPLACE(l_out, ' {2,}', ' ');

    RETURN TRIM(l_out);
  END clean_text;


  -- ---------------------------------------------------------------
  -- split_top_level
  --
  -- A plain REGEXP split on ',' destroys "Parfum (Linalool, Limonene)".
  -- So walk the string character by character, track bracket depth, and
  -- only split when depth = 0. Slightly old-fashioned; completely
  -- reliable, and easy to explain in an interview.
  -- ---------------------------------------------------------------
  FUNCTION split_top_level (p_text  IN VARCHAR2,
                            p_delim IN VARCHAR2 DEFAULT ',')
    RETURN sys.odcivarchar2list
  IS
    l_result sys.odcivarchar2list := sys.odcivarchar2list();
    l_buffer VARCHAR2(4000);
    l_depth  PLS_INTEGER := 0;
    l_ch     VARCHAR2(1);
  BEGIN
    IF p_text IS NULL THEN
      RETURN l_result;
    END IF;

    FOR i IN 1 .. LENGTH(p_text) LOOP
      l_ch := SUBSTR(p_text, i, 1);

      IF l_ch IN ('(', '[', '{') THEN
        l_depth  := l_depth + 1;
        l_buffer := l_buffer || l_ch;

      ELSIF l_ch IN (')', ']', '}') THEN
        l_depth  := GREATEST(l_depth - 1, 0);
        l_buffer := l_buffer || l_ch;

      ELSIF l_ch = p_delim AND l_depth = 0 THEN
        l_result.EXTEND;
        l_result(l_result.COUNT) := TRIM(l_buffer);
        l_buffer := NULL;

      ELSE
        l_buffer := l_buffer || l_ch;
      END IF;
    END LOOP;

    IF TRIM(l_buffer) IS NOT NULL THEN
      l_result.EXTEND;
      l_result(l_result.COUNT) := TRIM(l_buffer);
    END IF;

    RETURN l_result;
  END split_top_level;


  FUNCTION similarity (p_a IN VARCHAR2, p_b IN VARCHAR2) RETURN NUMBER DETERMINISTIC
  IS
  BEGIN
    IF p_a IS NULL OR p_b IS NULL THEN
      RETURN 0;
    END IF;
    RETURN utl_match.jaro_winkler_similarity(p_a, p_b);
  END similarity;


  -- =====================================================================
  -- File helpers
  -- =====================================================================
  FUNCTION file_exists (p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN BOOLEAN
  IS
    l_exists     BOOLEAN;
    l_length     NUMBER;
    l_block_size NUMBER;
  BEGIN
    utl_file.fgetattr(p_directory, p_file_name, l_exists, l_length, l_block_size);
    RETURN l_exists;
  END file_exists;


  FUNCTION file_size (p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN NUMBER
  IS
    l_exists     BOOLEAN;
    l_length     NUMBER;
    l_block_size NUMBER;
  BEGIN
    utl_file.fgetattr(p_directory, p_file_name, l_exists, l_length, l_block_size);
    RETURN l_length;
  END file_size;


  -- ---------------------------------------------------------------
  -- SHA-256 of the file content. This is what makes a duplicate load
  -- impossible rather than merely unlikely.
  --
  -- Why copy the file into a temporary BLOB at all: DBMS_CRYPTO.HASH
  -- accepts RAW, BLOB or CLOB, never a BFILE, and has no incremental
  -- (chunk-by-chunk) API. A large temporary LOB spills to the TEMP
  -- tablespace rather than sitting in session memory, so the real cost
  -- is reading the file twice, not memory.
  -- ---------------------------------------------------------------
  FUNCTION file_checksum (p_directory IN VARCHAR2, p_file_name IN VARCHAR2) RETURN VARCHAR2
  IS
    l_bfile     BFILE;
    l_blob      BLOB;
    l_hash      RAW(32);
    -- Track state ourselves: calling fileisopen on a file that was never
    -- opened can itself raise, and that would mask E_FILE_NOT_FOUND.
    l_file_open BOOLEAN := FALSE;
    l_blob_temp BOOLEAN := FALSE;
  BEGIN
    l_bfile := bfilename(p_directory, p_file_name);

    IF dbms_lob.fileexists(l_bfile) <> 1 THEN
      raise_error('E_FILE_NOT_FOUND', p_file_name);
    END IF;

    dbms_lob.createtemporary(l_blob, TRUE);
    l_blob_temp := TRUE;

    dbms_lob.fileopen(l_bfile, dbms_lob.file_readonly);
    l_file_open := TRUE;

    dbms_lob.loadfromfile(l_blob, l_bfile, dbms_lob.getlength(l_bfile));
    dbms_lob.fileclose(l_bfile);
    l_file_open := FALSE;

    l_hash := dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256);

    dbms_lob.freetemporary(l_blob);
    RETURN LOWER(RAWTOHEX(l_hash));
  EXCEPTION
    WHEN OTHERS THEN
      -- Release both resources, or a failed checksum leaks a file handle
      -- and a TEMP segment until the session ends.
      IF l_file_open THEN
        dbms_lob.fileclose(l_bfile);
      END IF;
      IF l_blob_temp THEN
        dbms_lob.freetemporary(l_blob);
      END IF;
      RAISE;
  END file_checksum;


  PROCEDURE open_out (p_directory IN VARCHAR2, p_file_name IN VARCHAR2)
  IS
  BEGIN
    IF g_out_open THEN
      close_out;
    END IF;
    g_out_file := utl_file.fopen(p_directory, p_file_name, 'W', 32767);
    g_out_open := TRUE;
  END open_out;


  PROCEDURE write_line (p_line IN VARCHAR2)
  IS
  BEGIN
    IF NOT g_out_open THEN
      raise_error('E_INVALID_PARAM', 'no output file is open');
    END IF;
    utl_file.put_line(g_out_file, p_line);
  END write_line;


  PROCEDURE close_out
  IS
  BEGIN
    IF g_out_open THEN
      utl_file.fclose(g_out_file);
      g_out_open := FALSE;
    END IF;
  END close_out;

END pkg_util;
/
