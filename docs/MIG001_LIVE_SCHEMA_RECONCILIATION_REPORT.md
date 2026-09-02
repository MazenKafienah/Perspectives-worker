# MIG-001 — Live Supabase Schema Reconciliation Report

**Phase:** MIG-001 — Live Supabase Schema Baseline and Data API Grant Reconciliation
**Date:** 2026-08-27/28
**Author:** Claude Code, working from a manually-exported, read-only catalogue capture. Claude Code made no direct connection to Supabase at any point in this phase.

## 1. Executive summary

The live PERSPECTIVES Supabase project exists and its 11-table `public` schema shape matches the **handover document's** schema, not the master document's — resolving the long-standing "which schema is canonical" question (conflict 7 in the prior session handoff) decisively in the handover's favour. Row Level Security is enabled on all 11 tables. However, the underlying **table-level grants are far broader than intended** on every table — a legacy Supabase auto-expose default, not the explicit least-privilege model the runbook assumes — and RLS is currently the only thing preventing that from being exploitable. Two decisions that were open before this phase have now been resolved by the project owner using this live evidence:

- `article_processing_log` is **worker-only** (no anon/authenticated Data API access). This requires revoking its current grant and, in a later phase, dropping a stale RLS policy that predates the decision.
- V1 is **authenticated-only** for all reader-facing content (`articles`, `authors`, `journals`, `specialties`, `subtopics`, `article_specialties`). `anon` gets no read access at all. This matches the RLS policies already live on those six tables.

A reproducible baseline (`supabase/baseline/`) and a corrected, least-privilege grant proposal (`supabase/grants/`) have been produced from the capture. Neither has been executed. No live mutation occurred at any point in this phase.

## 2. Capture method and security boundary

Claude Code authored a single, read-only, catalogue-only SQL query (`supabase/audit/MIG001_READ_ONLY_SCHEMA_CAPTURE.sql`) consisting entirely of `WITH`/`SELECT` over `pg_catalog` and `information_schema`. The project owner ran it manually in the Supabase SQL Editor, exported the single-row result, and saved it locally outside every Git repository. Claude Code read that exported file from local disk and never connected to Supabase, the Supabase CLI, the Management API, the Data API, PostgREST, GraphQL, or `psql` at any point. No credential of any kind was supplied to, requested by, or read by Claude Code during this phase.

## 3. Capture checksum

- **File:** `MIG-001_LOCAL_CAPTURE/live_schema_capture.csv` (outside all Git repositories)
- **SHA-256:** `670f0cfd82dbf783d7891663c58924a420137ee2b0014fdc3474de417b1fb7e1`
- **Capture format version:** `1.0`
- **Query executed at (as reported by the database):** `2026-08-27T21:12:04.332485+00:00`
- **Postgres version:** `PostgreSQL 17.6 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit`

A bounded secret-pattern scan was run across every function definition, function configuration, column default, table comment, RLS policy expression, view/materialized-view definition, trigger definition, constraint definition, and index definition in the capture. **Zero matches.**

## 4. Verified object inventory

| Object type | Count |
|---|---|
| Public tables | 11 |
| Columns | 114 |
| Generated columns | 1 (`articles.fts`) |
| Constraints | 32 (11 primary key, 5 unique, 12 foreign key, 4 check, 0 exclusion) |
| Indexes | 35 (16 constraint-backing, 19 standalone) |
| Extensions | 6 (`pg_stat_statements`, `pgcrypto`, `plpgsql`, `supabase_vault`, `uuid-ossp`, `vector`) |
| Functions | 1 (`set_updated_at`) |
| Triggers | 4 (all `BEFORE UPDATE ... EXECUTE FUNCTION set_updated_at()`) |
| Views / materialized views | 0 / 0 |
| Sequences | 0 (all surrogate keys use `gen_random_uuid()`, not `SERIAL`) |
| Enums / domains | 0 / 0 |
| RLS policies | 13 |
| Publications | 0 tables published |

## 5. Exact table list

**The user-confirmed 11-table list is exact.** No addition, no omission:

