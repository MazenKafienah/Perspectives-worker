-- ============================================================================
-- MIG-002 — Reviewed Target Grant Plan (PROPOSAL ONLY — NOT EXECUTED)
-- ============================================================================
--
-- RELATIONSHIP TO THE MIG-001 PROPOSAL
--   This is the MIG-002-reviewed counterpart of
--   Perspectives-worker/supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql.
--   The target privilege state is IDENTICAL in intent and content — both
--   locked decisions (article_processing_log worker-only; V1 authenticated-only
--   for the six reader-content tables) were already known and already
--   incorporated when the MIG-001 file was drafted, so no correction to the
--   target state was needed. This file exists as a separate MIG-002 artifact
--   because it is the version that was actually locally rehearsed (applied to
--   a disposable local Supabase stack, verified for idempotency, and verified
--   to be reversible) — see MIG002_LOCAL_GRANT_VALIDATION.md for the results.
--   The MIG-001 file is left untouched; nothing here rewrites MIG-001 history.
--
-- WHAT THIS FILE IS NOT
--   Not executed against production. Not executed against anything at all
--   outside the disposable local replay database during MIG-002. A future,
--   separately authorised phase reviews this (or a materially unchanged
--   copy of it) before any production execution — see
--   MIG002_PRODUCTION_EXECUTION_PLAN.md.
--
-- EXECUTION GUARD
--   Remove only inside a separately authorised execution context (local
--   replay rehearsal, or a future authorised production phase), never as a
--   matter of routine review.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-002 REVIEWED GRANT PLAN: execution guard active. This file is a reviewed proposal, locally rehearsed only. It has not been authorised for execution against production. Remove this guard only inside an explicitly authorised execution context.';
END;
$guard$;

-- ============================================================================
-- Step 1 — Revoke the current, overly broad default grants from anon and
-- authenticated on every public table. service_role is intentionally
-- untouched (Supabase's standard default; the worker's documented direct
-- Postgres connection does not depend on it via the Data API anyway).
-- ============================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- ============================================================================
-- Step 2 — Re-grant exactly what each table needs, and nothing more.
-- ============================================================================

-- Public-read tables (V1 = authenticated-only; LOCKED USER DECISION 2).
-- Live RLS already restricts SELECT to auth.role() = 'authenticated' on all
-- six; this grant matches that shape exactly. No anon grant — none is needed
-- or wanted for V1.
GRANT SELECT ON public.articles             TO authenticated;
GRANT SELECT ON public.authors              TO authenticated;
GRANT SELECT ON public.journals             TO authenticated;
GRANT SELECT ON public.specialties          TO authenticated;
GRANT SELECT ON public.subtopics            TO authenticated;
GRANT SELECT ON public.article_specialties  TO authenticated;

-- Per-user tables. Command list matches the live RLS policies exactly.
GRANT SELECT, INSERT, DELETE ON public.interaction_signals TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_preferences    TO authenticated;

-- Worker-only tables: article_processing_log, api_cache, content_fingerprints
-- (LOCKED USER DECISION 1 for article_processing_log). Deliberately NOT
-- granted to anon or authenticated. article_processing_log currently still
-- has a live RLS policy ('processing_log_authenticated_read') permitting
-- authenticated SELECT — this REVOKE (no corresponding GRANT is added back)
-- is sufficient on its own to make the table unreachable via the Data API,
-- because a table privilege is required before RLS is ever evaluated.
-- MIG-002 confirmed this distinction empirically (see
-- MIG002_LOCAL_GRANT_VALIDATION.md, "article_processing_log special test").
-- The stale policy itself remains untouched — that cleanup requires separate
-- authorisation and is not part of this file.

-- No sequence grants required: every table uses gen_random_uuid() or a plain
-- bigint column, not an owned SERIAL/BIGSERIAL sequence.

-- ============================================================================
-- Verification queries — safe to run any time after execution.
-- ============================================================================

-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.table_privileges
-- WHERE table_schema = 'public' AND grantee IN ('anon','authenticated')
-- ORDER BY table_name, grantee, privilege_type;
