-- ============================================================================
-- MIG-001 — Proposed Data API Grants (PROPOSAL ONLY — NOT EXECUTED)
-- ============================================================================
--
-- WHAT THIS FILE IS
--   A least-privilege Data API grant script, rebuilt from the VERIFIED live
--   table set captured 2026-08-27T21:12:04Z (capture SHA-256
--   670f0cfd82dbf783d7891663c58924a420137ee2b0014fdc3474de417b1fb7e1), not
--   copied from the execution runbook's stale Appendix A table list (which
--   was written against a different, incompatible schema shape — see
--   docs/MIG001_LIVE_SCHEMA_RECONCILIATION_REPORT.md, conflict 7).
--
-- WHAT THIS FILE IS NOT
--   - It was NOT executed during MIG-001. Nothing in this file has touched
--     the live database. Claude Code made no Supabase connection at any
--     point in MIG-001.
--   - It is a PROPOSAL for a later, separately authorised phase to review
--     and execute (or amend) against the live project.
--
-- WHY A REVOKE STEP IS NEEDED FIRST
--   The live capture shows every one of the 11 public tables currently
--   grants full SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER to
--   BOTH `anon` and `authenticated` — including the tables that are meant
--   to be worker-only (api_cache, content_fingerprints,
--   article_processing_log). This matches the legacy Supabase
--   "automatically expose new tables to the Data API" default (Runbook
--   Appendix C), not the explicit least-privilege model this project
--   intends. RLS currently prevents most of that from being exploitable
--   (see the reconciliation report), but the underlying grants themselves
--   are far broader than intended and must be revoked before the correct,
--   narrow grants are added back.
--
--   `service_role` is intentionally left untouched by the REVOKE below.
--   Supabase's standard design gives service_role full access to `public`
--   by default and this project's own documents plan for the worker to use
--   a direct Postgres connection anyway (unaffected by any of this) — there
--   is no documented reason to narrow service_role here, and doing so risks
--   breaking something outside this capture's visibility.
--
-- DECISIONS THIS FILE ENCODES (confirmed by the project owner during MIG-001)
--   1. article_processing_log is WORKER-ONLY. No anon/authenticated grant.
--      The live database currently has an RLS policy,
--      `processing_log_authenticated_read`, that permits authenticated
--      SELECT — this predates and conflicts with that decision. Revoking
--      the table-level grant below makes the table unreachable via the
--      Data API immediately (grants are checked before RLS is evaluated),
--      even before that stale policy is removed. The policy itself should
--      still be dropped in a later, separately authorised phase for
--      hygiene — a future accidental re-grant would otherwise silently
--      reactivate authenticated read access through it. That cleanup is
--      NOT performed here.
--   2. V1 is authenticated-only for reader-facing content. `anon` gets NO
--      read access to articles, authors, journals, specialties, subtopics,
--      or article_specialties. This matches the live RLS policies already
--      in place on those six tables (`USING (auth.role() = 'authenticated')`)
--      — so unlike article_processing_log, no RLS change is implied here,
--      only removing the unnecessary `anon` table-level grant that RLS was
--      already blocking in practice.
--
-- EXECUTION GUARD
--   Remove only when a separately authorised phase is ready to execute this
--   against the live project, after independent review.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-001 PROPOSED DATA API GRANTS: execution guard active. This file is a reviewed proposal, not yet authorised for execution against the live PERSPECTIVES project. Remove this guard only in a separately authorised grant-execution phase, after independent review of the header comments above.';
END;
$guard$;

-- ============================================================================
-- Step 1 — Revoke the current, overly broad default grants from anon and
-- authenticated on every public table. service_role is untouched (see above).
-- ============================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- ============================================================================
-- Step 2 — Re-grant exactly what each table needs, and nothing more.
-- Schema USAGE is already correctly granted live and is not touched here.
-- ============================================================================

-- Public-read tables (verified live, decision: authenticated-only for V1).
-- RLS already restricts SELECT to `auth.role() = 'authenticated'` on all six;
-- this grant simply stops offering anon a privilege RLS was already denying,
-- and confirms authenticated keeps exactly SELECT (no write access here).
GRANT SELECT ON public.articles             TO authenticated;
GRANT SELECT ON public.authors              TO authenticated;
GRANT SELECT ON public.journals             TO authenticated;
GRANT SELECT ON public.specialties          TO authenticated;
GRANT SELECT ON public.subtopics            TO authenticated;
GRANT SELECT ON public.article_specialties  TO authenticated;

-- Per-user tables. Command list matches the live RLS policies exactly
-- (interaction_signals has no UPDATE policy; user_preferences has no DELETE
-- policy) — granting a command with no corresponding policy would be inert
-- at best and misleading about intent at worst, so it is omitted.
GRANT SELECT, INSERT, DELETE ON public.interaction_signals TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_preferences    TO authenticated;

-- Worker-only tables: article_processing_log, api_cache, content_fingerprints.
-- Deliberately NOT granted to anon or authenticated. Reached only by the
-- worker's direct Postgres connection (as the `postgres` role), which is
-- unaffected by Data API grants entirely.
--
-- article_processing_log in particular: see "Decisions" note 1 above — this
-- table currently has a live RLS policy that would allow authenticated
-- SELECT if a grant existed. No grant is added here, which is sufficient to
-- keep it unreachable via the Data API. The stale policy itself is flagged
-- for removal in a later phase, not handled here.

-- No sequence grants are required: every table uses gen_random_uuid() or a
-- plain bigint column (content_fingerprints.fingerprint) rather than an
-- owned SERIAL/BIGSERIAL sequence, per the live capture (sequences: []).

-- ============================================================================
-- Verification queries — run these AFTER this file is executed in a future,
-- separately authorised phase, to confirm the intended state was reached.
-- Safe to run any time: read-only, no data returned beyond booleans/text.
-- ============================================================================

-- Expect: anon has SELECT nowhere in this list (no rows for anon at all,
-- since anon has no grant on any of these 11 tables after this file runs).
-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.table_privileges
-- WHERE table_schema = 'public' AND grantee = 'anon'
-- ORDER BY table_name, privilege_type;

-- Expect: authenticated has exactly SELECT on the six public-read tables,
-- SELECT/INSERT/DELETE on interaction_signals, SELECT/INSERT/UPDATE on
-- user_preferences, and nothing on api_cache / content_fingerprints /
-- article_processing_log.
-- SELECT table_name, privilege_type
-- FROM information_schema.table_privileges
-- WHERE table_schema = 'public' AND grantee = 'authenticated'
-- ORDER BY table_name, privilege_type;

-- Per-table effective exposure check (mirrors the capture's data_api_exposure
-- section) — expect FALSE for anon on every table, and TRUE only where
-- listed above for authenticated:
-- SELECT relname AS table_name,
--        has_table_privilege('anon', oid, 'SELECT') AS anon_select,
--        has_table_privilege('authenticated', oid, 'SELECT') AS authenticated_select
-- FROM pg_class
-- WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r','p')
-- ORDER BY relname;