`api_cache`, `article_processing_log`, `article_specialties`, `articles`, `authors`, `content_fingerprints`, `interaction_signals`, `journals`, `specialties`, `subtopics`, `user_preferences`.

## 6. Schema comparison against the three canonical documents

### 6.1 Overall schema shape (conflict 7, session handoff register)

- **Live fact:** 11 tables matching the list above; standalone `specialties` and `content_fingerprints` tables exist; no `article_authors` or `article_tags` join table exists anywhere in `public`.
- **Handover statement:** 11 tables, standalone `specialties` and `content_fingerprints`, no author/tag join tables.
- **Master document statement:** a different schema — `article_authors` and `article_tags` join tables, no standalone `specialties` or `content_fingerprints`, SimHash as a `content_fingerprint` column on `articles`.
- **Runbook statement:** inherits the master document's table set in its Appendix A grant script, which references `article_authors` and `article_tags` (neither exists live) and never mentions `specialties` or `content_fingerprints` (both exist live and need grants).
- **Operational consequence:** running the runbook's Appendix A verbatim against the live database would fail on missing tables and would leave `specialties` and `content_fingerprints` completely unaddressed.
- **Reconciliation:** **resolved.** The live database matches the handover. The runbook's Appendix A is confirmed incompatible and was not used; `supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql` was built from the verified live table set instead.

### 6.2 Author relationships (new finding — not anticipated by either document's join-table framing)

- **Live fact:** `articles` has a single `author_id uuid` foreign key directly to `authors(id)` — no many-to-many join table at all. A `co_authors jsonb` column on `articles` appears to hold any additional authors as unstructured JSON rather than normalized rows.
- **Master document statement:** assumes an `article_authors` join table with an `author_position` column, implying many-to-many normalized authorship.
- **Handover statement:** does not describe a join table at all; silent on this point.
- **Operational consequence:** the pipeline design must account for a single-primary-author-plus-JSON-co-authors model, not a normalized many-to-many one, if Phase 2 worker code is to match what's actually live.
- **Reconciliation:** this is a **new fact**, not previously flagged as a conflict. Recorded here and in `OPEN_DECISIONS.md` as a point future worker design must account for — not something MIG-001 resolves on its own, since it's a data-model observation rather than a yes/no decision.

### 6.3 Subtopic/tag relationships (conflict 8 area, extended)

- **Live fact:** `subtopics` is a standalone taxonomy table (as both documents expect), but articles relate to subtopics and tags via plain `text[]` array columns (`articles.subtopic_slugs`, `articles.tags`, `articles.studies_referenced`) — not via any join table.
- **Master document statement:** assumes an `article_tags` join table.
- **Handover statement:** does not describe the tag-relationship mechanism at the column level.
- **Reconciliation:** live matches neither document's exact mechanism precisely; the master document's join-table assumption is confirmed wrong, and the handover is silent rather than wrong. No product decision is required here — it's a data-model fact for future worker code to match.

### 6.4 SimHash storage (item 6, live-schema verification checklist)

- **Live fact:** SimHash is stored **only** in the standalone `content_fingerprints` table (`fingerprint bigint PRIMARY KEY`, `article_id uuid UNIQUE` with `ON DELETE CASCADE`, `computed_at`). `articles` has **no** `content_fingerprint` column.
- **Master document statement:** SimHash as a `content_fingerprint BYTEA` column directly on `articles`, no standalone table.
- **Handover statement:** matches live — standalone `content_fingerprints` table, no column on `articles`.
- **Reconciliation:** resolved in the handover's favour, consistent with 6.1.

### 6.5 Prototype audit (conflict 8, legacy inventory)

Already independently verified against the `Perspectives_Prototype` repository during MIG-000 (not this phase): **7 entities, 10 functions** (not 9 — `seedSubtopics` was previously undocumented), **27 custom components** (not 22), **49 shadcn primitives** (not 45). See `examples/perspectives/LEGACY_INVENTORY.md` in the toolkit repository. Restated here only for completeness of the reconciliation record; no new evidence from this phase changes it.

## 7. Present RLS state (item: "present RLS state")

