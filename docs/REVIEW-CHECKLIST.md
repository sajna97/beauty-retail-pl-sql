# Review checklist

You chose to review every line. This is what "review" has to mean for that to
be worth anything.

Print this, or keep it open. Run it before every commit.

---

## The one question that matters

> **If an interviewer pointed at any line of this and asked "why is that
> there?", could I answer without looking it up?**

If no — that line is not ready to commit. Ask for `/explain`, or rewrite it
yourself until it is yours.

---

## Per-change checklist

**Understand it**
- [ ] I can state what this code does in two sentences, without reading it again.
- [ ] I know why each non-obvious construct is there.
- [ ] I could write the next similar procedure without help.

**Check it**
- [ ] It compiles (`/compile`).
- [ ] I ran it against real data and looked at the output myself — not just at
      Claude's summary of the output.
- [ ] I tried at least one input designed to break it.
- [ ] Row counts are what I expected. If they surprised me, I found out why.

**Question it**
- [ ] Is there a simpler way? I asked.
- [ ] Is there anything here I would not have thought of? Those are the lines
      to study, not skim.
- [ ] Does it follow the conventions in CLAUDE.md, or did it quietly drift?

**Own it**
- [ ] The commit message is mine, and describes what I decided, not what was
      generated.

---

## Things to deliberately write yourself

Let Claude do the DDL, the loaders, the boilerplate, the test data, the docs.
Write these by hand, even slowly:

1. **`pkg_ingredient` — the INCI parser.** This is the centrepiece and the
   thing you will be asked about. Writing it yourself is the single highest
   value hour in the project.
2. **One bulk-processing routine**, end to end, with `BULK COLLECT` and
   `FORALL ... SAVE EXCEPTIONS`. You need this in your fingers.
3. **The compound trigger.** Small, tricky, extremely interviewable.
4. **One genuinely hard query** — the cohort analysis or the shade-demand
   curve. Analytic functions come up in every Oracle interview.

For each, a good pattern: ask Claude to explain the approach and write the
package *spec*, then write the body yourself, then ask for `/review`.

---

## Red flags in your own process

- You committed something you did not read. Stop; go back and read it.
- You do not know why a query is fast. Find out before it matters.
- Three sessions have passed since you wrote any PL/SQL yourself.
- You are asking Claude to fix an error without understanding the error.

None of these are moral failures — they are just the failure mode that turns
a portfolio project into something you cannot talk about. Catching them early
costs nothing.
