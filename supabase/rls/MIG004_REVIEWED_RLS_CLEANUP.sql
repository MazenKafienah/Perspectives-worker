-- ============================================================================
-- MIG-004 — Reviewed RLS Cleanup: Residual article_processing_log Policy
-- (PROPOSAL ONLY — NOT EXECUTED)
-- ============================================================================
--
-- WHAT THIS FILE DOES
--   Removes exactly one stale RLS policy that predates the MIG-003 worker-only
--   decision for public.article_processing_log:
--
--     processing_log_authenticated_read
--     PERMISSIVE, FOR SELECT, TO public
--     USING (auth.role() = 'authenticated'::text)
--
--   This is the exact live definition, confirmed by:
--     (a) a fresh production capture taken 2026-09-08
--         (mig004_pre_cleanup_schema_capture.csv, SHA-256
--         1244c17074132a91eb165c3dad12d39e8becb4250a6871d09f4b400aa19fb030),
--     (b) an independent cross-check against the policy definition MIG-003
--         explicitly recorded as its post-execution state
--         (supabase/audit/MIG003_POST_EXECUTION_COMPARISON.json).
--   Both sources agree exactly. No detail here is reconstructed from memory.
--
-- WHY THIS IS SAFE TO REMOVE
--   MIG-003 already revoked article_processing_log's table-level grant from
--   both anon and authenticated. A table privilege is required before RLS is
--   ever evaluated, so this policy has been unreachable via the Data API
--   since MIG-003 executed — removing it changes no client-visible behaviour
--   at all. It is pure hygiene: closing the gap between "what the grant
--   layer allows" and "what the policy layer would allow if the grant ever
--   came back."
--
-- SCOPE — THIS IS THE ONLY MUTATING STATEMENT IN THIS FILE
--   One DROP POLICY. Nothing else. No GRANT/REVOKE, no table/column change,
--   no other policy touched, no RLS enabled/disabled state changed, no
--   function/trigger change, no data mutation.
--
--   No IF EXISTS is used deliberately: if the policy is not exactly present
--   as verified above at execution time, this statement should fail loudly
--   rather than silently succeed against a database that has drifted from
--   what was reviewed.
--
-- EXECUTION GUARD
--   Remove only in the SQL Editor's paste buffer, after a separate explicit
--   production-execution authorisation. Never edit this committed file to
--   remove the guard.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-004 RLS CLEANUP: execution guard active. This file removes a specific, freshly-verified stale RLS policy from production. It has not been authorised for execution. Remove this guard only in the SQL Editor paste buffer, after separate explicit authorisation, and only after re-confirming the policy still matches the definition documented above.';
END;
$guard$;

DROP POLICY processing_log_authenticated_read ON public.article_processing_log;

-- ============================================================================
-- Verification query — run after execution to confirm removal.
-- Expect: zero rows.
-- ============================================================================

-- SELECT policyname, tablename, cmd, roles, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename = 'article_processing_log';
