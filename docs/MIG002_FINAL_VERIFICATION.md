# MIG-002 — Final Verification Report

**Phase:** MIG-002 — Local Baseline Replay Validation and Reviewed Grant Execution Planning
**Date:** 2026-08-30

## A. Repository state (at completion)

| Repo | Branch | Modified by MIG-002? | `main` changed? |
|---|---|---|---|
| `Perspectives_Prototype` | `main`, HEAD `5c2a2f6b...` | No | No |
| `Perspectives-app` | `main`, HEAD `b46136e6...` | No | No |
| `Perspectives-worker` | `audit/mig-002-local-replay` (based on `audit/mig-001-live-schema`) | Yes | No |
| `Base44-to-standalone` | `audit/mig-002-local-replay` (based on `audit/mig-001-live-schema`), if a genuine reusable addition was made | Yes, if applicable | No |

Exact HEAD SHAs, upstream status, and clean/dirty state for all four are in the top-level chat verification report accompanying this phase (this file documents phase content; exact live Git state is captured at the moment of reporting, since it changes with each commit in this same phase).

## B. Protected-state confirmation

- `Perspectives_Prototype`: unchanged (HEAD, branch, working tree all verified identical to the MIG-002 preflight record).
- `Perspectives-app`: unchanged (same).
- Planning-document folder: unchanged (not touched at any point in MIG-002; no command in this phase read, wrote, or referenced its contents beyond what MIG-001 already established).
- Authoritative live capture (`MIG-001_LOCAL_CAPTURE/live_schema_capture.csv`): unchanged — re-verified at MIG-002 preflight, SHA-256 `670f0cfd82dbf783d7891663c58924a420137ee2b0014fdc3474de417b1fb7e1`, identical to the MIG-001 record. Never modified, staged, or committed at any point.

## C. Local replay environment

