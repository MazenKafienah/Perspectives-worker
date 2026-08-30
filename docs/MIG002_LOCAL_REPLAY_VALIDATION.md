# MIG-002 — Local Baseline Replay Validation

**Phase:** MIG-002 — Local Baseline Replay Validation and Reviewed Grant Execution Planning
**Date:** 2026-08-30
**Security boundary:** No connection to the live Supabase project occurred at any point in this phase. All SQL executed in this document ran only against a disposable local Supabase development stack (Docker containers on loopback, torn down at the end of the phase). No production credential was requested, read, or used.

## Capture-key precision correction

The MIG-001 capture query returns exactly **26** top-level JSON keys: 4 scalar metadata fields (`capture_format_version`, `query_executed_at`, `postgres_version`, `public_table_count`) plus 22 array-valued inventory sections. MIG-001's own prose described this as "24 expected top-level sections" in places — that was an arithmetic slip in the summary text at the time, not a data or structural discrepancy. The capture file and its JSON were always complete and correct at 26 keys; this correction is documentation-only and does not modify any MIG-001 committed file.

## Local environment

- **Container runtime:** Colima (`v0.10.3`, Lima `v2.2.0`) running Docker (`v29.5.2` server) via Apple's Virtualization framework — chosen over Docker Desktop specifically to avoid a manual GUI launch step.
- **Stack:** official Supabase CLI (`v2.116.0`) local development stack (`supabase init` + `supabase start`), all 12 services healthy: `db`, `auth` (GoTrue), `rest` (PostgREST), `kong`, `studio`, `realtime`, `storage`, `storage-api`, `pg_meta`, `edge_runtime`, `inbucket`, `analytics`, `vector`.
- **Database:** `ghcr.io/supabase/postgres:17.6.1.165`, container `supabase_db_mig002-local-supabase`.
- **Local-only evidence:** Postgres reachable at `127.0.0.1:54322`; API gateway at `127.0.0.1:54321`; no `supabase link`, no login, no project reference, no production credential used at any point. (One residual note: colima's SSH-based port forwarder binds the published ports on the host's wildcard interface rather than strictly `127.0.0.1`, per its default `ssh` port-forwarder implementation — every command in this phase nonetheless targeted `127.0.0.1` exclusively, and the entire stack was destroyed at the end of the phase. Flagged here for transparency rather than treated as a production-adjacent risk, since this is a disposable local sandbox with zero path to the live project.)
- **Extensions confirmed pre-installed:** `pg_stat_statements 1.11`, `pgcrypto 1.3`, `plpgsql 1.0`, `supabase_vault 0.3.1`, `uuid-ossp 1.1` — identical to the live capture. `vector` was *available* (`0.8.2`) but not yet installed, matching the live project's state before any baseline was applied.
- **Roles confirmed present:** `anon`, `authenticated`, `service_role`, `postgres`.
- **Auth helper functions confirmed present:** `auth.uid()`, `auth.role()`, both reading from the `request.jwt.claims` session setting exactly as PostgREST would set it — allowing faithful effective-access testing (see `MIG002_LOCAL_GRANT_VALIDATION.md`).
- **Limitations:** none material. The environment reproduces every feature this validation needed (RLS, the three Supabase roles, `auth.*` helper functions, pgvector availability, Postgres 17).

## Baseline replay result: **PASS**

