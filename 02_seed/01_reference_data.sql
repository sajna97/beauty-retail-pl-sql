-- =====================================================================
-- 02_seed/01_reference_data.sql
-- Hand-curated reference data. This is the "manual entry" data source:
-- small, deliberate, and the part you own rather than import.
-- =====================================================================

-- ---------------------------------------------------------------------
-- REGULATION_SCHEMES
-- legal_ref is filled only where it is certain. A wrong citation on a
-- regulatory table is worse than an empty one.
-- ---------------------------------------------------------------------
INSERT INTO regulation_schemes (scheme_code, scheme_name, legal_ref)
VALUES ('EU_1223_2009', 'EU Cosmetic Products Regulation', 'Regulation (EC) No 1223/2009');
INSERT INTO regulation_schemes (scheme_code, scheme_name, legal_ref)
VALUES ('UK_SI_2019', 'UK Cosmetics Regulation', NULL);
INSERT INTO regulation_schemes (scheme_code, scheme_name, legal_ref)
VALUES ('IN_BIS', 'India cosmetics rules and BIS standards', NULL);
INSERT INTO regulation_schemes (scheme_code, scheme_name, legal_ref)
VALUES ('US_FDA', 'US FDA cosmetics regulation', NULL);

-- ---------------------------------------------------------------------
-- MARKETS
-- Resolve the scheme by code so the seed never depends on identity
-- values, which differ between builds.
-- ---------------------------------------------------------------------
INSERT INTO markets (market_code, market_name, iso_country_code, region, regulation_scheme_id, currency_code)
SELECT 'EU', 'European Union', NULL, 'Europe', rs.regulation_scheme_id, 'EUR'
  FROM regulation_schemes rs
 WHERE rs.scheme_code = 'EU_1223_2009';
INSERT INTO markets (market_code, market_name, iso_country_code, region, regulation_scheme_id, currency_code)
SELECT 'UK', 'United Kingdom', 'GB', 'Europe', rs.regulation_scheme_id, 'GBP'
  FROM regulation_schemes rs
 WHERE rs.scheme_code = 'UK_SI_2019';
INSERT INTO markets (market_code, market_name, iso_country_code, region, regulation_scheme_id, currency_code)
SELECT 'IN', 'India', 'IN', 'Asia', rs.regulation_scheme_id, 'INR'
  FROM regulation_schemes rs
 WHERE rs.scheme_code = 'IN_BIS';
INSERT INTO markets (market_code, market_name, iso_country_code, region, regulation_scheme_id, currency_code)
SELECT 'US', 'United States', 'US', 'Americas', rs.regulation_scheme_id, 'USD'
  FROM regulation_schemes rs
 WHERE rs.scheme_code = 'US_FDA';

