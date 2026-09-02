# MIG-001 Baseline — What's Here and What It Isn't

This directory holds a **captured snapshot of the already-live PERSPECTIVES Supabase schema**, produced during MIG-001 (2026-08-27/28), plus the normalized inventory it was derived from.

## Files

- **`20260821_LIVE_SCHEMA_INVENTORY.json`** — normalized, deterministic JSON inventory of the live `public` schema (tables, columns, constraints, indexes, functions, triggers, RLS policies, grants). Derived only from the verified capture; records the capture's SHA-256 and provenance.
- **`20260821_EXISTING_STATE_BASELINE.sql`** — a DDL reconstruction of the same live schema, generated mechanically from the inventory. Carries an execution guard that raises an exception if run.

## What this is

Evidence. A faithful, best-effort reconstruction of what the live database looked like at capture time, built without ever connecting to it directly — every fact here traces back to one manually-run, read-only SQL Editor query and the file the project owner exported from its result.

## What this is not

- **Not a migration to run against the live project.** That project already has this schema.
- **Not proof of any live mutation.** MIG-001 made zero Supabase connections. Nothing in this directory changed the live database.
- **Not the canonical location for future migrations.** The project's actual forward migrations belong in `supabase/migrations/`, not here — even now that the baseline is replay-validated (see below).

## MIG-002 update: now replay-validated

MIG-002 (2026-08-30) replayed `20260821_EXISTING_STATE_BASELINE.sql` against a disposable local Supabase development stack — the committed file itself was never modified; a mechanically-guard-stripped, untracked local copy was used, and only that copy was executed. **Result: full success, zero errors, zero corrections needed.** A structural comparison against the original live capture found 220/223 categories an exact match, with the only differences being expected environment noise (a minor `vector` extension patch-version difference; a couple of platform-internal schema names). See `docs/MIG002_LOCAL_REPLAY_VALIDATION.md` for the complete report and `MIG002_LIVE_VS_LOCAL_SCHEMA_DIFF.json` in this directory for the machine-readable detail.

**This still does not mean the baseline has been applied to production**, and it does not resolve the embedding-dimension limitation below (local replay validates DDL syntax, not the live column's actual dimension).

## Known limitation

`articles.embedding` is captured as `extensions.vector` with an **unspecified dimension** — `information_schema.columns` doesn't expose a vector column's typmod the way it exposes `character_maximum_length` for varchar. The planning documents assume 1536 (OpenAI `text-embedding-3-small`), but that has not been confirmed against the live catalogue and is not asserted as fact anywhere in this baseline or in the MIG-002 replay. See the SQL file's header comment for how to verify it.

## Related reading

- `docs/MIG001_LIVE_SCHEMA_RECONCILIATION_REPORT.md` — the full MIG-001 reconciliation against all three planning documents.
- `docs/MIG002_LOCAL_REPLAY_VALIDATION.md` — the replay validation report.
- `docs/MIG002_LOCAL_GRANT_VALIDATION.md` — the grant rehearsal, effective-access testing, idempotency, and rollback report.
- `docs/MIG002_PRODUCTION_EXECUTION_PLAN.md` — the review-only plan for a future, separately authorised production execution phase.
- `MIG002_TARGET_ACCESS_MATRIX.csv` (this directory) — the authoritative, deterministic 11-table × 3-role target access matrix.
- `supabase/grants/` — the MIG-001 proposed grants, the MIG-002 reviewed (and locally rehearsed) grant plan, and its rollback.
- `supabase/audit/` — the original read-only capture query and instructions.
