# MIG-002 — Future Production Execution Plan (REVIEW ONLY — NOT AUTHORISED FOR EXECUTION)

This plan describes how a **later, separately authorised phase** should execute the reviewed grant change against the live PERSPECTIVES Supabase project. Nothing in this document is an instruction to execute anything now, and MIG-002 itself executes nothing against production. This plan is a checklist for that future phase to follow, and for a human to approve step by step.

## Pre-execution requirements (all must be satisfied before that future phase begins)

1. **Explicit, separate user authorisation** naming this specific action (grant execution against the named live project), distinct from the authorisation that produced this plan.
2. **Confirmed correct live project identity** — the operator running the SQL must independently confirm they are connected to the actual PERSPECTIVES production project (correct project reference, correct region), not a different project.
3. **A fresh, read-only live capture**, taken the same way as MIG-001's (a human runs the committed read-only capture query manually, no coding agent connects directly), timestamped close to the execution window.
4. **Schema/grant drift comparison** between that fresh capture and the MIG-001/MIG-002 baseline this plan was built from. If the live table set, RLS policies, or grants have changed since MIG-001, this plan must be re-reviewed before proceeding — do not execute against a database that has drifted from what was analysed.
5. **Approved SQL hashes** — the operator must confirm the exact file they are about to run matches a specific, named, approved SHA-256 (of `MIG002_REVIEWED_GRANT_PLAN.sql` with its guard removed), not "something similar."
6. **Rollback readiness** — `MIG002_REVIEWED_GRANT_ROLLBACK.sql` reviewed and ready, with its own guard understood (see that file's warning about `article_processing_log` before anyone reaches for it reflexively).
7. **Operator/permission confirmation** — whoever executes this must have the necessary Supabase project permissions and should not be doing so unilaterally without the project owner's sign-off at execution time, even if a general authorisation exists.
8. **Appropriate execution timing** — outside the worker's active ingestion windows (currently planned as 06:00 and 18:00 UTC) if at all avoidable, so that any unexpected effect is easier to isolate from a concurrent pipeline run.

## Execution sequence (for the future authorised phase to follow)

1. Take the fresh live read-only capture (pre-requisite 3).
2. Compare it against the expected MIG-001/MIG-002 state (pre-requisite 4). **Abort if there is unexpected drift** — do not proceed on the assumption that a small difference is harmless.
3. Manually review the exact guarded target SQL one final time, in full, immediately before running it.
4. Execute `MIG002_REVIEWED_GRANT_PLAN.sql` (guard removed) **only under the separate authorisation from pre-requisite 1**.
5. **Immediately** re-run the file's own verification query (the commented `SELECT ... FROM information_schema.table_privileges ...` block at the bottom) to confirm the resulting grant state matches intent exactly.
6. If the project's execution context provides transactional DDL/grant semantics (Postgres supports transactional `GRANT`/`REVOKE`, so wrapping steps 4–5 in an explicit `BEGIN`/`COMMIT` is possible and recommended) — **commit only if the verification in step 5 passes**.
7. If verification fails, **roll back the transaction** (if still open) or apply `MIG002_REVIEWED_GRANT_ROLLBACK.sql` (if already committed) — understanding its `article_processing_log` caveat first.
8. Perform **independent post-execution verification**: from a separate check (e.g. a `curl` against `/rest/v1/<table>` with the anon key, expecting a permission error on tables that should no longer be anon-readable, and a normal response — or empty array — where authenticated access is expected), confirm the live Data API actually behaves as intended, not just that the catalogue says so.
9. **Preserve audit evidence** — save the fresh pre-execution capture, the exact SQL executed (with its hash), the verification query output, and a timestamp, in a durable location for this specific execution event.

## Explicit abort conditions

Abort before executing (or roll back if already executed) if any of the following is true:

- The fresh capture's table set, RLS policies, or existing grants differ from what this plan assumes, in any way not already accounted for.
- The operator cannot independently confirm they are connected to the correct production project.
- The SQL about to be run does not match the approved hash exactly.
- Any step 5 verification query returns an unexpected row (e.g. `anon` shows a privilege on any table, or `authenticated` is missing an expected privilege, or has an unexpected extra one).
- Anything about the live database's state at execution time looks inconsistent with the MIG-001/MIG-002 analysis in a way not explained by expected, accounted-for drift (e.g. a new table appeared, a policy changed).

## What this plan deliberately does not decide

- **The residual `article_processing_log` RLS policy** (`processing_log_authenticated_read`) is not addressed by the grant execution in this plan. Revoking the table-level grant is sufficient to close Data API access to it regardless of that policy's presence (see MIG-002's local test of this exact distinction). Removing the stale policy itself is separate follow-up work requiring its own authorisation — this plan does not include it, and executing this plan does not constitute doing that cleanup.
- **The `articles.embedding` vector dimension** remains unverified against the live catalogue. This plan concerns Data API grants only, not schema changes, and does not depend on that answer — but it is called out here so it is not forgotten before any future schema-changing phase.
