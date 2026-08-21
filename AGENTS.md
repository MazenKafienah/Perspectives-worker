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

Do not create schema SQL in this phase (MIG-000). A live-database baseline capture and grant reconciliation happens in a separately authorised phase (MIG-001) — read-only inspection first, no state-changing SQL without explicit separate authorisation. When that baseline lands, treat it as a snapshot of already-existing production state, not a script to blindly rerun.

## Current status

MIG-000 governance only. No pipeline modules, dependencies, or SQL exist yet beyond this documentation and an empty `supabase/migrations/` placeholder.
