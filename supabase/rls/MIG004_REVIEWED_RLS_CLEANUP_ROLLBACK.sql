-- ============================================================================
-- MIG-004 — Reviewed RLS Cleanup Rollback (PROPOSAL ONLY — NOT EXECUTED)
-- ============================================================================
--
-- WHAT THIS FILE DOES
--   Recreates exactly one RLS policy on public.article_processing_log,
--   reproducing the fresh, verified pre-cleanup definition field-for-field:
--
--     name:          processing_log_authenticated_read
--     permissive:    PERMISSIVE
--     command:       SELECT
--     roles:         public
--     using:         auth.role() = 'authenticated'
--     with check:    (none)
--
--   Derived directly from the fresh 2026-09-08 production capture
--   (mig004_pre_cleanup_schema_capture.csv, SHA-256
--   1244c17074132a91eb165c3dad12d39e8becb4250a6871d09f4b400aa19fb030) and
--   cross-checked against MIG-003's explicitly recorded post-execution
--   policy definition. Not reconstructed from memory or from any planning
--   document.
--
-- WARNING — WHAT RECREATING THIS POLICY DOES AND DOES NOT DO
--   Because MIG-003 already revoked article_processing_log's table-level
--   grant from anon and authenticated, recreating this policy alone does
--   NOT restore any client-visible access — a table privilege is required
--   before RLS is evaluated at all, and this rollback does not touch grants.
--   This file exists purely to undo the MIG-004 cleanup at the RLS-policy
--   layer specifically, for cases where that exact layer needs restoring
--   (e.g. a review process wants the historical policy back for reference,
--   or the cleanup is judged premature after the fact). It is not a general
--   "undo MIG-004" or "restore old access" mechanism.
--
-- SCOPE — THIS IS THE ONLY MUTATING STATEMENT IN THIS FILE
--   One CREATE POLICY. No GRANT/REVOKE, no other policy, no table/column/
--   RLS-enabled-state change.
--
-- EXECUTION GUARD
--   Remove only in the SQL Editor's paste buffer, after a separate explicit
--   authorisation, and only if the defined MIG-004 rollback condition is
--   actually met. Never edit this committed file to remove the guard.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-004 RLS CLEANUP ROLLBACK: execution guard active. This file recreates a specific RLS policy that MIG-004 removed. It must not be run casually — see the header warning about what it does and does not restore. Remove this guard only in the SQL Editor paste buffer, after separate explicit authorisation, and only if the defined rollback condition is met.';
END;
$guard$;

CREATE POLICY processing_log_authenticated_read ON public.article_processing_log
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (auth.role() = 'authenticated'::text);

-- ============================================================================
-- Verification query — run after execution to confirm restoration.
-- Expect: exactly one row, matching the definition documented above.
-- ============================================================================

-- SELECT policyname, tablename, cmd, roles, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename = 'article_processing_log';
