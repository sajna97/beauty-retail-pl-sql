-- =====================================================================
-- 01_ddl/01_control_tables.sql
-- The framework layer: file tracking, run logging, error registry,
-- audit trail and the metadata-driven data-quality rule engine.
--
-- Nothing here is specific to cosmetics. This entire file is designed to
-- be lifted wholesale into the larger retail platform later.
-- =====================================================================

-- ---------------------------------------------------------------------
-- REF_FILE_TYPE
-- Drives file dispatch. pkg_ingest looks the incoming file up here and
-- calls PARSER_PROC dynamically. Adding a new feed = one INSERT.
-- ---------------------------------------------------------------------
CREATE TABLE ref_file_type (
  file_type_id      NUMBER GENERATED ALWAYS AS IDENTITY,
  file_type_code    VARCHAR2(30)   NOT NULL,
  description       VARCHAR2(200),
  file_name_pattern VARCHAR2(100)  NOT NULL,   -- e.g. 'OBF_PRODUCTS_%.jsonl'
  file_format       VARCHAR2(20)   NOT NULL,   -- JSONL, CSV, XML, FIXED, XLSX
  parser_proc       VARCHAR2(100)  NOT NULL,   -- e.g. 'pkg_ingest.load_obf_products'
  target_table      VARCHAR2(30),
  active_flag       CHAR(1) DEFAULT 'Y' NOT NULL,
  created_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT ref_file_type_pk  PRIMARY KEY (file_type_id),
  CONSTRAINT ref_file_type_uk  UNIQUE (file_type_code),
  CONSTRAINT ref_file_type_ck1 CHECK (active_flag IN ('Y','N')),
  CONSTRAINT ref_file_type_ck2 CHECK (file_format IN ('JSONL','JSON','CSV','TSV','XML','FIXED','XLSX'))
);

COMMENT ON TABLE ref_file_type IS 'Metadata-driven file dispatch: never hard-code filename IF/ELSIF chains.';

-- ---------------------------------------------------------------------
-- FILE_REGISTRY
-- One row per physical file seen. The checksum is what stops the same
-- file being loaded twice -- a mistake every real ETL makes once.
--
-- Retry rule: a FAILED file may be loaded again, and the retry REUSES
-- this row (attempt_count + 1) rather than inserting a new one -- the
-- unique checksum would refuse a second row anyway. Per-attempt history
-- is not lost: each attempt opens its own JOB_RUN_LOG row with file_id.
-- ---------------------------------------------------------------------
CREATE TABLE file_registry (
  file_id         NUMBER GENERATED ALWAYS AS IDENTITY,
  file_type_id    NUMBER         NOT NULL,
  directory_name  VARCHAR2(30)   NOT NULL,
  file_name       VARCHAR2(400)  NOT NULL,
  file_checksum   VARCHAR2(64)   NOT NULL,   -- SHA-256 hex
  file_size_bytes NUMBER,
  received_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  load_status     VARCHAR2(20) DEFAULT 'REGISTERED' NOT NULL,
  attempt_count   NUMBER DEFAULT 1 NOT NULL,
  load_started_at TIMESTAMP,
  load_ended_at   TIMESTAMP,
  rows_read       NUMBER DEFAULT 0,
  rows_loaded     NUMBER DEFAULT 0,
  rows_rejected   NUMBER DEFAULT 0,
  error_message   VARCHAR2(4000),
  CONSTRAINT file_registry_pk  PRIMARY KEY (file_id),
  CONSTRAINT file_registry_uk  UNIQUE (file_checksum),
  CONSTRAINT file_registry_fk1 FOREIGN KEY (file_type_id) REFERENCES ref_file_type (file_type_id),
  CONSTRAINT file_registry_ck1 CHECK (load_status IN
        ('REGISTERED','LOADING','LOADED','FAILED','SKIPPED_DUPLICATE')),
  CONSTRAINT file_registry_ck2 CHECK (attempt_count >= 1)
);

CREATE INDEX file_registry_ix1 ON file_registry (file_type_id, load_status);