-- ---------------------------------------------------------------------
-- PRODUCT_TYPES
-- The flags are what the compliance engine actually reads.
-- ---------------------------------------------------------------------
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('LEAVE_ON_FACE', 'Leave-on facial product', 'N', 'N', 'N', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('LEAVE_ON_BODY', 'Leave-on body product', 'N', 'N', 'N', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('RINSE_OFF', 'Rinse-off product', 'Y', 'N', 'N', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('EYE_AREA', 'Eye-area product', 'N', 'N', 'Y', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('LIP', 'Lip product (ingestible risk)', 'N', 'N', 'N', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('ORAL_CARE', 'Oral care product', 'Y', 'Y', 'N', 'N');
INSERT INTO product_types (product_type_code, product_type_name, rinse_off_flag, oral_care_flag, eye_area_flag, children_flag)
VALUES ('CHILDREN', 'Product for children under three', 'N', 'N', 'N', 'Y');

-- ---------------------------------------------------------------------
-- CATEGORIES -- two levels is enough to prove the hierarchy works
-- ---------------------------------------------------------------------
INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
VALUES ('MAKEUP', 'Makeup', NULL, NULL, 1);
INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
VALUES ('SKINCARE', 'Skincare', NULL, NULL, 1);
INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
VALUES ('HAIRCARE', 'Haircare', NULL, NULL, 1);

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'FOUNDATION', 'Foundation', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'MAKEUP' AND pt.product_type_code = 'LEAVE_ON_FACE';

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'LIPSTICK', 'Lipstick', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'MAKEUP' AND pt.product_type_code = 'LIP';

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'MASCARA', 'Mascara', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'MAKEUP' AND pt.product_type_code = 'EYE_AREA';

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'MOISTURISER', 'Moisturiser', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'SKINCARE' AND pt.product_type_code = 'LEAVE_ON_FACE';

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'CLEANSER', 'Cleanser', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'SKINCARE' AND pt.product_type_code = 'RINSE_OFF';

INSERT INTO categories (category_code, category_name, parent_category_id, product_type_id, level_no)
SELECT 'SHAMPOO', 'Shampoo', c.category_id, pt.product_type_id, 2
  FROM categories c, product_types pt
 WHERE c.category_code = 'HAIRCARE' AND pt.product_type_code = 'RINSE_OFF';

-- ---------------------------------------------------------------------
-- REF_FILE_TYPE -- the dispatch table
-- ---------------------------------------------------------------------
INSERT INTO ref_file_type (file_type_code, description, file_name_pattern, file_format, parser_proc, target_table)
VALUES ('OBF_PRODUCTS', 'Open Beauty Facts product export', 'OBF_PRODUCTS%.jsonl', 'JSONL',
        'pkg_ingest.load_obf_products', 'STG_OBF_PRODUCT');
INSERT INTO ref_file_type (file_type_code, description, file_name_pattern, file_format, parser_proc, target_table)
VALUES ('COSING_INGREDIENTS', 'EU CosIng ingredient export', 'COSING_INGREDIENTS%.csv', 'CSV',
        'pkg_ingest.load_cosing_ingredients', 'STG_COSING_INGREDIENT');
INSERT INTO ref_file_type (file_type_code, description, file_name_pattern, file_format, parser_proc, target_table)
VALUES ('COSING_ANNEXES', 'EU CosIng annex II/III/IV/V/VI restrictions', 'COSING_ANNEX%.csv', 'CSV',
        'pkg_ingest.load_cosing_annexes', 'INGREDIENT_RESTRICTIONS');
INSERT INTO ref_file_type (file_type_code, description, file_name_pattern, file_format, parser_proc, target_table)
VALUES ('SUPPLIER_PRICES', 'Supplier new-launch and price sheet', 'SUPPLIER_PRICES%.xlsx', 'XLSX',
        'pkg_ingest.load_supplier_prices', 'STG_SUPPLIER_PRICE');

-- Parked until their parsers exist: process_directory skips files of an
-- inactive type instead of failing the batch on a stub every night.
-- Switching a feed on is one UPDATE here.
UPDATE ref_file_type
   SET active_flag = 'N'
 WHERE file_type_code IN ('OBF_PRODUCTS', 'COSING_ANNEXES', 'SUPPLIER_PRICES');

-- ---------------------------------------------------------------------
-- ERROR_CODES -- allocate ranges up front
-- ---------------------------------------------------------------------
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20001, 'PKG_UTIL',       'E_NOT_IMPLEMENTED',   'Feature not implemented yet', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20002, 'PKG_UTIL',       'E_INVALID_PARAM',     'Invalid parameter: %s', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20003, 'PKG_UTIL',       'E_FILE_NOT_FOUND',    'File not found in directory: %s', 'ERROR');

INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20101, 'PKG_INGEST',     'E_UNKNOWN_FILE_TYPE', 'No active file type matches file name: %s', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20102, 'PKG_INGEST',     'E_DUPLICATE_FILE',    'File already loaded (checksum match): %s', 'WARN');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20103, 'PKG_INGEST',     'E_PARSER_FAILED',     'Parser %s failed for file %s', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20104, 'PKG_INGEST',     'E_NO_APEX_PARSER',    'APEX_DATA_PARSER is not available; convert the xlsx to CSV', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20105, 'PKG_INGEST',     'E_AMBIGUOUS_FILE_TYPE', 'File %s matches more than one active file type', 'ERROR');

INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20201, 'PKG_INGREDIENT', 'E_EMPTY_INCI',        'Product %s has no INCI string to parse', 'WARN');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20202, 'PKG_INGREDIENT', 'E_PARSE_FAILED',      'INCI parse failed for product %s', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20203, 'PKG_INGREDIENT', 'E_TOO_MANY_TOKENS',   'INCI string for product %s exceeds token limit', 'WARN');

INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20301, 'PKG_COMPLIANCE', 'E_UNKNOWN_MARKET',    'Market code not found: %s', 'ERROR');
INSERT INTO error_codes (error_code, module_name, error_name, message_text, severity) VALUES (-20302, 'PKG_COMPLIANCE', 'E_NOT_PARSED',        'Product %s has not been parsed; cannot assess compliance', 'ERROR');

-- ---------------------------------------------------------------------
-- DQ_RULES -- start with these ten; add more as you meet real bad data
-- ---------------------------------------------------------------------
INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PROD_NAME_NOT_NULL', 'Product must have a name', 'PRODUCTS', 'PRODUCT_NAME', 'NOT_NULL', NULL, 'ERROR', 'Y');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PROD_BARCODE_FORMAT', 'Barcode must be 8-14 digits', 'PRODUCTS', 'BARCODE', 'PATTERN', '^[0-9]{8,14}$', 'WARN', 'N');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PROD_HAS_INCI', 'Product should have an ingredient list', 'PRODUCTS', 'INCI_RAW', 'NOT_NULL', NULL, 'WARN', 'N');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PROD_NAME_NOT_JUNK', 'Product name must contain a letter', 'PRODUCTS', 'PRODUCT_NAME', 'PATTERN', '[A-Za-z]', 'ERROR', 'Y');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PROD_NAME_LENGTH', 'Product name is suspiciously short', 'PRODUCTS', 'PRODUCT_NAME', 'SQL',
        'LENGTH(product_name) >= 3', 'WARN', 'N');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('ING_INCI_NOT_NULL', 'Ingredient must have an INCI name', 'INGREDIENTS', 'INCI_NAME', 'NOT_NULL', NULL, 'ERROR', 'Y');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('ING_CAS_FORMAT', 'CAS number format nnn-nn-n', 'INGREDIENTS', 'CAS_NUMBER', 'PATTERN',
        '^[0-9]{2,7}-[0-9]{2}-[0-9]$', 'INFO', 'N');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('RESTR_CONC_RANGE', 'Concentration limit must be 0-100', 'INGREDIENT_RESTRICTIONS', 'MAX_CONCENTRATION', 'RANGE',
        '0,100', 'ERROR', 'Y');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PI_POSITION_POSITIVE', 'Ingredient position must be positive', 'PRODUCT_INGREDIENTS', 'POSITION_NO', 'SQL',
        'position_no > 0', 'ERROR', 'Y');

INSERT INTO dq_rules (rule_code, description, target_table, target_column, rule_type, rule_expression, severity, reject_row)
VALUES ('PI_MATCH_RATE', 'Product with under half its tokens matched needs review', 'PRODUCTS', NULL, 'SQL',
        'unmatched_count IS NULL OR token_count IS NULL OR unmatched_count <= token_count/2', 'WARN', 'N');

-- ---------------------------------------------------------------------
-- SUPPLIERS
-- ---------------------------------------------------------------------
INSERT INTO suppliers (supplier_code, supplier_name, currency_code, contact_email)
VALUES ('SUP001', 'Nordic Beauty Distribution', 'EUR', 'orders@nordicbeauty.example');
INSERT INTO suppliers (supplier_code, supplier_name, currency_code, contact_email)
VALUES ('SUP002', 'Mumbai Cosmetics Trading', 'INR', 'sales@mumbaicos.example');

COMMIT;
