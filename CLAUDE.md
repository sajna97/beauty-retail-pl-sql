# Beauty & Fashion Retail Intelligence Platform

Oracle PL/SQL portfolio project. Built from scratch on real public data
(Open Beauty Facts, EU CosIng, Kaggle Sephora and H&M datasets).

This is a **portfolio project**. The point is not to finish fast — it is to
produce code Sajna can explain, line by line, in an interview.

---

## How to work with me on this repo

**Explain before you write.** For anything longer than ~20 lines, state the
approach in plain English first and wait for me to agree. Use plan mode for
any new package.

**One thing at a time.** Never write more than one package body per turn.
Never touch DDL and package logic in the same turn.

**Comment the *why*, not the *what*.** `-- loop over tokens` is noise.
`-- split at depth 0 so Parfum (Linalool, Limonene) stays one token` is the
kind of comment this repo wants.

**Flag every judgement call.** When you pick between two reasonable
approaches, say so and say why in one line. I want to know where the
decisions were.

**No silent cleverness.** If a query needs an analytic function, a hint, or
a non-obvious construct, say what it does before using it.

**Ask rather than assume** about business rules. Guessing at a regulatory
rule is worse than stopping.

---

## Project layout

```
00_setup/            user, grants, directory objects
01_ddl/              tables, in dependency order
02_seed/             hand-curated reference data
03_types/            SQL object types for pipelined functions
04_packages/         .pks spec then .pkb body, same base name
05_triggers/
06_external_tables/
07_jobs/             DBMS_SCHEDULER
09_mviews/
data/download.sh     fetches and subsets source data
data/in/  data/out/
tests/               utPLSQL
docs/design-decisions.md
install.sql          builds the schema from empty
99_teardown.sql
```

## Database

Oracle XE in Docker, container `oraxe`, service `FREEPDB1`, schema `INCI`.

```bash
./scripts/sql.sh <file.sql>      # run a script, show errors
./scripts/compile.sh             # recompile all packages, list invalid objects
```

Oracle-visible directories inside the container:
`/opt/oracle/inci/{in,out,bad,archive}` mapped to directory objects
`INCI_DATA_IN`, `INCI_DATA_OUT`, `INCI_DATA_BAD`, `INCI_DATA_ARC`.

---

## PL/SQL conventions

- **Naming**: tables plural (`products`), packages `pkg_*`, spec `.pks`,
  body `.pkb`. Constraints `<table>_pk|uk|fk<n>|ck<n>`. Indexes `<table>_ix<n>`.
- **Keys**: identity column surrogate PK on every table. Natural keys get a
  unique constraint, never the PK.
- **Staging tables are all VARCHAR2.** Typing happens on promotion, not load.
- **Effective-date anything regulatory** — `valid_from` / `valid_to`.
- **Errors**: allocate from `error_codes`, raise via `pkg_util.raise_error`.
  Never a bare `RAISE_APPLICATION_ERROR(-20001, ...)`.
- **Logging**: every entry point opens a run with `pkg_util.start_run` and
  closes it. `WHEN OTHERS` calls `pkg_util.log_error` then re-raises —
  never swallows.
- **Bulk**: `BULK COLLECT ... LIMIT 500`, `FORALL ... SAVE EXCEPTIONS`.
  Row-by-row loops only where correctness demands it, with a comment saying why.
- **Dynamic SQL**: bind every value. Table and column names cannot be bound,
  so validate them against `user_tab_columns` before concatenating.
- **Pure functions stay pure.** `pkg_ingredient.parse_inci` takes a string and
  returns a collection. It does not read or write tables. Persistence lives in
  a separate wrapper.
- **Business rules live in tables**, not in `IF market_code = 'EU' THEN`.

## Style

- 2-space indent, keywords uppercase, identifiers lowercase.
- One statement per line; align `INTO` / `FROM` / `WHERE` at column 3.
- Package spec carries the documentation. Body carries the reasoning.

---

## Git

- One commit per logical unit. Message: `<area>: <what changed>`.
- Commit only after the code compiles and I have read it.
- Never commit `data/in/` or `data/out/` contents.
- Never `git push` unless I ask.

## Never do

- Never run `99_teardown.sql` without asking.
- Never `DROP` or `TRUNCATE` anything without asking.
- Never edit `install.sql` to skip a failing step — fix the step.
- Never add a dependency on a paid or licensed Oracle feature.
  This must run on XE.
- Never write a package body longer than ~400 lines. Split it.