RLS is **enabled on all 11 tables** (`row_level_security_enabled = true` everywhere; `row_level_security_forced = false` everywhere — meaning the table owner, `postgres`, still bypasses RLS, which is expected and fine since the worker's direct connection uses that role).

Policy-by-policy:

| Table | Policies | Effective behaviour |
|---|---|---|
| `articles`, `authors`, `journals`, `specialties`, `subtopics`, `article_specialties` | 1 each: `SELECT USING (auth.role() = 'authenticated')` | Authenticated users can read; **anon gets nothing**, regardless of its table grant. |
| `article_processing_log` | 1: `SELECT USING (auth.role() = 'authenticated')` | Same shape as the six tables above — i.e., whoever configured this treated it as just another public-read table, not as worker-only. |
| `interaction_signals` | 3: own-row `SELECT`, `INSERT` (`WITH CHECK`), `DELETE`, all keyed on `auth.uid() = user_id` | Matches every document. No `UPDATE` policy exists. |
| `user_preferences` | 3: own-row `SELECT`, `INSERT` (`WITH CHECK`), `UPDATE` (`USING` + `WITH CHECK`), all keyed on `auth.uid() = user_id` | Matches every document. No `DELETE` policy exists. |
| `api_cache`, `content_fingerprints` | **0 policies each** | RLS enabled with zero policies is Postgres's default-deny: nobody except the table owner can see or touch a row, regardless of table grants. Currently, correctly, fully locked. |

## 8. Present grant state and overexposure findings (items: "present grant state", "overexposure or underexposure findings")

Every one of the 11 tables currently grants **`SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` to both `anon` and `authenticated`** (and, separately and appropriately, to `service_role`) — 308 raw `table_privileges` rows total, exactly `11 tables × 4 roles × 7 privilege types`. Column-level privileges (1,824 rows) are a homogeneous per-column mirror of the same table-level grants; no column carries a narrower restriction than its table.

This is the signature of Supabase's legacy "automatically expose new tables to the Data API" project-creation default (documented as a fallback in the runbook's Appendix C) — not the explicit-grant model the runbook otherwise assumes throughout Part 3.

**Overexposure, mitigated by RLS today:**
- `api_cache` and `content_fingerprints` hold full anon/authenticated table-level grants but zero RLS policies — currently unreachable in practice, but this is fragile: any future permissive policy accidentally added to either table would immediately expose it, because the grant layer places no restriction at all.
- The six public-read tables and `article_processing_log` hold full anon `INSERT/UPDATE/DELETE` grants with no corresponding RLS policy permitting those commands for any role — currently blocked by RLS's default-deny-per-command behaviour, again relying entirely on RLS staying exactly as configured.

**Underexposure relative to any document's plan:** none found. Every table any document expected to be reachable is at least as reachable as expected (in fact, more so, due to the broad grants) — the gap here runs entirely in the overexposure direction.

**Currently effective Data API exposure** (`has_table_privilege`, independent of RLS) confirmed **`TRUE` for every privilege type, for both `anon` and `authenticated`, on all 11 tables** — i.e., at the grant layer alone, there is currently no distinction between any table's intended sensitivity. RLS is the only thing doing any work today.

## 9. Resolved decisions (this phase)

1. **`article_processing_log` access: WORKER-ONLY** (Option A). Confirmed by the project owner after reviewing the live evidence in §6.1/§7/§8 above — specifically that the live RLS policy shape matched the public-read tables rather than the deny-all shape used for the other two worker-only tables, which was presented as evidence *against* Option A before the owner's decision. The owner chose Option A regardless, on the basis that this table holds internal processing records. **Follow-up required in a later phase:** the live RLS policy `processing_log_authenticated_read` predates this decision and must eventually be dropped; the proposed grant SQL revokes the table-level grant now, which is sufficient to close the Data API path immediately once executed, independent of when the stale policy is cleaned up.
2. **V1 read access: authenticated-only, no anon reads.** Confirmed by the project owner as the intended V1 product state: users must sign in before accessing reader-facing content (`articles`, `authors`, `journals`, `specialties`, `subtopics`, `article_specialties`). This matches the RLS policies already live on those six tables — no RLS change is implied by this decision, only removing the unused `anon` table-level grant.

   **Note on "the frontend uses the anon key only":** this settled architecture point is not in tension with requiring sign-in. "Anon key" refers to which *type* of Supabase client key `Perspectives-app` holds (the public key, never the service-role key) — it is not a statement about whether unauthenticated requests can read data. A signed-in user's browser still authenticates via the anon key plus their session's access token; RLS then evaluates their role as `authenticated`. The frontend never needs, and must never hold, the service-role key regardless of this decision.

