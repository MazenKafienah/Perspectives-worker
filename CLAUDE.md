# CLAUDE.md — Perspectives-worker

This file is read by Claude Code when working in this repository. The full set of rules lives in [AGENTS.md](AGENTS.md) — read that file first; it applies to Claude Code exactly as it does to any other agent.

## Quick summary

- This repo owns the Python ingestion worker and the canonical, executable Supabase migrations for PERSPECTIVES.
- The worker connects to Postgres directly (`DATABASE_URL`) and holds the service-role key; it never ships to a browser.
- Scheduling is GitHub Actions cron, not an HTTP server and not Railway as primary host.
- Summarisation stays two-call; dedup stays DOI-then-SimHash; impact factors stay lookup-only; embeddings stay OpenAI `text-embedding-3-small` at 1536 dimensions.
- Verify exact Anthropic model identifiers against official docs before writing them into code — do not trust planning-document pins.

## Permanent credential-handling rules

Never inspect Keychain, credential helpers, environment variables, shell history, or populated `.env` files as a diagnostic step; never read/print/commit a Supabase key, password, connection string, or any other credential; never connect directly to Supabase (see [AGENTS.md](AGENTS.md) for the full list and the incident that established this). If a required CLI or auth is unavailable, stop and report that plainly rather than probing for a workaround.

## Current phase

MIG-001 is complete: the live schema was captured read-only (a human ran the query manually and exported the result; Claude Code only read that export from disk), reconciled against the planning documents, and an existing-state baseline plus a proposed grant script were drafted — both guarded against execution, neither replay-tested, neither run against the live project. No worker modules or dependencies exist yet.
