# Design decisions

Written as they are made. Each entry: the decision, the alternative, and why.

---

### `parse_inci` is a pure function

**Decision.** The parser takes a `CLOB` and returns a collection. It does not read or write any table.

**Alternative.** A procedure that reads `products.inci_raw` and writes `product_ingredients` directly — fewer moving parts.

**Why.** A pure function can be unit-tested with a literal, called from SQL (`SELECT * FROM TABLE(pkg_ingredient.parse_inci('Aqua, Glycerin'))`), and reused anywhere — including from an API layer that has no product row yet. Persistence lives in a thin wrapper, `parse_product`. The separation costs one extra procedure and buys testability.

---

### Barcode is unique, not the primary key

**Decision.** `products.product_id` is an identity column; `barcode` has a unique constraint (which allows many NULLs).

**Alternative.** Natural key on barcode.

**Why.** Two reasons. Some Open Beauty Facts records have no barcode at all, and a natural-key design would have to reject them. And in the larger platform this schema grows into, one product has many sellable variants, each with its own barcode — so the barcode belongs on the variant, not the product. Splitting later is a migration; splitting now is free.

---

### Restrictions are effective-dated from day one

**Decision.** `ingredient_restrictions` carries `valid_from` / `valid_to`.

**Alternative.** Current-state only, updated in place when a regulation changes.

**Why.** Regulations change on known dates, and the interesting question is often "was this product compliant when we shipped it in March?" — which current-state data cannot answer. Retrofitting effective dating onto a live table means reconstructing history you no longer have.

---

### Rules belong to a regulation scheme; markets point at a scheme

**Decision.** `regulation_schemes` is a table. `markets` references it, and `ingredient_restrictions` and `allergens` reference the scheme — not the market. `compliance_results` still records the market, because a verdict is about where you sell.

**Alternative.** Restrictions keyed by `market_id` (the first draft of this schema), or a `CHAR(2)` country column.

**Why.** Several markets share one rule book — the EU, Norway and Iceland all follow EC 1223/2009. Keyed by market, adding Norway means copying every EU rule, and the copies drift apart. Keyed by scheme, adding Norway is one `markets` row.

---

### Effective-date ranges are half-open

**Decision.** `valid_from` is inclusive, `valid_to` is exclusive: a rule applies on day `d` when `valid_from <= d AND d < valid_to`.

**Alternative.** `d BETWEEN valid_from AND valid_to`.

**Why.** `BETWEEN` is inclusive at both ends, so a rule ending on the day its replacement starts would overlap it for one day and both would fire. Half-open ranges chain without gaps or overlaps. The `CHECK (valid_to > valid_from)` constraints already assume this.

---

### Allergens are rule-book entries, not ingredients

**Decision.** `allergens` holds one row per entry in a scheme's allergen list, effective-dated. `allergen_ingredients` maps each entry to one or more ingredients. Thresholds and `valid_from` have no defaults.

**Alternative.** One row per ingredient with a unique `ingredient_id` and default 0.001% / 0.01% thresholds (the first draft).

**Why.** Regulation (EU) 2023/1545 expanded the EU list from 26 to roughly 80 entries, and several entries (essential oils, extracts) cover more than one INCI name, which a one-row-per-ingredient table cannot represent. Effective dating lets the original 26 and the new entries coexist with their real start dates. Defaults on regulatory values would hide missing data behind a plausible-looking number.

---

### A failed or interrupted file can be retried; the retry reuses its registry row

**Decision.** A file in status `FAILED`, `LOADING` or `REGISTERED` may be loaded again. The retry updates the existing `file_registry` row and increments `attempt_count`. There is no `SKIPPED_DUPLICATE` status; a re-sent copy of a `LOADED` file is skipped and the skip is logged on that attempt's `job_run_log` row.

**Alternative.** Insert a new registry row per attempt; leave `LOADING` rows for a human; mark duplicates with their own status.

**Why.** The checksum is unique, so a second row is impossible without weakening the duplicate check that is the whole point of the table. History is not lost: each attempt opens its own `job_run_log` row carrying the `file_id`. `LOADING` or `REGISTERED` found at registration means a session died before recording an outcome — part-way through the load, or before it started — the same situation as `FAILED`, just without the error message. And a duplicate has no row of its own to carry a status, which is why that status could never actually be written.