## 10. Remaining open decisions (carried forward, unresolved)

1. **`runMonthIngestion`** — port, replace, or deliberately drop. Unresolved.
2. **`pruneOldArticles`** — port, replace, or deliberately drop while preserving saved-article protection. Unresolved.
3. **Exact current Anthropic API model identifiers** — must be verified against official documentation at implementation time; the `claude-3-5-*` strings in the master document are known-stale. Unresolved (not a MIG-001-scope question).
4. **`articles.embedding` vector dimension** — not recoverable from `information_schema.columns`; the documents' assumed 1536 (OpenAI `text-embedding-3-small`) has not been verified against the live catalogue. New, raised by this phase. See `supabase/baseline/README.md`.
5. **Author/tag data-model mismatch (§6.2, §6.3)** — not a yes/no decision, but a fact the Phase 2 worker design must account for: no `article_authors` or `article_tags` join tables exist; authors are a single FK plus a JSON co-authors blob, and tags/subtopics are plain array columns.
6. **Stale RLS policy cleanup on `article_processing_log`** — flagged in §9.1, not executed in MIG-001.

## 11. Proposed least-privilege model

See `supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql` in full. Summary:

| Table | anon | authenticated |
|---|---|---|
| `articles`, `authors`, `journals`, `specialties`, `subtopics`, `article_specialties` | *(none)* | `SELECT` |
| `interaction_signals` | *(none)* | `SELECT, INSERT, DELETE` |
| `user_preferences` | *(none)* | `SELECT, INSERT, UPDATE` |
| `api_cache`, `content_fingerprints`, `article_processing_log` | *(none)* | *(none)* |

`service_role` is left untouched throughout (Supabase's standard default; the worker's documented direct-Postgres connection doesn't depend on it via the Data API anyway).

## 12. Baseline limitations

See `supabase/baseline/README.md` in full. Headline limitation: `articles.embedding`'s vector dimension could not be recovered from `information_schema.columns` and is not asserted anywhere in the baseline. The baseline has **not** been replay-tested against any database, local or otherwise.

## 13. Proof no live mutation occurred

- Claude Code's tool use in this phase never included the Supabase CLI, `psql`, `pg_dump`, a database URL, an anon key, a service-role key, a Management API call, a Data API call, PostgREST, or GraphQL.
- The only artifact reflecting live state is a file the project owner exported by hand from the Supabase SQL Editor and saved to local disk; Claude Code's only interaction with it was reading that local file.
- All generated SQL (`20260821_EXISTING_STATE_BASELINE.sql`, `20260821_PROPOSED_DATA_API_GRANTS.sql`) carries an execution guard (`DO $guard$ ... RAISE EXCEPTION ...`) that aborts on any accidental run, and neither guard was removed at any point.

## 14. Recommended next phase

**MIG-002 — Local Baseline Replay Validation and Reviewed Grant Execution Planning.** Must remain separately authorised. Must not execute grant changes against production unless a later, explicit authorisation separately permits that specific action. Suggested scope: stand up a disposable local/throwaway Postgres instance, remove the baseline's execution guard there only, replay `20260821_EXISTING_STATE_BASELINE.sql`, confirm it runs clean end-to-end, resolve the `articles.embedding` dimension question, and only then plan (not execute) how `20260821_PROPOSED_DATA_API_GRANTS.sql` would actually be applied to the live project.

## 15. Explicit statement on replay status

**The baseline has not yet been replay-tested.** No claim in this report or in any MIG-001 deliverable should be read as asserting that `20260821_EXISTING_STATE_BASELINE.sql` has been proven to execute successfully anywhere. Its content is believed accurate because it was generated mechanically from each object's own live catalogue definition, not because it has been run.
