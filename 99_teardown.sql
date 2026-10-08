-- =====================================================================
-- 99_teardown.sql -- drop everything the project owns.
-- Run as INCI. Useful during development; do not ship it as the only
-- way to rebuild.
-- =====================================================================

SET SERVEROUTPUT ON
BEGIN
  FOR r IN (SELECT table_name FROM user_tables
             WHERE table_name NOT LIKE 'BIN$%'
             ORDER BY table_name) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
      dbms_output.put_line('dropped table  ' || r.table_name);
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('SKIP table     ' || r.table_name || ' : ' || SQLERRM);
    END;
  END LOOP;

  FOR r IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type IN ('PACKAGE','PROCEDURE','FUNCTION','VIEW','SEQUENCE')
             ORDER BY object_type) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
      dbms_output.put_line('dropped ' || LOWER(r.object_type) || ' ' || r.object_name);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- Types last -- they are referenced by the packages above.
  FOR r IN (SELECT type_name FROM user_types ORDER BY type_name) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TYPE ' || r.type_name || ' FORCE';
      dbms_output.put_line('dropped type   ' || r.type_name);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

PURGE RECYCLEBIN;
