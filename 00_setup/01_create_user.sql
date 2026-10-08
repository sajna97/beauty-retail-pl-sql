-- =====================================================================
-- 00_setup/01_create_user.sql
-- Run as SYS in the PDB -- not SYSTEM, which cannot grant EXECUTE on
-- SYS-owned packages (ORA-01031). E.g.:
--   sqlplus sys/oracle@localhost:1521/FREEPDB1 as sysdba
--   SQL> @00_setup/01_create_user.sql
--
-- Creates the application schema and grants only what the project needs.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------
CREATE USER inci IDENTIFIED BY "Inci#2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION            TO inci;
GRANT CREATE TABLE              TO inci;
GRANT CREATE VIEW               TO inci;
GRANT CREATE SEQUENCE           TO inci;
GRANT CREATE PROCEDURE          TO inci;
GRANT CREATE TRIGGER            TO inci;
GRANT CREATE TYPE               TO inci;
GRANT CREATE MATERIALIZED VIEW  TO inci;
GRANT CREATE JOB                TO inci;
-- No CREATE ANY DIRECTORY: SYS creates the directories below and grants
-- READ/WRITE on each, which is all external tables and UTL_FILE need.
-- The ANY privilege would let INCI point a directory at any OS path.

-- ---------------------------------------------------------------------
-- Packages the project calls directly
-- ---------------------------------------------------------------------
-- Comments go on their own line, never after the ';'. SQL*Plus does not
-- treat '; -- text' as a terminator, glues the next statement on, and
-- both fail with ORA-03405.
GRANT EXECUTE ON sys.dbms_lob       TO inci;
-- file checksums (SHA-256)
GRANT EXECUTE ON sys.dbms_crypto    TO inci;
GRANT EXECUTE ON sys.utl_file       TO inci;
-- fuzzy ingredient / brand matching
GRANT EXECUTE ON sys.utl_match      TO inci;
GRANT EXECUTE ON sys.dbms_scheduler TO inci;

-- Optional: only if you want to inspect plans and stats yourself
GRANT SELECT ON sys.v_$session TO inci;

-- ---------------------------------------------------------------------
-- Directories
-- Create the OS folders FIRST, and make sure the Oracle OS user can
-- read/write them. On a Docker XE container these live inside the
-- container, so use `docker exec -it <c> mkdir -p /opt/oracle/inci/in`.
-- ---------------------------------------------------------------------
CREATE OR REPLACE DIRECTORY inci_data_in  AS '/opt/oracle/inci/in';
CREATE OR REPLACE DIRECTORY inci_data_out AS '/opt/oracle/inci/out';
CREATE OR REPLACE DIRECTORY inci_data_bad AS '/opt/oracle/inci/bad';
CREATE OR REPLACE DIRECTORY inci_data_arc AS '/opt/oracle/inci/archive';

GRANT READ, WRITE ON DIRECTORY inci_data_in  TO inci;
GRANT READ, WRITE ON DIRECTORY inci_data_out TO inci;
GRANT READ, WRITE ON DIRECTORY inci_data_bad TO inci;
GRANT READ, WRITE ON DIRECTORY inci_data_arc TO inci;

-- ---------------------------------------------------------------------
-- Check APEX_DATA_PARSER availability (for the .xlsx feed).
-- If this returns nothing, install APEX or fall back to CSV for that feed.
-- ---------------------------------------------------------------------
-- SELECT owner, object_name FROM dba_objects WHERE object_name = 'APEX_DATA_PARSER';
-- GRANT EXECUTE ON apex_data_parser TO inci;
