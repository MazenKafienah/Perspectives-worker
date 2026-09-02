-- ============================================================================
-- MIG-002 — Reviewed Grant Rollback (PROPOSAL ONLY — NOT EXECUTED)
-- ============================================================================
--
-- WHAT THIS FILE DOES
--   Restores the exact PRE-CHANGE grant state verified live during MIG-001:
--   full SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER on every one
--   of the 11 public tables, for both `anon` and `authenticated`. This is the
--   legacy Supabase auto-expose default the project was actually running
--   under at MIG-001 capture time — see
--   Perspectives-worker/docs/MIG001_LIVE_SCHEMA_RECONCILIATION_REPORT.md
--   section 8 for the full evidence.
--
-- WARNING — THIS IS A ROLLBACK OF GRANTS ONLY, NOT OF RLS
--   Running this file recreates the previous OVER-PERMISSIVE table-privilege
--   state — including on the two tables that should never be reachable via
--   the Data API at all (api_cache, content_fingerprints) and on
--   article_processing_log. Whether that state is actually EXPLOITABLE after
--   rollback depends entirely on RLS, which this file does not touch:
--     - api_cache / content_fingerprints: RLS enabled, zero policies, so
--       rollback alone does not expose them (default-deny still applies) —
--       but the underlying grant is again far broader than intended.
--     - article_processing_log: has a live, residual RLS policy permitting
--       authenticated SELECT. Rolling back this grant file WOULD immediately
--       re-expose this table's rows to authenticated Data API callers, via
--       that policy, because the table privilege the policy depends on would
--       exist again. Do not roll back without accounting for this.
--   This file is a REVIEW-ONLY artifact for a future, separately authorised
--   phase, not a casual "undo button." Use it only with a specific, reviewed
--   reason (e.g. an unexpected production incident traced to the target
--   grant state) and full awareness of the above.
--
-- EXECUTION GUARD
--   Remove only inside a separately authorised execution context.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-002 REVIEWED GRANT ROLLBACK: execution guard active. This file restores the previous, over-permissive legacy grant state and must not be run casually. Remove this guard only inside an explicitly authorised execution context, after re-reading the warning above.';
END;
$guard$;

-- ============================================================================
-- Restore the exact pre-change (legacy auto-expose) grant state.
-- ============================================================================

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;

-- ============================================================================
-- Verification — confirm the pre-change state was restored exactly.
-- ============================================================================

-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.table_privileges
-- WHERE table_schema = 'public' AND grantee IN ('anon','authenticated')
-- ORDER BY table_name, grantee, privilege_type;
--
-- Expect: every one of the 11 tables x {anon, authenticated} x
-- {SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER} = 154 rows,
-- matching the MIG-001 captured pre-change state exactly.
