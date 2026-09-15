-- ============================================================================
-- MIG-004 — Read-Only Embedding Column Metadata Query
-- ============================================================================
-- What this is: a single, strictly read-only SELECT over PostgreSQL system
-- catalogues only. It resolves the one piece of live metadata MIG-001,
-- MIG-002, and MIG-003 all left unverified: the dimension (if any) of
-- public.articles.embedding, a pgvector `vector` column.
--
-- Why information_schema can't answer this: information_schema.columns
-- exposes character_maximum_length for varchar-like types and
-- numeric_precision/numeric_scale for numeric types, but has no field for
-- an extension type's typmod. pgvector's `vector` type registers a
-- typmodout function specifically so that pg_catalog.format_type() can
-- render it as "vector(N)" — that is the only reliable, purely-catalogue
-- way to recover N without reading any row.
--
-- What it deliberately does NOT do: it never reads a row of `articles`,
-- never calls vector_dims() against data, never exposes article content.
-- It reads only the column's type *definition* from pg_attribute /
-- pg_class / pg_namespace.
--
-- Result columns:
--   schema_name, table_name, column_name — confirm the exact target
--   base_type          — the resolved type name (expect "vector")
--   formatted_type     — format_type() output; renders as "vector(N)" when
--                         a dimension constraint exists, or bare "vector"
--                         if none was set at column-creation time
--   type_modifier      — the raw atttypmod integer, as a second,
--                         independent corroboration of formatted_type
--
-- Executed manually by the project owner on 2026-09-08 in the live
-- PERSPECTIVES Supabase SQL Editor. Result:
--   base_type = vector, formatted_type = vector(1536), type_modifier = 1536
-- Two independent fields agree exactly — LIVE_METADATA_VERIFIED.
-- ============================================================================

SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  a.attname AS column_name,
  a.atttypid::regtype::text AS base_type,
  pg_catalog.format_type(a.atttypid, a.atttypmod) AS formatted_type,
  a.atttypmod AS type_modifier
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c
  ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'articles'
  AND a.attname = 'embedding'
  AND a.attnum > 0
  AND NOT a.attisdropped;