- **Source (committed, guarded) file:** `supabase/baseline/20260821_EXISTING_STATE_BASELINE.sql`, SHA-256 `6ce544db8dee9d661c582cd86888561d77cb72e92eac4eaf53f599fee4d6d7ff` (unchanged from MIG-001; verified again at the start of this phase).
- **Local executable copy:** generated mechanically by stripping the exact `DO $guard$ ... $guard$;` block via a regex substitution — the only textual change made. Generated file SHA-256 `94ea6c94819a13d2bbd1cb9abc0cefd84d73512c07e751a490eb298c857c18ae`. This copy is untracked, lives only under a session-scratch directory outside every Git repository, and was never staged or committed.
- **Result:** applied with `psql -v ON_ERROR_STOP=1` against a completely empty `public` schema. Every statement succeeded on the first run: 3 `CREATE EXTENSION`, 11 `CREATE TABLE`, 32 `ALTER TABLE ... ADD CONSTRAINT` (11 primary key, 5 unique, 12 foreign key, 4 check), 19 `CREATE INDEX`, 1 `CREATE FUNCTION`, 4 `CREATE TRIGGER`, 11 `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, 13 `CREATE POLICY`. Zero errors, zero warnings.
- **No correction was required.** The baseline as committed in MIG-001 replayed cleanly and exactly as written.
- A second, accidental re-run of the same file against the now-populated database failed deterministically with `relation "specialties" already exists` — this is expected, correct Postgres behaviour for a one-time schema-creation script without `IF NOT EXISTS` guards, not a defect. It is noted here only for a complete, honest record of every command executed.

## Live-vs-local schema comparison: **PASS** (220/223 exact matches)

Full machine-readable detail in `supabase/baseline/MIG002_LIVE_VS_LOCAL_SCHEMA_DIFF.json`. Summary by category — all compared with full structural/semantic equality (not byte-for-byte where environment-specific values are expected to differ):

| Category | Compared | Result |
|---|---|---|
| Public table set (11 tables) | names | EXACT_MATCH |
| Postgres version string | full `version()` output | **EXACT_MATCH** — `PostgreSQL 17.6 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit`, identical on both sides |
| Columns (114) | type, nullability, default, identity, generated-column expression | 0 mismatches |
| Constraints (32) | type + full definition | 0 mismatches |
| Indexes (35) | full definition | 0 mismatches |
| Triggers (4) | full definition + enabled state | 0 mismatches |
| Functions (1) | full definition, volatility, security-definer | 0 mismatches |
| RLS policies (13) | permissive/command/roles/using/with-check | 0 mismatches |
| RLS enabled flags (11 tables) | enabled + forced | 0 mismatches |
| Generated columns (1) | expression | EXACT_MATCH |
| Extensions | name/version | 5/6 exact; `vector` `0.8.0` (live) vs `0.8.2` (local) — **EXPECTED_LOCAL_ENVIRONMENT_DIFFERENCE** |
| Schemas present | set | **EXPECTED_LOCAL_ENVIRONMENT_DIFFERENCE** — local stack additionally provisions `_realtime` and `supabase_functions`; live additionally shows `pgbouncer` in the same position either way; harmless platform-schema variance, not a `public`-schema concern |
| Pre-rehearsal `anon`/`authenticated` table grants | full privilege set | **EXACT_MATCH** — see below, a significant corroborating finding |

**No `BASELINE_MISMATCH` or `UNRESOLVED` classification occurred anywhere in the comparison.**

### Corroborating finding: the local stack defaults to the same over-permissive grants as the live project

Before any grant rehearsal was applied, the freshly-provisioned local database already granted full `SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER` to both `anon` and `authenticated` on every one of the 11 tables — an exact structural match to what MIG-001 found live. This confirms the live project's over-permissive grant state is Supabase's own standard default behaviour (inherited via default privileges on the `postgres` role), not a one-off misconfiguration specific to that project. It also means this local environment is an unusually faithful testbed for rehearsing exactly the REVOKE-then-GRANT transition the reviewed grant plan performs — see `MIG002_LOCAL_GRANT_VALIDATION.md`.

## Embedding dimension: still not live-verified

`articles.embedding` replayed successfully as `extensions.vector` with **no dimension parameter**, because none was recoverable from the live capture (`information_schema.columns` does not expose a vector column's typmod). The local replay's success validates that this baseline's *syntax* is correct and that the `vector` extension type is usable in this position — it does **not** verify, and must not be read as verifying, that the live column's actual dimension is 1536 or any other value. That remains an open item (see `OPEN_DECISIONS.md` in the toolkit repository).
