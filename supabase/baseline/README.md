# MIG-001 Baseline — What's Here and What It Isn't

This directory holds a **captured snapshot of the already-live PERSPECTIVES Supabase schema**, produced during MIG-001 (2026-08-27/28), plus the normalized inventory it was derived from.

## Files

- **`20260821_LIVE_SCHEMA_INVENTORY.json`** — normalized, deterministic JSON inventory of the live `public` schema (tables, columns, constraints, indexes, functions, triggers, RLS policies, grants). Derived only from the verified capture; records the capture's SHA-256 and provenance.
- **`20260821_EXISTING_STATE_BASELINE.sql`** — a DDL reconstruction of the same live schema, generated mechanically from the inventory. Carries an execution guard that raises an exception if run.

## What this is

Evidence. A faithful, best-effort reconstruction of what the live database looked like at capture time, built without ever connecting to it directly — every fact here traces back to one manually-run, read-only SQL Editor query and the file the project owner exported from its result.

## What this is not

- **Not a migration to run against the live project.** That project already has this schema.
- **Not replay-tested.** Nobody has run `20260821_EXISTING_STATE_BASELINE.sql` against any database, local or otherwise, at any point during MIG-001. Its correctness is inferred from mechanical, per-object catalogue definitions (`pg_get_constraintdef`, `pg_get_functiondef`, `pg_get_triggerdef`, `pg_indexes.indexdef`, and the captured RLS policy fields), not proven by execution. Local replay validation is a separate, later, separately authorised phase.
- **Not proof of any live mutation.** MIG-001 made zero Supabase connections. Nothing in this directory changed the live database.
- **Not the canonical location for future migrations.** Once this baseline is replay-validated (a later phase), the project's actual forward migrations belong in `supabase/migrations/`, not here.

## Known limitation

`articles.embedding` is captured as `extensions.vector` with an **unspecified dimension** — `information_schema.columns` doesn't expose a vector column's typmod the way it exposes `character_maximum_length` for varchar. The planning documents assume 1536 (OpenAI `text-embedding-3-small`), but that has not been confirmed against the live catalogue and is not asserted as fact anywhere in this baseline. See the SQL file's header comment for how to verify it.

## Related reading

- `docs/MIG001_LIVE_SCHEMA_RECONCILIATION_REPORT.md` — the full reconciliation against all three planning documents, including every resolved and unresolved conflict.
- `supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql` — the corresponding least-privilege Data API grant proposal (kept separate from schema shape deliberately).
- `supabase/audit/` — the original read-only capture query and instructions.