**Assumption this depends on.** Only one loader runs at a time. If two ran concurrently, the second would see the first's genuine, in-progress `REGISTERED` or `LOADING` row and retry it — loading the file twice. Today a single `DBMS_SCHEDULER` job is the only caller, so the assumption holds; if that changes, `register_file` needs a lock (e.g. `SELECT … FOR UPDATE NOWAIT` on the registry row, held for the whole load).

---

### Unmatched ingredient tokens are kept

**Decision.** `product_ingredients.ingredient_id` is nullable; unmatched tokens are stored with `match_method = 'NONE'`.

**Alternative.** Discard tokens that do not match CosIng.

**Why.** An unmatched token is evidence — of a gap in the reference data, a typo in the source, or a genuinely new substance. Discarding it destroys the only signal that the reference data is incomplete, and it silently understates the ingredient count. It also feeds the review queue, which is how the reference data improves over time.

---

### `NULL` product type means "all product types"

**Decision.** A restriction with `product_type_id IS NULL` applies to every product type.

**Alternative.** A row per applicable product type.

**Why.** Most Annex II bans apply universally; enumerating seven rows for each would multiply the rule table sevenfold with no added meaning. The cost is that the matching predicate needs an explicit `(r.product_type_id IS NULL OR r.product_type_id = p.product_type_id)`, which is a small, contained complexity.

---

### Fuzzy matches below the review threshold are queued, not accepted

**Decision.** A Jaro-Winkler score between the accept and review thresholds writes to `match_review_queue` with status `PENDING`.

**Alternative.** Accept the best match above a single threshold.

**Why.** A silent 78% match on a regulated ingredient is a compliance error dressed up as a feature. The queue makes uncertainty visible and reviewable, and it is the same mechanism brand normalisation will need later.

---

### Files are checksummed before they are read

**Decision.** `file_registry.file_checksum` is SHA-256 of the file content, with a unique constraint.

**Alternative.** Track by file name and modification date.

**Why.** Names lie. The same file gets re-sent with a new name, or a different file arrives with the same name. A content hash is the only thing that reliably answers "have I already loaded this?" — and duplicate loading is the single most common ETL failure.

---

### Normalisation uses nested `TRANSLATE`, not `REGEXP_REPLACE`

**Decision.** `normalised_name` on `brands`, `brand_aliases` and `ingredients` keeps only `A-Z a-z 0-9` and uppercases, using

```sql
CAST(UPPER(TRANSLATE(x,
       'A' || TRANSLATE(x, 'AABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'A'),
       'A')) AS VARCHAR2(200 BYTE))
```

`pkg_util.normalise` uses the identical expression.

**Alternative.** `UPPER(REGEXP_REPLACE(x, '[^A-Za-z0-9]', ''))` — shorter, and what the first draft used.

**Why.** On this database (Oracle 26ai Free, `MAX_STRING_SIZE=STANDARD`) the regex version cannot be a virtual column. It was found by testing each candidate on throwaway tables, after three guesses at the cause had each cost a full rebuild:

| Expression | Result |
|---|---|
| `REGEXP_REPLACE` in `VARCHAR2(200)` | ORA-12899 — size checked first, so the purity failure was hidden |
| `REGEXP_REPLACE`, any `CAST`, or no declared type | ORA-54002 — not a pure function |
| `REGEXP_REPLACE(x COLLATE BINARY, …)` | ORA-43929 — collation clauses need `MAX_STRING_SIZE=EXTENDED` |
| nested `TRANSLATE` + `CAST(… 200 BYTE)` | works, 200 bytes wide |

The likely reason (inferred, not documented): a regex character range like `[A-Za-z]` follows the session collation, so its result is not fixed by its input alone. `TRANSLATE` maps characters one-for-one and compares nothing, so it is pure. The `CAST` is needed because Oracle otherwise infers 4 bytes per source character; it cannot truncate, because only single-byte ASCII survives.

How it reads, inside out: the inner `TRANSLATE` deletes every allowed character, leaving only the junk characters present in `x`; the outer `TRANSLATE` deletes that junk from `x`. `'A'` is an anchor that maps to itself, so the replacement string is never empty (`TRANSLATE` with an empty target returns `NULL`).

`pkg_util.normalise` could still use the regex — PL/SQL has no purity rule — but it must match the virtual columns exactly. Under a linguistic `NLS_SORT` the regex and `TRANSLATE` could disagree, and a parsed token would silently stop joining to its ingredient. One expression in both places removes that risk. The cost is that the allowed-character literal is written twice: a virtual column cannot reference a package constant.
