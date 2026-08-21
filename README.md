# Perspectives-worker

Python discovery, enrichment, and summarisation worker for **PERSPECTIVES**, plus the canonical, executable Supabase database migrations for the project.

This repository owns the **ingestion pipeline and the production database schema**. It is the single place PERSPECTIVES SQL migrations are written and applied from.

## Scope

- The Python 3.12 worker: discovery (PubMed, Crossref, RSS), bibliographic resolution, journal/impact-factor lookup, author resolution and enrichment, two-call editorial summarisation, validation/dedup, and persistence.
- Scheduling via **GitHub Actions cron** (target: 06:00 and 18:00 UTC). This worker is **not** an HTTP server — no FastAPI, no uvicorn, no Railway as primary host.
- A **direct PostgreSQL connection** to Supabase (`DATABASE_URL`, `postgres` role), independent of Supabase Data API grants.
- The Supabase **service-role key**. This key lives only in this repository's environment (GitHub Actions secrets for CI; a local `.env` — never committed — for development). It must never appear in `Perspectives-app` or in any `NEXT_PUBLIC_` variable.
- `supabase/migrations/` — the canonical, executable SQL migration history for the live PERSPECTIVES database.

## Explicitly out of scope for this repository

- The reader-facing frontend — that lives in [`Perspectives-app`](https://github.com/MazenKafienah/Perspectives-app).
- Serving HTTP traffic. The worker runs as a scheduled script, not a server.

## Non-negotiable pipeline guardrails

- **Journal impact factors come only from a verified lookup** (`data/journals.yml` / the `journals` table), never from an LLM guess.
- **Summarisation is a two-call design**: Call A extracts structured facts (claims, referenced studies, caveats); Call B writes the headline and plain-language summary from Call A's output only. Never collapse this into a single call.
- **Deduplication is DOI-first, then SimHash** content-fingerprint fallback. Never rely on loose title matching alone.
- **Embeddings** use OpenAI `text-embedding-3-small` at 1536 dimensions.
- Exact current Anthropic API model identifiers (the intended split is Sonnet for extraction, Haiku for writing) **must be verified against Anthropic's official documentation at implementation time**. Do not copy a stale `claude-3-5-*` model string from any planning document — those pins predate this repository and are known to be outdated.

## Database migrations

`supabase/migrations/` is the **only** canonical, executable location for PERSPECTIVES production SQL. No other repository in this project (including the general migration toolkit) should hold a second canonical copy of production schema.

A baseline capture of the **existing live database** (created outside this repository, prior to any migration file existing here) will be reconciled into this directory in a separately authorised phase (MIG-001). That baseline represents already-existing production state — it must not be blindly reapplied against production without review.

## Environment variables

See [`.env.example`](.env.example). Populate a local, git-ignored `.env` for development; never commit real values.

```
DATABASE_URL=
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
```

## Status

This repository currently contains only MIG-000 governance and documentation, plus an empty `supabase/migrations/` directory placeholder. No worker code, dependencies, or schema SQL has been created yet.
