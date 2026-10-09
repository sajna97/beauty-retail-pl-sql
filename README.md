# INCI Inspector

A cosmetic ingredient and regulatory compliance checker, built entirely in Oracle PL/SQL.

Give it a cosmetic product's ingredient list — the messy free-text kind printed on the back of a bottle — and it tells you what is actually in the product, which ingredients are banned or restricted in a given market, which declarable allergens are present, and produces a label compliance sheet.

Built on real, publicly licensed data: the [Open Beauty Facts](https://world.openbeautyfacts.org/data) product database and the EU's [CosIng](https://single-market-economy.ec.europa.eu/sectors/cosmetics/cosmetic-ingredient-database_en) cosmetic ingredient database.

---

## Why this exists

Cosmetics are regulated per market. A product legal in India may be blocked in the EU because one ingredient exceeds an Annex III concentration limit. Working that out means parsing a free-text INCI string into identified substances and evaluating them against a rule book that changes over time.

That is a real problem, and it is almost entirely a database problem.

---

## What it demonstrates

| | |
|---|---|
| **Heterogeneous ingestion** | JSONL, CSV, XML and XLSX, all landed through one metadata-driven dispatcher |
| **Dirty real data** | Open Beauty Facts has missing fields, multilingual names and inconsistent spellings — handled, not hidden |
| **Metadata-driven rules** | Both the DQ engine and the compliance engine read rules from tables; adding a market is an INSERT, not a code change |
| **Error tolerance** | `DBMS_ERRLOG` quarantines bad rows; an autonomous-transaction logger survives rollback |
| **String processing** | A bracket-aware INCI parser that does not break on `Parfum (Linalool, Limonene)` |
| **Fuzzy matching** | `UTL_MATCH` with a confidence threshold and a human review queue — no silent guessing |
| **File output** | Compliance report, label sheet and unmatched-token JSON via `UTL_FILE` |

---

## Quick start

```bash
# 1. Start Oracle XE (any 21c/23ai instance works)
docker run -d --name oraxe -p 1521:1521 \
  -e ORACLE_PASSWORD=oracle \
  gvenzl/oracle-free:latest

# 2. Fetch and subset the source data
./data/download.sh 20000

# 3. Make the files visible to the database
docker exec oraxe mkdir -p /opt/oracle/inci/{in,out,bad,archive,exec}
docker cp ./data/in/. oraxe:/opt/oracle/inci/in/
# .inci_listing is the location file of ext_inbound_listing; it must exist
docker exec oraxe touch /opt/oracle/inci/in/.inci_listing
docker cp ./00_setup/list_dir.sh oraxe:/opt/oracle/inci/exec/
docker exec oraxe chown -R oracle:oinstall /opt/oracle/inci
docker exec oraxe chmod 755 /opt/oracle/inci/exec/list_dir.sh
```

```sql
-- 4. Create the schema (as SYS)
@00_setup/01_create_user.sql
@00_setup/02_exec_directory.sql

-- 5. Build everything (as INCI)
@install.sql

-- 6. External tables, once the files are in place
@06_external_tables/01_ext_cosing.sql
```

---

## Repository layout

```
00_setup/            user, grants, directory objects
01_ddl/              tables, in dependency order
02_seed/             hand-curated reference data
03_types/            SQL object types for pipelined functions
04_packages/         pkg_util, pkg_ingest, pkg_ingredient, pkg_compliance
05_triggers/         audit and allergen-flag triggers
06_external_tables/  CosIng CSV and Open Beauty Facts JSONL
07_jobs/             DBMS_SCHEDULER definitions
data/download.sh     fetches and subsets the source data
data/in/, data/out/  inbound feeds and generated files
tests/               utPLSQL suite
docs/                ERD and design decisions
install.sql          builds the whole schema from empty
99_teardown.sql      drops everything
```

---

## The pipeline

```
  files in                  staging                core                 files out
  --------                  -------                ----                 ---------
  OBF .jsonl   ──┐                                                   ┌── compliance.csv
  CosIng .csv  ──┤                                                   ├── label_sheet.txt
  Annexes .xml ──┼──▶ pkg_ingest ──▶ stg_* ──▶ pkg_ingredient ──┐    └── unmatched.json
  Supplier.xlsx──┘                     │            │            │              ▲
                                       │            ▼            ▼              │
                                       │      product_ingredients               │
                                       ▼                         │              │
                                    pkg_dq ──▶ dq_results        ▼              │
                                                          pkg_compliance ───────┘
                                                                 │
                                                                 ▼
                                                        compliance_results
```

---

## Design decisions

Full reasoning in [`docs/design-decisions.md`](docs/design-decisions.md). The short version:

- **`parse_inci` is a pure function.** It takes a string and returns a collection; it does not touch tables. That keeps it testable, callable from SQL, and reusable.
- **Barcode is unique, not the primary key.** Some source records have no barcode, and a product will later have many variants.
- **Restrictions are effective-dated from day one.** Regulations change. Retrofitting `valid_from`/`valid_to` onto live data is miserable.
- **A market is a dimension, not a `CHAR(2)` column.**
- **Unmatched ingredients are kept, not discarded.** An unmatched token is a fact, and it feeds the review queue.
- **`NULL` product type on a restriction means "all types".** Encoding "applies to everything" as a `NULL` foreign key keeps the rule table small.

---

## Status

| Phase | |
|---|---|
| Schema and framework | ✅ |
| CosIng ingestion | ⬜ |
| Open Beauty Facts ingestion | ⬜ |
| DQ engine | ⬜ |
| INCI parser | ⬜ |
| Fuzzy matching | ⬜ |
| Compliance engine | ⬜ |
| Outbound files | ⬜ |
| Tests and scheduling | ⬜ |

---

## Data licences

Open Beauty Facts is published under the Open Database Licence; its contents under the Database Contents Licence. CosIng is published by the European Commission. Both are redistributed here by reference only — `data/download.sh` fetches them, the repository does not contain them.
