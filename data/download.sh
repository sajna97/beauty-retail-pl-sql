#!/usr/bin/env bash
# =====================================================================
# data/download.sh -- fetch and subset the source data.
#
# Usage:  ./data/download.sh [line_count]
# Default subset size is 20000 JSONL lines, which is plenty for
# development and small enough to load in under a minute.
#
# Having this script in the repo is what makes the project runnable by
# a stranger. Most PL/SQL repos on GitHub cannot be run at all.
# =====================================================================
set -euo pipefail

LINES="${1:-20000}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_DIR="${HERE}/in"
mkdir -p "${IN_DIR}"

echo "==> Target directory: ${IN_DIR}"
echo "==> Subset size:      ${LINES} products"
echo

# ---------------------------------------------------------------------
# 1. Open Beauty Facts -- product master (JSONL, Open Database Licence)
#
# The full export is ~0.9 GB compressed. We stream it and stop after
# LINES rows, so nothing large is ever written to disk.
# ---------------------------------------------------------------------
OBF_URL="https://static.openbeautyfacts.org/data/openbeautyfacts-products.jsonl.gz"
OBF_OUT="${IN_DIR}/OBF_PRODUCTS.jsonl"

if [[ -f "${OBF_OUT}" ]]; then
  echo "--> OBF_PRODUCTS.jsonl already present, skipping"
else
  echo "--> Downloading Open Beauty Facts (streaming first ${LINES} lines)..."
  curl -sSL "${OBF_URL}" \
    | gunzip -c \
    | head -n "${LINES}" \
    > "${OBF_OUT}" || true
  echo "    wrote $(wc -l < "${OBF_OUT}") lines"
fi

# ---------------------------------------------------------------------
# 2. EU CosIng -- ingredient master and annex restrictions
#
# The Commission's own download page changes location periodically. The
# biobricks mirror is stable and machine-readable.
#
# Put the resulting file at:  in/COSING_INGREDIENTS.csv
# and the annex export at:    in/COSING_ANNEX_II.xml (etc.)
# ---------------------------------------------------------------------
echo
echo "--> CosIng: manual step"
echo "    Official : https://single-market-economy.ec.europa.eu/sectors/cosmetics/cosmetic-ingredient-database_en"
echo "    Mirror   : https://github.com/biobricks-ai/cosing-kg"
echo "    Save the ingredient export as ${IN_DIR}/COSING_INGREDIENTS.csv"
echo "    Save each annex export as    ${IN_DIR}/COSING_ANNEX_<n>.xml"

# ---------------------------------------------------------------------
# 3. Supplier price list (.xlsx) -- you create this one
# ---------------------------------------------------------------------
echo
echo "--> Supplier sheet: create ${IN_DIR}/SUPPLIER_PRICES_202608.xlsx"
echo "    Columns: barcode | product_name | brand | cost_price | currency | launch_date"
echo "    20 rows is enough. Include two deliberately bad rows so the"
echo "    DQ layer has something to catch."

# ---------------------------------------------------------------------
# 4. Copy into the database directory
#
# On Docker XE the Oracle process cannot see your host filesystem unless
# you mounted it. Either mount ./data/in to /opt/oracle/inci/in at
# container start, or copy the files in:
#
#   docker exec <container> mkdir -p /opt/oracle/inci/{in,out,bad,archive}
#   docker cp ./data/in/. <container>:/opt/oracle/inci/in/
#   docker exec <container> chown -R oracle:oinstall /opt/oracle/inci
# ---------------------------------------------------------------------
echo
echo "==> Next: make these files visible to the database."
echo "    See the 'Getting the files where Oracle can see them' section"
echo "    in README.md."
