---
description: Adversarially review uncommitted PL/SQL changes
---

Review the uncommitted changes in this repo as a senior Oracle developer
would, before they go anywhere near a commit.

Run `git diff` and `git status` first. Review only what actually changed.

Check, in order of how much it would cost to get wrong:

**Correctness**
- Will it compile? Will it run against the real schema?
- NULL handling — especially in comparisons, aggregates and string building.
- Implicit conversions, particularly dates and numbers from VARCHAR2 staging.
- Transaction boundaries. Is a partial result possible? Is there a COMMIT
  somewhere it does not belong (inside a loop, inside a function)?
- Mutating-table risk on any trigger.

**Robustness**
- Is `WHEN OTHERS` used anywhere without re-raising? That is a defect.
- Are errors raised through `pkg_util.raise_error` with a registered code?
- Would a bad source row kill the whole batch, or be quarantined?

**Performance**
- Row-by-row processing where a set operation would do.
- A function called per row that queries a table.
- Anything that will not scale past the sample data size.
- Missing index for a predicate this code introduces.

**Repo conventions**
- Check against CLAUDE.md. Naming, style, pure-function rule, rules-in-tables
  rule.

Report findings most serious first. For each: the file and line, what is
wrong, and what would actually go wrong at runtime. Be specific — "consider
adding error handling" is not a finding.

If you find nothing serious, say so plainly rather than inventing something.

Do not fix anything. This command only reports.
