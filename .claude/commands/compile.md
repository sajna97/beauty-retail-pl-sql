---
description: Recompile the schema and fix any invalid objects
---

Run `./scripts/compile.sh`.

If anything is invalid:

1. Read the reported errors carefully — PLS line numbers are relative to the
   start of the package body, not the file.
2. Fix the cause, not the symptom. If a package will not compile because a
   table column is missing, say so and ask before changing DDL.
3. Recompile and repeat until clean.
4. Report what was wrong in one or two sentences. Do not paste the whole
   error list back at me.

Do not commit anything as part of this command.