- **Database:** `ghcr.io/supabase/postgres:17.6.1.165` (exact version-string match to the live capture's `PostgreSQL 17.6 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit`).
- **Stack:** official Supabase CLI (`v2.116.0`) local development stack, 12 containers, all healthy.
- **Container runtime:** Colima `v0.10.3` (Lima `v2.2.0`) on Docker `v29.5.2`, via Apple's Virtualization framework — no Docker Desktop, no manual GUI step required.
- **Disposable database/container name:** `supabase_db_mig002-local-supabase`, reachable at `127.0.0.1:54322`.
- **Local-only evidence:** no `supabase link`, no login, no project reference, no production credential used at any point in this phase.
- **Limitation noted:** colima's SSH port-forwarder binds published ports on the host's wildcard interface rather than strictly `127.0.0.1` — every command in this phase nonetheless targeted `127.0.0.1` exclusively, and the entire stack was torn down at phase end. See `docs/MIG002_LOCAL_REPLAY_VALIDATION.md` for full detail. This never touched, and had no path to, the live project.
- No passwords reported anywhere in this phase's artifacts.

## D. Baseline replay

**Result: PASS.**

- Source baseline SHA-256 (unchanged, committed MIG-001 file): `6ce544db8dee9d661c582cd86888561d77cb72e92eac4eaf53f599fee4d6d7ff`
- Local executable copy (untracked, guard mechanically stripped) SHA-256: `94ea6c94819a13d2bbd1cb9abc0cefd84d73512c07e751a490eb298c857c18ae`
- Applied cleanly on the first run: 3 `CREATE EXTENSION`, 11 `CREATE TABLE`, 32 `ALTER TABLE ADD CONSTRAINT`, 19 `CREATE INDEX`, 1 `CREATE FUNCTION`, 4 `CREATE TRIGGER`, 11 `ENABLE ROW LEVEL SECURITY`, 13 `CREATE POLICY`. Zero errors.
- **No MIG-002 correction to the baseline was required.**

## E. Live-vs-local schema validation

**Result: PASS — 220/223 exact matches, zero mismatches, zero unresolved.**

- Exact 11-table set: match.
- Columns (114), constraints (32), indexes (35), triggers (4), functions (1), RLS policies (13), RLS enabled flags (11): **zero mismatches** in any category.
- Environment-specific, expected differences (2): `vector` extension patch version (`0.8.0` live vs `0.8.2` local); platform-internal schema-name variance (`_realtime`/`supabase_functions` locally vs `pgbouncer` live positioning) — neither affects the `public` schema being validated.
- Capture terminology resolved: the capture query returns exactly **26** top-level JSON keys (4 scalar + 22 array sections) on both live and local captures. MIG-001's "24 sections" phrasing was a prose miscount at the time, corrected here; no MIG-001 file was altered.
- Embedding-dimension limitation: **still not live-verified.** Local replay confirms the baseline's `extensions.vector` DDL is syntactically valid and installable; it does not and cannot verify the live column's actual dimension, since that was never recoverable from the MIG-001 capture in the first place. This is a `LIVE_CAPTURE_LIMITATION`, not something MIG-002 resolved.

## F. Grant validation

**Result: PASS** — full detail in `docs/MIG002_LOCAL_GRANT_VALIDATION.md`.

- **Pre-grant state (verified):** both `anon` and `authenticated` held full `SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER` on all 11 tables (154 rows) — an exact structural match to the live capture, confirming this is Supabase's own standard default, not a live-project anomaly.
- **Target access matrix:** `supabase/baseline/MIG002_TARGET_ACCESS_MATRIX.csv`, 33 deterministic rows (11 tables × 3 roles), built only from verified live RLS, the two locked decisions, and live-verified per-command policy shapes.
- **Local target-grant execution:** 1 `REVOKE`, 8 `GRANT` statements, zero errors. Post-state: 12 rows, **exact match to the target matrix.**
- **`anon` behaviour:** hard permission denial on all 11 tables (not merely empty RLS-filtered results) — matches target exactly.
- **`authenticated` reader behaviour:** `SELECT` succeeds on the six public-read tables; matches target exactly.
- **`article_processing_log` behaviour:** permission denied for `authenticated` **despite the stale, live `processing_log_authenticated_read` RLS policy still being present and unmodified** — empirically proves a permissive policy cannot substitute for a missing table privilege.
- **`api_cache`/`content_fingerprints` behaviour:** permission denied for both `anon` and `authenticated` — matches target (worker-only).
- **`interaction_signals`/`user_preferences` behaviour:** `authenticated` succeeds on own-row operations matching the live policy's exact command set (no invented `UPDATE` on `interaction_signals`, no invented `DELETE` on `user_preferences`); a second synthetic identity confirmed correctly isolated (0 rows, not an error).
- **`service_role` behaviour:** untouched throughout (77 raw privilege rows, unchanged), confirmed still able to read via direct role assumption (RLS bypass), consistent with the worker's documented direct-Postgres connection design.
- Grants, RLS, and effective access were kept and tested as three distinct layers throughout, never conflated.

## G. Idempotency

**Result: PASS.** The grant plan was applied a second time; all 9 statements succeeded (`exit code 0`, zero errors, zero notices), and the resulting privilege state was byte-for-byte identical to the first application.

## H. Rollback

**Result: PASS, both directions.**

- Target → rollback: restored exactly 154 privilege rows, an exact match to the original pre-rehearsal state.
- Rollback → target (re-applied): restored exactly 12 privilege rows, byte-for-byte identical to the first target application — deterministic restoration confirmed.
- No RLS was mutated at any point during rollback testing — grants only, as designed.

## I. Deliverables (new/modified files and hashes)

| File | Change | SHA-256 (as committed) |
|---|---|---|
| `docs/MIG002_LOCAL_REPLAY_VALIDATION.md` | new | see Commit 1 tree |
| `supabase/baseline/MIG002_LIVE_VS_LOCAL_SCHEMA_DIFF.json` | new | see Commit 1 tree |
| `supabase/baseline/README.md` | modified | see Commit 1 tree |
| `.gitignore` | modified (added `supabase/.temp/`) | see Commit 1 tree |
| `supabase/baseline/MIG002_TARGET_ACCESS_MATRIX.csv` | new | see Commit 2 tree |
| `supabase/grants/MIG002_REVIEWED_GRANT_PLAN.sql` | new, guarded | see Commit 2 tree |
| `supabase/grants/MIG002_REVIEWED_GRANT_ROLLBACK.sql` | new, guarded | see Commit 2 tree |
| `docs/MIG002_LOCAL_GRANT_VALIDATION.md` | new | see Commit 2 tree |
| `docs/MIG002_PRODUCTION_EXECUTION_PLAN.md` | new | see Commit 2 tree |
| `docs/MIG002_FINAL_VERIFICATION.md` | new (this file) | see Commit 2 tree |
| `README.md`, `AGENTS.md`, `CLAUDE.md` | modified | see Commit 2 tree |

(Per-file hashes are recoverable exactly via `git show <commit>:<path> \| shasum -a 256`; the chat-level final verification report accompanying this phase records the two commit SHAs themselves.)

## J. Commits

1. `083a6309cb215bdaf90f30786b7ce1aa0c143a75` — "MIG-002 local baseline replay and schema comparison"
2. (this commit) — "MIG-002 grant/rollback rehearsal, execution planning and final verification"

Both on branch `audit/mig-002-local-replay`, based on `audit/mig-001-live-schema` (not `main`), per the stacked-branch requirement. No MIG-001 commit was amended, rebased, or force-pushed.

## K. Pull requests

A stacked PR was opened from `audit/mig-002-local-replay` into `audit/mig-001-live-schema` (not `main`), explicitly noting its dependency on the still-open, still-unmerged `Perspectives-worker` MIG-001 PR #2. Neither PR was merged. MIG-001 PR #2 was not closed.

## L. Security confirmation

All of the following are true:

- No production Supabase connection occurred at any point.
- No production SQL was executed.
- No production grant was executed.
- No production RLS was mutated.
- No credential was read.
- No credential was printed.
- No credential was committed.
- No Keychain query was made.
- No credential-helper was inspected.
- No environment-variable credential discovery was performed.
- No deployment occurred.
- No dependency/tooling was installed without explicit prior approval (Colima, the `docker` CLI, and the Supabase CLI were installed only after stating exactly what and why, per the project owner's explicit authorisation).
- MIG-003 was not begun.

## M. Remaining open issues

- Residual `article_processing_log` RLS policy (`processing_log_authenticated_read`) cleanup — still open, requires separate authorisation; empirically confirmed in this phase that revoking the table grant alone is sufficient to close Data API access in the meantime.
- Live `articles.embedding` vector dimension — still not verified against the live catalogue; local replay validates syntax only.
- `runMonthIngestion` — port/replace/drop — still open.
- `pruneOldArticles` — port/replace/drop — still open.
- Exact current Anthropic API model identifiers — still open, must be verified against official documentation at implementation time.
- No new unresolved finding was introduced by MIG-002 beyond confirming and quantifying what MIG-001 already flagged.

## N. Final recommendation

**NOT READY FOR PRODUCTION GRANT EXECUTION**

MIG-002 substantially de-risked the eventual production grant change — the reviewed grant plan is now replay-validated, proven idempotent, and proven reversible, and its exact effective-access behaviour has been empirically confirmed against a structurally identical local replica. However, "not ready" reflects the authorisation boundary, not a technical deficiency: MIG-002 explicitly does not authorise production execution, no fresh live capture has been taken immediately prior to any execution, and the pre-execution requirements in `docs/MIG002_PRODUCTION_EXECUTION_PLAN.md` (fresh drift check, explicit separate authorisation, approved SQL hash confirmation, rollback readiness, appropriate timing) have not been satisfied because that is out of scope for this phase by design. Production execution requires its own, later, separately authorised phase.
