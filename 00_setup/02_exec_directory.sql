-- =====================================================================
-- 00_setup/02_exec_directory.sql
-- Run as SYS in the PDB, after 01_create_user.sql:
--   sqlplus sys/oracle@localhost:1521/FREEPDB1 as sysdba
--   SQL> @00_setup/02_exec_directory.sql
--
-- PL/SQL cannot list the files in a directory. pkg_ingest works around
-- that with an external table whose PREPROCESSOR runs list_dir.sh and
-- reads its output as rows. A preprocessor script must live in a
-- directory the schema can EXECUTE.
--
-- Copy the script in first (see README, step 3):
--   /opt/oracle/inci/exec/list_dir.sh, mode 755
-- =====================================================================

CREATE OR REPLACE DIRECTORY inci_exec AS '/opt/oracle/inci/exec';

-- READ is needed for the preprocessor to open the script, EXECUTE to run
-- it. No WRITE: with it, INCI could replace the script with anything and
-- have the database run it as the oracle OS user.
GRANT READ, EXECUTE ON DIRECTORY inci_exec TO inci;
