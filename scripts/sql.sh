#!/usr/bin/env bash
# Run a SQL script inside the Oracle container and surface compile errors.
#
#   ./scripts/sql.sh install.sql
#   ./scripts/sql.sh 04_packages/pkg_ingredient.pkb
#   ./scripts/sql.sh -q "SELECT COUNT(*) FROM products"
#
set -euo pipefail

CONTAINER="${ORACLE_CONTAINER:-oraxe}"
CONN="${ORACLE_CONN:-inci/Inci#2026@localhost:1521/FREEPDB1}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "-q" ]]; then
  # Inline query mode
  printf '%s\n' \
    "SET PAGESIZE 200 LINESIZE 200 FEEDBACK ON" \
    "${2};" \
    "EXIT" \
  | docker exec -i "${CONTAINER}" sqlplus -S "${CONN}"
  exit $?
fi

SCRIPT="${1:?usage: sql.sh <script.sql> | -q \"<query>\"}"
[[ -f "${REPO}/${SCRIPT}" ]] || { echo "not found: ${SCRIPT}" >&2; exit 1; }

# Copy the whole repo in so relative @@ includes resolve
docker exec "${CONTAINER}" mkdir -p /tmp/repo
docker cp "${REPO}/." "${CONTAINER}:/tmp/repo/" >/dev/null

OUT=$(printf '%s\n' \
  "WHENEVER SQLERROR CONTINUE" \
  "SET SERVEROUTPUT ON SIZE UNLIMITED" \
  "SET PAGESIZE 200 LINESIZE 200 FEEDBACK ON ECHO OFF" \
  "@/tmp/repo/${SCRIPT}" \
  "SHOW ERRORS" \
  "EXIT" \
| docker exec -i -w /tmp/repo "${CONTAINER}" sqlplus -S "${CONN}")
# -w matters: this SQL*Plus resolves @@ in install.sql against the
# working directory, not the calling script's folder (SP2-0310 otherwise).

echo "${OUT}"

# Fail loudly so Claude Code notices
if grep -qE '^(ORA-|PLS-|SP2-)' <<<"${OUT}"; then
  echo
  echo "!! errors above" >&2
  exit 1
fi
echo
echo "-- ok"
