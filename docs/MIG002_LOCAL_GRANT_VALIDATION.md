# MIG-002 — Local Grant Rehearsal and Effective-Access Validation

**Phase:** MIG-002. All SQL in this document executed only against the disposable local Supabase stack described in `MIG002_LOCAL_REPLAY_VALIDATION.md`. No production connection occurred.

## Layer separation

Three distinct layers were tested independently throughout, as required:

1. **Table/schema privilege** (`information_schema.table_privileges` / `has_table_privilege`) — can the role attempt the operation at all.
2. **RLS policy** (`pg_policies`) — which rows, if any, the role can see or affect once the operation is attempted.
3. **Effective access** — the actual, observed result of running a query as that role, which depends on both of the above together.

## Stage 7 — Verified pre-grant (replayed) privilege state

Immediately after the baseline replay (`MIG002_LOCAL_REPLAY_VALIDATION.md`), before any grant change:

- `anon` and `authenticated`: full `SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` on **all 11 tables** — 154 rows total (`11 × 2 × 7`). Confirmed identical in shape to the live capture (see the corroborating finding in the replay report).
- `service_role`: full privileges on all 11 tables — 77 rows (`11 × 7`) — Supabase's standard default, left untouched throughout this entire phase.

## Stage 8 — Authoritative target access matrix

See `supabase/baseline/MIG002_TARGET_ACCESS_MATRIX.csv` for the full, deterministic 33-row matrix (11 tables × 3 roles). Built only from: verified live RLS policies (MIG-001), the two locked user decisions, and the live-verified per-command policy shapes for `interaction_signals`/`user_preferences` (no invented privileges — e.g. `interaction_signals` has no live `UPDATE` policy, so `UPDATE` is not granted; `user_preferences` has no live `DELETE` policy, so `DELETE` is not granted).

Target summary:

| Table | anon | authenticated |
|---|---|---|
| `articles`, `authors`, `journals`, `specialties`, `subtopics`, `article_specialties` | none | `SELECT` |
| `interaction_signals` | none | `SELECT, INSERT, DELETE` |
| `user_preferences` | none | `SELECT, INSERT, UPDATE` |
| `api_cache`, `content_fingerprints`, `article_processing_log` | none | none |

## Stage 9 — Local grant application result

Applied `MIG002_REVIEWED_GRANT_PLAN.sql` (local executable copy, guard mechanically stripped; source SHA-256 `c1fb20bac47386f8e4402f66718db556f2f9a43100e6b6c92fe332e329088303`) against the disposable database. One `REVOKE ALL ... FROM anon, authenticated`, then 8 precise `GRANT` statements. **All 9 statements succeeded, zero errors.**

Post-state: exactly 12 privilege rows for `anon`/`authenticated` combined (`0` for `anon`; `6×SELECT + 3 + 3 = 12` for `authenticated`). **Matches the target matrix exactly — zero mismatches.**

## Stage 10 — Effective access testing

Tested using real PostgREST-equivalent session context: `SET LOCAL request.jwt.claims = '{"role":"...","sub":"..."}'; SET LOCAL ROLE ...;` inside explicit transactions (Postgres requires `SET LOCAL` inside a transaction block to take effect — an early attempt outside a transaction silently no-opped and was caught and corrected before any result was trusted). Synthetic fixture rows only (two synthetic `auth.users` rows, one row each in `specialties`/`journals`/`authors`/`articles`/`article_processing_log`/`interaction_signals`/`user_preferences`); all deleted at the end of the phase.

### `anon`, post-target-grant — every one of 11 tables: **DENIED**

```
articles: DENIED (permission denied)          authors: DENIED
journals: DENIED                              specialties: DENIED
subtopics: DENIED                             article_specialties: DENIED
article_processing_log: DENIED                api_cache: DENIED
content_fingerprints: DENIED                  interaction_signals: DENIED
user_preferences: DENIED
```

Matches target exactly: V1 requires authenticated sign-in for everything, and `anon` now gets a hard permission error at the grant layer (not merely an empty RLS-filtered result) on every table.

### `authenticated`, post-target-grant

```
articles: OK              authors: OK              journals: OK
specialties: OK           subtopics: OK            article_specialties: OK
article_processing_log: DENIED
api_cache: DENIED
content_fingerprints: DENIED
interaction_signals: OK (own row only, confirmed 0 rows for a second synthetic user)
user_preferences: OK (own row only, confirmed 0 rows for a second synthetic user)
```

**Exact match to the target matrix on every one of the 11 tables.** Per-user isolation on `interaction_signals`/`user_preferences` was independently confirmed with a second synthetic user identity that owns no rows: both returned `0`, not an error — RLS correctly filtering rather than denying, since the grant permits the operation but the policy restricts the rows.

### `service_role`

Confirmed 77 raw privilege rows unchanged throughout, and confirmed by direct query (`SET LOCAL ROLE service_role`) that it can still read `articles` and `article_processing_log` (RLS bypass, Supabase's standard role attribute) — untouched by any step in this phase, consistent with the worker's documented direct-Postgres connection path.

## Special test — `article_processing_log`: permissive RLS policy alone does not grant access

This is the specific empirical test the MIG-002 authorisation required. The replayed baseline includes the live, stale `processing_log_authenticated_read` policy verbatim (`FOR SELECT ... USING (auth.role() = 'authenticated')`), because the baseline faithfully reproduces live state including known technical debt.

- **Before the grant rehearsal** (broad legacy grant still present): `authenticated` → `article_processing_log` → **1 row visible** (the synthetic fixture row). The stale policy, combined with the still-present table grant, does permit read access — matching exactly what MIG-001 found live.
- **After applying the reviewed grant plan** (table grant revoked, no grant added back for this table, policy left completely untouched): `authenticated` → `article_processing_log` → `ERROR: permission denied for table article_processing_log` — **HINT: Grant the required privileges to the current role with: GRANT SELECT ON public.article_processing_log TO authenticated.**
- The policy was independently confirmed still present after the grant change (`SELECT policyname FROM pg_policies WHERE tablename='article_processing_log'` → `processing_log_authenticated_read`).

**This empirically proves the distinction the authorisation asked for:** a permissive RLS policy is necessary but not sufficient for Data API access — the underlying table privilege is checked first, and revoking it closes access completely regardless of what any policy would otherwise permit. This does **not** mean the stale policy should remain forever; it remains documented technical debt (see `OPEN_DECISIONS.md`), and its removal requires its own separate authorisation. It was not touched during MIG-002.

## Stage 11 — Idempotency: **PASS**

Applied the identical local grant-plan file a second time. All 9 statements re-executed with `exit code 0`, zero errors, zero notices. The resulting privilege state (12 rows for `anon`/`authenticated`) was byte-for-byte identical to the first application's result.

## Stage 12 — Rollback rehearsal: **PASS** (both directions)

1. Applied `MIG002_REVIEWED_GRANT_ROLLBACK.sql` (local executable copy). Result: exactly 154 privilege rows restored (`11 × 2 × 7`) — an exact match to the original pre-rehearsal broad-grant state.
2. Re-applied the target grant plan afterward. Result: exactly 12 privilege rows, byte-for-byte identical to the very first target application — **deterministic restoration confirmed.**

No RLS was ever mutated during rollback testing — only table-level grants, exactly as the rollback file's own header documents. The rollback file's warning about `article_processing_log` (that rolling back would immediately re-expose it via the still-present stale policy) is consistent with, and directly explained by, the special test above.

## Overall grant validation result: **PASS**

Every stage (7 through 12) passed with zero unexplained deviation from the authoritative target matrix.
