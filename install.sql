-- =====================================================================
-- install.sql  --  builds the whole schema from empty.
--
-- Run as the INCI user:
--   sqlplus inci/"Inci#2026"@localhost:1521/FREEPDB1
--   SQL> @install.sql
--
-- Prerequisite: 00_setup/01_create_user.sql has been run as SYS.
--
-- NOT idempotent: it expects an empty schema. Re-running over an
-- existing build fails on every CREATE TABLE. To rebuild, drop
-- everything first with @99_teardown.sql.
-- =====================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET ECHO OFF
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT ============================================================
PROMPT  INCI Inspector -- schema build
PROMPT ============================================================

PROMPT
PROMPT -- 1/6  Control and framework tables ------------------------
@@01_ddl/01_control_tables.sql

PROMPT
PROMPT -- 2/6  Master tables ---------------------------------------
@@01_ddl/02_master_tables.sql

PROMPT
PROMPT -- 3/6  Product tables --------------------------------------
@@01_ddl/03_product_tables.sql

PROMPT
PROMPT -- 4/6  Staging tables, GTT and error-log tables ------------
@@01_ddl/04_staging_and_gtt.sql

PROMPT
PROMPT -- 5/6  Object types ----------------------------------------
@@03_types/01_types.sql

PROMPT
PROMPT -- 6/6  Reference data --------------------------------------
@@02_seed/01_reference_data.sql

PROMPT
PROMPT ============================================================
PROMPT  Packages
PROMPT ============================================================
@@04_packages/pkg_util.pks
@@04_packages/pkg_util.pkb
@@04_packages/pkg_ingest.pks
@@04_packages/pkg_ingredient.pks
@@04_packages/pkg_compliance.pks

PROMPT
PROMPT ============================================================
PROMPT  External tables
PROMPT  (data files need not exist yet -- they are read at query time)
PROMPT ============================================================
@@06_external_tables/01_ext_cosing.sql
@@06_external_tables/02_ext_inbound_listing.sql

PROMPT
PROMPT ============================================================
PROMPT  Build summary
PROMPT ============================================================

COLUMN object_name FORMAT A32
COLUMN object_type FORMAT A20
COLUMN status      FORMAT A10

SELECT object_type, COUNT(*) AS object_count
  FROM user_objects
 GROUP BY object_type
 ORDER BY object_type;

PROMPT
PROMPT -- Anything listed below needs fixing before you continue:
SELECT object_name, object_type, status
  FROM user_objects
 WHERE status <> 'VALID'
 ORDER BY object_type, object_name;

PROMPT
PROMPT -- Compilation errors, if any:
SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, sequence;

PROMPT
PROMPT Done.
PROMPT
