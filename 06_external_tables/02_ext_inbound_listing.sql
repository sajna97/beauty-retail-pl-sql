-- =====================================================================
-- 06_external_tables/02_ext_inbound_listing.sql
--
-- A directory listing as a table. PL/SQL has no "list files" call, so
-- the PREPROCESSOR runs 00_setup/list_dir.sh and this table reads its
-- output -- one file name per row -- instead of reading a data file.
--
-- Prerequisites (see README, steps 3-4):
--   - INCI_EXEC directory with READ, EXECUTE (00_setup/02_exec_directory.sql)
--   - /opt/oracle/inci/exec/list_dir.sh, mode 755
--   - an empty marker file .inci_listing in each directory to be listed
--
-- The marker is the LOCATION: Oracle hands its path to the script, and
-- the script lists the directory the marker sits in. pkg_ingest points
-- the table at another directory with EXTERNAL MODIFY (LOCATION ...).
-- =====================================================================

CREATE TABLE ext_inbound_listing (
  file_name  VARCHAR2(400)
)
ORGANIZATION EXTERNAL (
  TYPE oracle_loader
  DEFAULT DIRECTORY inci_data_in
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET AL32UTF8
    PREPROCESSOR inci_exec : 'list_dir.sh'
    BADFILE  inci_data_bad : 'inbound_listing.bad'
    LOGFILE  inci_data_bad : 'inbound_listing.log'
    -- Positional, not delimited: a file name may contain commas or
    -- spaces, and the whole line is the name.
    FIELDS NOTRIM
    (
      file_name  POSITION(1:400) CHAR(400)
    )
  )
  LOCATION ('.inci_listing')
)
REJECT LIMIT UNLIMITED;

-- SELECT file_name FROM ext_inbound_listing;
--
-- KUP-04095 / ORA-29400 on the first query usually means the script is
-- not executable by the oracle OS user, or INCI lacks EXECUTE on
-- INCI_EXEC. The .log file in INCI_DATA_BAD names which.
