# AGENTS.md — Perspectives-worker

Instructions for any AI coding agent (Claude Code, or otherwise) working in this repository.

## What this repository is

The Python ingestion/enrichment/summarisation worker for PERSPECTIVES, and the canonical home of executable Supabase database migrations for the project.

## Hard boundaries — do not cross these

- **No frontend code here.** The Next.js application lives in `Perspectives-app`. Do not add React/Next.js files here.
- **This is the only canonical location for production SQL.** `supabase/migrations/` in this repository is the single source of truth for the PERSPECTIVES schema. Do not create a second canonical copy of production migrations anywhere else, including in `Base44-to-standalone`.
- **The worker is a scheduled script, not a server.** Do not add FastAPI, uvicorn, or any HTTP server. Do not stand up a Railway deployment as the primary host — scheduling is GitHub Actions cron (target `0 6,18 * * *`).
- **Service-role key stays here.** It goes in this repository's environment only (GitHub Actions secrets, or a local git-ignored `.env`). Never place it in `Perspectives-app`, never commit it, never print it in logs.
- **Direct Postgres connection, not the Data API.** The worker authenticates as the `postgres` role via `DATABASE_URL`. It is unaffected by Supabase Data API grant requirements (those only govern PostgREST/GraphQL/`supabase-js` access, which is the frontend's concern).

## Pipeline guardrails (non-negotiable)

- Impact factors: verified lookup only (`data/journals.yml` / `journals` table). Never ask an LLM to supply or verify an impact factor.
- Summarisation: two-call structure always — extraction, then writing. Never merge into one call.
- Deduplication: DOI check first, SimHash fingerprint second. Never loose-match on title alone.
- Embeddings: OpenAI `text-embedding-3-small`, 1536 dimensions.
- Model identifiers: do not hardcode a Claude model string from any planning document without first checking Anthropic's current documentation. Planning-doc pins (e.g. `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`) are known-stale placeholders, not confirmed production values.

## Database migrations

MIG-001 produced a read-only-captured existing-state baseline (`supabase/baseline/`) and a proposed grant script (`supabase/grants/`), both guarded against accidental execution and neither replay-tested. Treat both as snapshots/proposals, not scripts to run. `supabase/migrations/` remains empty until a later, separately authorised phase populates it with real, replay-validated migrations.

## Permanent credential-handling rules (do not remove or weaken)

These apply in every future phase, not just MIG-001, following a real incident where a diagnostic command printed a live credential into a session transcript:

- Never run a credential-helper, Keychain, or secret-store lookup as a diagnostic or troubleshooting step (`git credential*`, `security find-*-password`, Supabase/GitHub CLI credential-storage inspection, etc.).
- Never enumerate or print environment variables as a diagnostic step (`env`, `printenv`, `export -p`, or similar).
- Never read a `.env`, `.env.local`, or any other populated environment file.
- Never read, request, print, log, or commit a Supabase access token, database password, service-role key, Anthropic/OpenAI API key, GitHub token, or any connection string containing credentials.
- If a required CLI or authentication is unavailable, stop and report exactly that — do not probe for an alternate way to recover or work around missing credentials.
- Claude Code must never connect directly to Supabase (CLI, Management API, Data API, PostgREST, GraphQL, or a raw `psql`/connection-string session). Live database facts are gathered only via a read-only SQL query that a human runs manually and exports to a local file for Claude Code to read.

## Current status

MIG-001 complete: live schema captured (read-only, manual export), reconciled against the planning documents, existing-state baseline and proposed grants drafted (both guarded, neither executed, neither replay-tested). No worker pipeline modules or dependencies exist yet. No SQL has been executed against Supabase at any point in this project's history to date.
