#!/usr/bin/env bash
# Recompile everything invalid and report what is still broken.
# Claude Code should run this after every package change.
set -euo pipefail

CONTAINER="${ORACLE_CONTAINER:-oraxe}"
CONN="${ORACLE_CONN:-inci/Inci#2026@localhost:1521/FREEPDB1}"

OUT=$(printf '%s\n' \
  "SET PAGESIZE 200 LINESIZE 200 FEEDBACK OFF HEADING ON" \
  "BEGIN dbms_utility.compile_schema(USER, FALSE); END;" \
  "/" \
  "COLUMN object_name FORMAT A30" \
  "COLUMN object_type FORMAT A16" \
  "PROMPT" \
  "PROMPT === invalid objects ===" \
  "SELECT object_name, object_type FROM user_objects WHERE status <> 'VALID' ORDER BY 2,1;" \
  "PROMPT" \
  "PROMPT === errors ===" \
  "COLUMN name FORMAT A24" \
  "COLUMN text FORMAT A90" \
  "SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;" \
  "SET HEADING OFF" \
  "SELECT 'INVALID_COUNT=' || COUNT(*) FROM user_objects WHERE status <> 'VALID';" \
  "EXIT" \
| docker exec -i "${CONTAINER}" sqlplus -S "${CONN}")

echo "${OUT}"

# Decide on an explicit count, not on "no rows selected": FEEDBACK OFF
# suppresses that message, so the old check reported failure every time.
if grep -q "^INVALID_COUNT=0$" <<<"${OUT}"; then
  echo
  echo "-- all objects valid"
  exit 0
fi
exit 1
