# Supabase migrations

Shared project: `dbkqemjfxtksjxrwrclf` (used by `ipilgo-tourist`, `ipilgo-owner`, `ipilgo-admin`).

`migrations/20260716000000_baseline_schema.sql` is a **snapshot**, not a replay log. It was
reconstructed on 2026-09-08 by reading the already-live database (tables, enums, functions,
triggers, RLS policies, storage policies) directly, because none of that logic previously
existed as a tracked file anywhere in this repo. Nothing in the live database was changed to
produce it.

Going forward: any schema change (new column, new policy, new trigger, etc.) should be written
as its own new migration file in this folder, applied through Supabase, and committed — instead
of being made only through the dashboard/SQL editor and left untracked.