-- ---------------------------------------------------------------------
-- JOB_RUN_LOG
-- Every package entry point opens a run and closes it. Row counts and
-- elapsed time live here, which is what makes a failed nightly run
-- diagnosable instead of a guessing game.
-- ---------------------------------------------------------------------
CREATE TABLE job_run_log (
  run_id          NUMBER GENERATED ALWAYS AS IDENTITY,
  parent_run_id   NUMBER,
  job_name        VARCHAR2(100) NOT NULL,
  module_name     VARCHAR2(100),
  file_id         NUMBER,
  started_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  ended_at        TIMESTAMP,
  status          VARCHAR2(20) DEFAULT 'RUNNING' NOT NULL,
  rows_processed  NUMBER DEFAULT 0,
  rows_rejected   NUMBER DEFAULT 0,
  message         VARCHAR2(4000),
  db_user         VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV','SESSION_USER') NOT NULL,
  CONSTRAINT job_run_log_pk  PRIMARY KEY (run_id),
  CONSTRAINT job_run_log_fk1 FOREIGN KEY (parent_run_id) REFERENCES job_run_log (run_id),
  CONSTRAINT job_run_log_fk2 FOREIGN KEY (file_id)       REFERENCES file_registry (file_id),
  CONSTRAINT job_run_log_ck1 CHECK (status IN ('RUNNING','SUCCESS','WARNING','FAILED'))
);

CREATE INDEX job_run_log_ix1 ON job_run_log (job_name, started_at);

-- ---------------------------------------------------------------------
-- ERROR_CODES
-- A registry so -20xxx numbers are allocated, not invented ad hoc.
-- Ranges: -20000..-20099 util, -20100..-20199 ingest,
--         -20200..-20299 ingredient, -20300..-20399 compliance.
-- ---------------------------------------------------------------------
CREATE TABLE error_codes (
  error_code_id NUMBER GENERATED ALWAYS AS IDENTITY,
  error_code    NUMBER        NOT NULL,
  module_name   VARCHAR2(50)  NOT NULL,
  error_name    VARCHAR2(50)  NOT NULL,
  message_text  VARCHAR2(500) NOT NULL,
  severity      VARCHAR2(10) DEFAULT 'ERROR' NOT NULL,
  CONSTRAINT error_codes_pk  PRIMARY KEY (error_code_id),
  CONSTRAINT error_codes_uk1 UNIQUE (error_code),
  CONSTRAINT error_codes_uk2 UNIQUE (error_name),
  CONSTRAINT error_codes_ck1 CHECK (error_code BETWEEN -20999 AND -20000),
  CONSTRAINT error_codes_ck2 CHECK (severity IN ('INFO','WARN','ERROR','FATAL'))
);

-- ---------------------------------------------------------------------
-- EXCEPTION_LOG
-- Written by an AUTONOMOUS TRANSACTION so the log survives the rollback
-- of the transaction that failed. This is the single most useful thing
-- in the whole framework.
-- ---------------------------------------------------------------------
CREATE TABLE exception_log (
  exception_id  NUMBER GENERATED ALWAYS AS IDENTITY,
  run_id        NUMBER,
  logged_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  module_name   VARCHAR2(100),
  error_code    NUMBER,
  error_message VARCHAR2(4000),
  error_stack   CLOB,
  call_stack    CLOB,
  context_info  VARCHAR2(4000),
  db_user       VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV','SESSION_USER') NOT NULL,
  CONSTRAINT exception_log_pk PRIMARY KEY (exception_id)
);

CREATE INDEX exception_log_ix1 ON exception_log (logged_at);

-- ---------------------------------------------------------------------
-- AUDIT_LOG
-- Written by statement/row triggers on the tables you care about.
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
  audit_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  table_name   VARCHAR2(30)  NOT NULL,
  pk_value     VARCHAR2(100),
  operation    VARCHAR2(10)  NOT NULL,
  changed_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  changed_by   VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV','SESSION_USER') NOT NULL,
  old_values   CLOB,
  new_values   CLOB,
  CONSTRAINT audit_log_pk  PRIMARY KEY (audit_id),
  CONSTRAINT audit_log_ck1 CHECK (operation IN ('INSERT','UPDATE','DELETE'))
);

CREATE INDEX audit_log_ix1 ON audit_log (table_name, changed_at);

