-- ============================================================================
-- MIG-001 — Existing-State Baseline (Captured, NOT Yet Replay-Validated)
-- ============================================================================
--
-- WHAT THIS FILE IS
--   A reconstruction of the PERSPECTIVES live Supabase `public` schema as it
--   existed at capture time, built entirely from the read-only catalogue
--   metadata captured by supabase/audit/MIG001_READ_ONLY_SCHEMA_CAPTURE.sql
--   (capture SHA-256: 670f0cfd82dbf783d7891663c58924a420137ee2b0014fdc3474de417b1fb7e1,
--   captured 2026-08-27T21:12:04Z). See supabase/baseline/README.md and
--   docs/MIG001_LIVE_SCHEMA_RECONCILIATION_REPORT.md for full context.
--
-- WHAT THIS FILE IS NOT
--   - This is NOT a migration to run against the already-live PERSPECTIVES
--     project. That project already has this schema — running this file
--     there would fail on "already exists" errors at best, and is not the
--     intent regardless.
--   - This has NOT been executed against a fresh local database. It has not
--     been replay-tested. Its syntactic and semantic correctness is believed
--     good (it was generated mechanically from live catalogue definitions,
--     using each object's own pg_get_*def() output wherever available), but
--     "believed correct" is not "proven to run." Local replay validation is
--     a separate, later, separately authorised phase (MIG-002 or later).
--   - This is NOT evidence that MIG-001 changed the live database. MIG-001
--     made no database connection at all; Claude Code never touched
--     Supabase directly. Every fact in this file came from a CSV/JSON file
--     the project owner exported by hand from the Supabase SQL Editor.
--
-- DATA API GRANTS ARE DELIBERATELY NOT IN THIS FILE
--   Table/column/routine/schema privileges are handled separately in
--   supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql. This file is
--   schema shape only: tables, constraints, indexes, functions, triggers,
--   RLS enablement, and RLS policies.
--
-- KNOWN LIMITATIONS OF THIS RECONSTRUCTION
--   - articles.embedding is `extensions.vector` with an UNSPECIFIED
--     dimension. information_schema.columns does not expose a vector
--     column's typmod (dimension parameter) the way it does for
--     character-length columns. The planning documents say 1536 (OpenAI
--     text-embedding-3-small), but that has not been verified against the
--     live catalogue in this capture and is NOT asserted here as fact.
--     Confirm the true dimension (e.g. `\d+ public.articles` in the SQL
--     Editor, or a follow-up capture of pg_attribute.atttypmod) before
--     replay.
--   - Platform-managed extensions (pg_stat_statements, supabase_vault) seen
--     in the capture are intentionally NOT recreated below — they are
--     Supabase-platform concerns, not application schema, and a generic
--     local Postgres instance would not replicate Supabase's own semantics
--     for them regardless.
--   - Column/table/routine grants are, per the live capture, currently far
--     broader than intended (see the reconciliation report). This file does
--     not reproduce those grants; see the grants file for the corrected,
--     least-privilege proposal.
--
-- EXECUTION GUARD
--   The DO block immediately below deliberately aborts any attempt to run
--   this file. Remove it ONLY inside a separately authorised local replay
--   validation phase, and only after reading the limitations above.
-- ============================================================================

DO $guard$
BEGIN
  RAISE EXCEPTION 'MIG-001 EXISTING-STATE BASELINE: execution guard active. This file is a captured snapshot of already-live PERSPECTIVES production state, not a migration to run. It has not been replay-validated. Do not remove this guard outside a separately authorised local replay validation phase. See the header comments in this file before proceeding.';
END;
$guard$;

-- ============================================================================
-- Extensions required by the schema below (application-relevant only; see
-- "Known limitations" above regarding platform-managed extensions omitted).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- ── Phase 1: Tables (columns only; constraints added in Phase 2) ──

CREATE TABLE public.specialties (
    code text NOT NULL,
    label text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.journals (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    issn text[] NOT NULL DEFAULT '{}'::text[],
    name text NOT NULL,
    name_canonical text NOT NULL,
    abbreviation text,
    aliases text[] NOT NULL DEFAULT '{}'::text[],
    jcr_year smallint,
    impact_factor numeric,
    h5_index integer,
    tier smallint,
    corpus text NOT NULL DEFAULT 'medicine'::text,
    default_specialty text,
    rss_url text,
    active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.subtopics (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    label text NOT NULL,
    slug text NOT NULL,
    specialty text NOT NULL,
    description text,
    keywords text[] NOT NULL DEFAULT '{}'::text[],
    mesh_terms text[] NOT NULL DEFAULT '{}'::text[],
    seeded boolean NOT NULL DEFAULT false,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.authors (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    full_name text NOT NULL,
    title text,
    full_title text,
    institution text,
    lab_name text,
    lab_description text,
    lab_url text,
    research_focus text,
    biography text,
    photo_url text,
    primary_specialty text,
    h_index integer,
    orcid_id text,
    openalex_id text,
    semantic_scholar_id text,
    citation_count integer,
    recent_paper_count integer,
    country text,
    researchgate_url text,
    recent_conferences jsonb NOT NULL DEFAULT '[]'::jsonb,
    recent_publications jsonb NOT NULL DEFAULT '[]'::jsonb,
    last_enriched_at timestamp with time zone,
    enrichment_source text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.article_processing_log (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    doi text,
    stage smallint,
    status text NOT NULL,
    rejection_reason text,
    stage_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.articles (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    headline text NOT NULL,
    original_title text,
    summary text NOT NULL,
    core_claim text,
    journal text NOT NULL,
    journal_impact_factor numeric,
    journal_id uuid,
    article_type text,
    publication_date date NOT NULL,
    tags text[] NOT NULL DEFAULT '{}'::text[],
    subtopic_slugs text[] NOT NULL DEFAULT '{}'::text[],
    author_id uuid,
    author_name text,
    author_institution text,
    co_authors jsonb NOT NULL DEFAULT '[]'::jsonb,
    doi text NOT NULL,
    original_url text,
    uncertainty_notes text,
    studies_referenced text[] NOT NULL DEFAULT '{}'::text[],
    discovered_via text,
    confidence_score numeric,
    embedding extensions.vector,
    processing_log_id uuid,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((((COALESCE(headline, ''::text) || ' '::text) || COALESCE(original_title, ''::text)) || ' '::text) || COALESCE(summary, ''::text)) || ' '::text) || COALESCE(core_claim, ''::text)))) STORED
);
-- NOTE: embedding is extensions.vector with an unspecified dimension (see
-- header limitations). Verify the true dimension before any replay.

CREATE TABLE public.article_specialties (
    article_id uuid NOT NULL,
    specialty_code text NOT NULL,
    confidence numeric NOT NULL DEFAULT 1.0
);

CREATE TABLE public.content_fingerprints (
    fingerprint bigint NOT NULL,
    article_id uuid NOT NULL,
    computed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.interaction_signals (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    article_id uuid,
    signal_type text NOT NULL,
    dwell_seconds numeric,
    context text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.user_preferences (
    user_id uuid NOT NULL,
    pinned_specialties text[] NOT NULL DEFAULT '{}'::text[],
    active_subtopics text[] NOT NULL DEFAULT '{}'::text[],
    followed_authors uuid[] NOT NULL DEFAULT '{}'::uuid[],
    liked_labs uuid[] NOT NULL DEFAULT '{}'::uuid[],
    saved_articles uuid[] NOT NULL DEFAULT '{}'::uuid[],
    onboarded boolean NOT NULL DEFAULT false,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.api_cache (
    cache_key text NOT NULL,
    cache_value jsonb NOT NULL,
    source text,
    fetched_at timestamp with time zone NOT NULL DEFAULT now(),
    expires_at timestamp with time zone
);

-- ── Phase 2: Constraints (primary keys, then unique, then foreign keys, then checks) ──

-- PRIMARY KEY constraints
ALTER TABLE public.api_cache ADD CONSTRAINT api_cache_pkey PRIMARY KEY (cache_key);
ALTER TABLE public.article_processing_log ADD CONSTRAINT article_processing_log_pkey PRIMARY KEY (id);
ALTER TABLE public.article_specialties ADD CONSTRAINT article_specialties_pkey PRIMARY KEY (article_id, specialty_code);
ALTER TABLE public.articles ADD CONSTRAINT articles_pkey PRIMARY KEY (id);
ALTER TABLE public.authors ADD CONSTRAINT authors_pkey PRIMARY KEY (id);
ALTER TABLE public.content_fingerprints ADD CONSTRAINT content_fingerprints_pkey PRIMARY KEY (fingerprint);
ALTER TABLE public.interaction_signals ADD CONSTRAINT interaction_signals_pkey PRIMARY KEY (id);
ALTER TABLE public.journals ADD CONSTRAINT journals_pkey PRIMARY KEY (id);
ALTER TABLE public.specialties ADD CONSTRAINT specialties_pkey PRIMARY KEY (code);
ALTER TABLE public.subtopics ADD CONSTRAINT subtopics_pkey PRIMARY KEY (id);
ALTER TABLE public.user_preferences ADD CONSTRAINT user_preferences_pkey PRIMARY KEY (user_id);

-- UNIQUE constraints
ALTER TABLE public.articles ADD CONSTRAINT articles_doi_key UNIQUE (doi);
ALTER TABLE public.authors ADD CONSTRAINT authors_orcid_id_key UNIQUE (orcid_id);
ALTER TABLE public.content_fingerprints ADD CONSTRAINT content_fingerprints_article_id_key UNIQUE (article_id);
ALTER TABLE public.journals ADD CONSTRAINT journals_name_key UNIQUE (name);
ALTER TABLE public.subtopics ADD CONSTRAINT subtopics_slug_key UNIQUE (slug);

-- FOREIGN KEY constraints
ALTER TABLE public.article_specialties ADD CONSTRAINT article_specialties_article_id_fkey FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE;
ALTER TABLE public.article_specialties ADD CONSTRAINT article_specialties_specialty_code_fkey FOREIGN KEY (specialty_code) REFERENCES specialties(code);
ALTER TABLE public.articles ADD CONSTRAINT articles_author_id_fkey FOREIGN KEY (author_id) REFERENCES authors(id);
ALTER TABLE public.articles ADD CONSTRAINT articles_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES journals(id);
ALTER TABLE public.articles ADD CONSTRAINT articles_processing_log_id_fkey FOREIGN KEY (processing_log_id) REFERENCES article_processing_log(id);
ALTER TABLE public.authors ADD CONSTRAINT authors_primary_specialty_fkey FOREIGN KEY (primary_specialty) REFERENCES specialties(code);
ALTER TABLE public.content_fingerprints ADD CONSTRAINT content_fingerprints_article_id_fkey FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE;
ALTER TABLE public.interaction_signals ADD CONSTRAINT interaction_signals_article_id_fkey FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE SET NULL;
ALTER TABLE public.interaction_signals ADD CONSTRAINT interaction_signals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.journals ADD CONSTRAINT journals_default_specialty_fkey FOREIGN KEY (default_specialty) REFERENCES specialties(code);
ALTER TABLE public.subtopics ADD CONSTRAINT subtopics_specialty_fkey FOREIGN KEY (specialty) REFERENCES specialties(code);
ALTER TABLE public.user_preferences ADD CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- CHECK constraints
ALTER TABLE public.article_processing_log ADD CONSTRAINT article_processing_log_status_check CHECK ((status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'rejected'::text, 'retry'::text])));
ALTER TABLE public.articles ADD CONSTRAINT articles_article_type_check CHECK ((article_type = ANY (ARRAY['Editorial'::text, 'Commentary'::text, 'Perspective'::text, 'Letter'::text, 'News'::text])));
ALTER TABLE public.interaction_signals ADD CONSTRAINT interaction_signals_signal_type_check CHECK ((signal_type = ANY (ARRAY['tap'::text, 'save'::text, 'share'::text, 'follow_author'::text, 'tag_tap'::text, 'specialty_pin'::text])));
ALTER TABLE public.journals ADD CONSTRAINT journals_tier_check CHECK ((tier = ANY (ARRAY[1, 2])));

-- ── Phase 3: Standalone indexes (constraint-backing indexes are created automatically by Phase 2) ──

CREATE INDEX idx_api_cache_expires ON public.api_cache USING btree (expires_at) WHERE (expires_at IS NOT NULL);
CREATE INDEX idx_processing_log_doi ON public.article_processing_log USING btree (doi) WHERE (doi IS NOT NULL);
CREATE INDEX idx_processing_log_stage ON public.article_processing_log USING btree (stage);
CREATE INDEX idx_processing_log_status ON public.article_processing_log USING btree (status);
CREATE INDEX idx_article_specialties_specialty ON public.article_specialties USING btree (specialty_code);
CREATE INDEX idx_articles_author_id ON public.articles USING btree (author_id);
CREATE INDEX idx_articles_created_at ON public.articles USING btree (created_at DESC);
CREATE INDEX idx_articles_fts ON public.articles USING gin (fts);
CREATE INDEX idx_articles_journal_id ON public.articles USING btree (journal_id) WHERE (journal_id IS NOT NULL);
CREATE INDEX idx_articles_publication_date ON public.articles USING btree (publication_date DESC);
CREATE INDEX idx_authors_full_name ON public.authors USING btree (full_name);
CREATE INDEX idx_authors_openalex ON public.authors USING btree (openalex_id) WHERE (openalex_id IS NOT NULL);
CREATE INDEX idx_authors_semantic ON public.authors USING btree (semantic_scholar_id) WHERE (semantic_scholar_id IS NOT NULL);
CREATE INDEX idx_authors_unenriched ON public.authors USING btree (created_at) WHERE (last_enriched_at IS NULL);
CREATE INDEX idx_signals_article_id ON public.interaction_signals USING btree (article_id);
CREATE INDEX idx_signals_type ON public.interaction_signals USING btree (signal_type);
CREATE INDEX idx_signals_user_article ON public.interaction_signals USING btree (user_id, article_id);
CREATE INDEX idx_signals_user_id ON public.interaction_signals USING btree (user_id);
CREATE INDEX idx_subtopics_specialty ON public.subtopics USING btree (specialty);

-- ── Phase 4: Functions ──

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
  BEGIN
    NEW.updated_at = now();
    RETURN NEW;
  END;
  $function$;

-- ── Phase 5: Triggers ──

CREATE TRIGGER trg_processing_log_updated_at BEFORE UPDATE ON public.article_processing_log FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_articles_updated_at BEFORE UPDATE ON public.articles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_journals_updated_at BEFORE UPDATE ON public.journals FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_user_preferences_updated_at BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Phase 6: Row Level Security ──

ALTER TABLE public.specialties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtopics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_processing_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_specialties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interaction_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_cache ENABLE ROW LEVEL SECURITY;

-- ── Phase 7: RLS Policies ──

CREATE POLICY processing_log_authenticated_read ON public.article_processing_log
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY article_specialties_authenticated_read ON public.article_specialties
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY articles_authenticated_read ON public.articles
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY authors_authenticated_read ON public.authors
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY signals_own_delete ON public.interaction_signals
  AS PERMISSIVE
  FOR DELETE
  TO public
  USING ((auth.uid() = user_id));

CREATE POLICY signals_own_insert ON public.interaction_signals
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((auth.uid() = user_id));

CREATE POLICY signals_own_read ON public.interaction_signals
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.uid() = user_id));

CREATE POLICY journals_authenticated_read ON public.journals
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY specialties_authenticated_read ON public.specialties
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY subtopics_authenticated_read ON public.subtopics
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.role() = 'authenticated'::text));

CREATE POLICY preferences_own_insert ON public.user_preferences
  AS PERMISSIVE
  FOR INSERT
  TO public
  WITH CHECK ((auth.uid() = user_id));

CREATE POLICY preferences_own_read ON public.user_preferences
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING ((auth.uid() = user_id));

CREATE POLICY preferences_own_update ON public.user_preferences
  AS PERMISSIVE
  FOR UPDATE
  TO public
  USING ((auth.uid() = user_id))
  WITH CHECK ((auth.uid() = user_id));

-- ============================================================================
-- End of captured existing-state baseline.
-- Data API grants are proposed separately in
-- supabase/grants/20260821_PROPOSED_DATA_API_GRANTS.sql — not here.
-- ============================================================================
