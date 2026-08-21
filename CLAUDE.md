# CLAUDE.md — Perspectives-worker

This file is read by Claude Code when working in this repository. The full set of rules lives in [AGENTS.md](AGENTS.md) — read that file first; it applies to Claude Code exactly as it does to any other agent.

## Quick summary

- This repo owns the Python ingestion worker and the canonical, executable Supabase migrations for PERSPECTIVES.
- The worker connects to Postgres directly (`DATABASE_URL`) and holds the service-role key; it never ships to a browser.
- Scheduling is GitHub Actions cron, not an HTTP server and not Railway as primary host.
- Summarisation stays two-call; dedup stays DOI-then-SimHash; impact factors stay lookup-only; embeddings stay OpenAI `text-embedding-3-small` at 1536 dimensions.
- Verify exact Anthropic model identifiers against official docs before writing them into code — do not trust planning-document pins.

## Current phase

This repository is in **MIG-000** (governance bootstrap) as of the commit that added this file. No worker modules, dependencies, or SQL migrations exist yet. A later, separately authorised phase (MIG-001) performs read-only live-schema capture before any migration file is written here.