-- ---------------------------------------------------------------------
-- DQ_RULES  --  the metadata-driven validation engine
--
-- RULE_TYPE tells pkg_dq how to interpret RULE_EXPRESSION:
--   NOT_NULL   -- expression ignored
--   PATTERN    -- expression is a regex the column must match
--   RANGE      -- expression is 'min,max'
--   LOOKUP     -- expression is 'table.column' the value must exist in
--   SQL        -- expression is a full boolean predicate; rows where it
--                 is FALSE are violations. This is the escape hatch.
-- ---------------------------------------------------------------------
CREATE TABLE dq_rules (
  rule_id         NUMBER GENERATED ALWAYS AS IDENTITY,
  rule_code       VARCHAR2(50)   NOT NULL,
  description     VARCHAR2(400),
  target_table    VARCHAR2(30)   NOT NULL,
  target_column   VARCHAR2(30),
  rule_type       VARCHAR2(20)   NOT NULL,
  rule_expression VARCHAR2(4000),
  severity        VARCHAR2(10) DEFAULT 'ERROR' NOT NULL,
  reject_row      CHAR(1) DEFAULT 'N' NOT NULL,  -- Y = quarantine, N = flag only
  active_flag     CHAR(1) DEFAULT 'Y' NOT NULL,
  valid_from      DATE DEFAULT DATE '2000-01-01' NOT NULL,
  valid_to        DATE DEFAULT DATE '9999-12-31' NOT NULL,
  created_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT dq_rules_pk  PRIMARY KEY (rule_id),
  CONSTRAINT dq_rules_uk  UNIQUE (rule_code),
  CONSTRAINT dq_rules_ck1 CHECK (rule_type IN ('NOT_NULL','PATTERN','RANGE','LOOKUP','UNIQUE','SQL')),
  CONSTRAINT dq_rules_ck2 CHECK (severity  IN ('INFO','WARN','ERROR')),
  CONSTRAINT dq_rules_ck3 CHECK (active_flag IN ('Y','N')),
  CONSTRAINT dq_rules_ck4 CHECK (reject_row  IN ('Y','N')),
  CONSTRAINT dq_rules_ck5 CHECK (valid_to > valid_from)
);

COMMENT ON COLUMN dq_rules.valid_to IS 'Exclusive upper bound: applies while valid_from <= d < valid_to';

-- ---------------------------------------------------------------------
-- DQ_RESULTS -- one row per violation found
-- ---------------------------------------------------------------------
CREATE TABLE dq_results (
  result_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  run_id        NUMBER        NOT NULL,
  rule_id       NUMBER        NOT NULL,
  target_table  VARCHAR2(30)  NOT NULL,
  offending_pk  VARCHAR2(100),
  column_value  VARCHAR2(1000),
  message       VARCHAR2(1000),
  detected_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT dq_results_pk  PRIMARY KEY (result_id),
  CONSTRAINT dq_results_fk1 FOREIGN KEY (run_id)  REFERENCES job_run_log (run_id),
  CONSTRAINT dq_results_fk2 FOREIGN KEY (rule_id) REFERENCES dq_rules (rule_id)
);

CREATE INDEX dq_results_ix1 ON dq_results (run_id, rule_id);

-- ---------------------------------------------------------------------
-- MATCH_REVIEW_QUEUE
-- Anything the fuzzy matcher is not confident about lands here instead
-- of being silently guessed. Reusable for brand matching later.
-- ---------------------------------------------------------------------
CREATE TABLE match_review_queue (
  queue_id          NUMBER GENERATED ALWAYS AS IDENTITY,
  source_table      VARCHAR2(30)  NOT NULL,
  source_id         NUMBER        NOT NULL,
  raw_value         VARCHAR2(1000) NOT NULL,
  normalised_value  VARCHAR2(1000),
  best_candidate_id NUMBER,
  best_candidate    VARCHAR2(1000),
  match_score       NUMBER(5,2),
  status            VARCHAR2(20) DEFAULT 'PENDING' NOT NULL,
  resolved_id       NUMBER,
  reviewed_by       VARCHAR2(128),
  reviewed_at       TIMESTAMP,
  created_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT match_review_queue_pk  PRIMARY KEY (queue_id),
  CONSTRAINT match_review_queue_ck1 CHECK (status IN ('PENDING','ACCEPTED','REJECTED','NEW_ENTITY'))
);

CREATE INDEX match_review_queue_ix1 ON match_review_queue (status, source_table);
