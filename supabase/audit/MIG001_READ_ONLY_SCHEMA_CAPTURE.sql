-- ============================================================================
-- MIG-001 — Read-Only Live Schema Metadata Capture
-- ============================================================================
-- What this is: a single, strictly read-only SELECT statement. It queries
-- only PostgreSQL system catalogues and information_schema. It never reads a
-- single row of application data, never creates or modifies any object, and
-- never grants or revokes anything.
--
-- What it returns: exactly one result row containing exactly one JSON object
-- (column name "mig001_schema_capture") describing the structure of the
-- `public` schema — tables, columns, constraints, indexes, views, functions,
-- triggers, RLS, policies, grants, extensions, sequences, enums, domains,
-- and publication membership. All arrays are deterministically ordered.
--
-- What it deliberately does NOT return: any application-table row, any row
-- count, any credential, any project URL, any key, any password.
--
-- Statements used: only SELECT and WITH, over pg_catalog / information_schema,
-- plus a small set of STABLE catalogue-inspection functions
-- (version(), now(), pg_get_constraintdef, pg_get_indexdef via pg_indexes,
-- pg_get_triggerdef, pg_get_functiondef, pg_get_userbyid, obj_description,
-- has_table_privilege, has_schema_privilege). None of these functions are
-- VOLATILE and none of them write anything or touch application data.
--
-- How to run: see the companion file MIG001_CAPTURE_INSTRUCTIONS.md in this
-- same directory. Paste this entire file into the Supabase SQL Editor and
-- run it once.
-- ============================================================================

WITH

schemas AS (
  SELECT jsonb_agg(nspname ORDER BY nspname) AS j
  FROM pg_namespace
  WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND nspname NOT LIKE 'pg_temp_%'
    AND nspname NOT LIKE 'pg_toast_temp_%'
),

extensions AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'name', e.extname,
      'schema', n.nspname,
      'version', e.extversion
    ) ORDER BY e.extname
  ) AS j
  FROM pg_extension e
  JOIN pg_namespace n ON n.oid = e.extnamespace
),

tables AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', c.relname,
      'kind', CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned_table' ELSE c.relkind::text END,
      'owner', pg_get_userbyid(c.relowner),
      'comment', obj_description(c.oid, 'pg_class'),
      'row_level_security_enabled', c.relrowsecurity,
      'row_level_security_forced', c.relforcerowsecurity
    ) ORDER BY c.relname
  ) AS j
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
),

columns AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', col.table_name,
      'column_name', col.column_name,
      'ordinal_position', col.ordinal_position,
      'data_type', col.data_type,
      'udt_schema', col.udt_schema,
      'udt_name', col.udt_name,
      'is_nullable', (col.is_nullable = 'YES'),
      'column_default', col.column_default,
      'character_maximum_length', col.character_maximum_length,
      'numeric_precision', col.numeric_precision,
      'numeric_scale', col.numeric_scale,
      'is_identity', (col.is_identity = 'YES'),
      'identity_generation', col.identity_generation,
      'is_generated', (col.is_generated = 'ALWAYS'),
      'generation_expression', col.generation_expression
    ) ORDER BY col.table_name, col.ordinal_position
  ) AS j
  FROM information_schema.columns col
  WHERE col.table_schema = 'public'
),

generated_columns AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', col.table_name,
      'column_name', col.column_name,
      'data_type', col.data_type,
      'generation_expression', col.generation_expression
    ) ORDER BY col.table_name, col.column_name
  ) AS j
  FROM information_schema.columns col
  WHERE col.table_schema = 'public' AND col.is_generated = 'ALWAYS'
),

sequences AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'sequence_name', s.sequence_name,
      'data_type', s.data_type,
      'start_value', s.start_value,
      'minimum_value', s.minimum_value,
      'maximum_value', s.maximum_value,
      'increment', s.increment,
      'cycle_option', s.cycle_option,
      'owned_by_table', own.table_name,
      'owned_by_column', own.column_name
    ) ORDER BY s.sequence_name
  ) AS j
  FROM information_schema.sequences s
  LEFT JOIN LATERAL (
    SELECT ct.relname AS table_name, a.attname AS column_name
    FROM pg_class sc
    JOIN pg_namespace sn ON sn.oid = sc.relnamespace AND sn.nspname = 'public'
    JOIN pg_depend d ON d.objid = sc.oid AND d.deptype = 'a'
    JOIN pg_class ct ON ct.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = ct.oid AND a.attnum = d.refobjsubid
    WHERE sc.relname = s.sequence_name AND sc.relkind = 'S'
    LIMIT 1
  ) own ON true
  WHERE s.sequence_schema = 'public'
),

enums AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'type_name', t.typname,
      'labels', (
        SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
        FROM pg_enum e
        WHERE e.enumtypid = t.oid
      )
    ) ORDER BY t.typname
  ) AS j
  FROM pg_type t
  JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public' AND t.typtype = 'e'
),

domains AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'domain_name', d.domain_name,
      'data_type', d.data_type,
      'udt_name', d.udt_name,
      'domain_default', d.domain_default,
      'character_maximum_length', d.character_maximum_length
    ) ORDER BY d.domain_name
  ) AS j
  FROM information_schema.domains d
  WHERE d.domain_schema = 'public'
),

constraints AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'constraint_name', con.conname,
      'table_name', rel.relname,
      'type', CASE con.contype
                WHEN 'p' THEN 'primary_key'
                WHEN 'u' THEN 'unique'
                WHEN 'f' THEN 'foreign_key'
                WHEN 'c' THEN 'check'
                WHEN 'x' THEN 'exclusion'
                ELSE con.contype::text
              END,
      'definition', pg_get_constraintdef(con.oid),
      'is_deferrable', con.condeferrable,
      'is_deferred_initially', con.condeferred,
      'is_validated', con.convalidated,
      'referenced_schema', fn.nspname,
      'referenced_table', frel.relname
    ) ORDER BY rel.relname, con.conname
  ) AS j
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = rel.relnamespace AND n.nspname = 'public'
  LEFT JOIN pg_class frel ON frel.oid = con.confrelid
  LEFT JOIN pg_namespace fn ON fn.oid = frel.relnamespace
),

indexes AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', tablename,
      'index_name', indexname,
      'definition', indexdef
    ) ORDER BY tablename, indexname
  ) AS j
  FROM pg_indexes
  WHERE schemaname = 'public'
),

views AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'view_name', table_name,
      'definition', view_definition
    ) ORDER BY table_name
  ) AS j
  FROM information_schema.views
  WHERE table_schema = 'public'
),

materialized_views AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'matview_name', matviewname,
      'definition', definition,
      'is_populated', ispopulated
    ) ORDER BY matviewname
  ) AS j
  FROM pg_matviews
  WHERE schemaname = 'public'
),

functions AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'function_name', p.proname,
      'arguments', pg_get_function_identity_arguments(p.oid),
      'return_type', pg_get_function_result(p.oid),
      'language', l.lanname,
      'volatility', CASE p.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' WHEN 'v' THEN 'volatile' END,
      'parallel_safety', CASE p.proparallel WHEN 's' THEN 'safe' WHEN 'r' THEN 'restricted' WHEN 'u' THEN 'unsafe' END,
      'is_security_definer', p.prosecdef,
      'owner', pg_get_userbyid(p.proowner),
      'configuration', to_jsonb(p.proconfig),
      'definition', pg_get_functiondef(p.oid)
    ) ORDER BY p.proname
  ) AS j
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  JOIN pg_language l ON l.oid = p.prolang
),

triggers AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'trigger_name', t.tgname,
      'table_name', rel.relname,
      'enabled_state', t.tgenabled,
      'definition', pg_get_triggerdef(t.oid)
    ) ORDER BY rel.relname, t.tgname
  ) AS j
  FROM pg_trigger t
  JOIN pg_class rel ON rel.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = rel.relnamespace AND n.nspname = 'public'
  WHERE NOT t.tgisinternal
),

policies AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'policy_name', policyname,
      'table_name', tablename,
      'permissive', permissive,
      'roles', to_jsonb(roles),
      'command', cmd,
      'using_expression', qual,
      'with_check_expression', with_check
    ) ORDER BY tablename, policyname
  ) AS j
  FROM pg_policies
  WHERE schemaname = 'public'
),

table_privileges AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', table_name,
      'grantee', grantee,
      'privilege_type', privilege_type,
      'is_grantable', (is_grantable = 'YES')
    ) ORDER BY table_name, grantee, privilege_type
  ) AS j
  FROM information_schema.table_privileges
  WHERE table_schema = 'public'
),

column_privileges AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', table_name,
      'column_name', column_name,
      'grantee', grantee,
      'privilege_type', privilege_type
    ) ORDER BY table_name, column_name, grantee, privilege_type
  ) AS j
  FROM information_schema.column_privileges
  WHERE table_schema = 'public'
),

routine_privileges AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'routine_name', routine_name,
      'grantee', grantee,
      'privilege_type', privilege_type
    ) ORDER BY routine_name, grantee, privilege_type
  ) AS j
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public'
),

-- Schema-level USAGE/CREATE on `public`, for the roles the Data API and the
-- worker actually use. has_schema_privilege() is STABLE and merely checks an
-- ACL; it does not modify anything. Assumes this runs on a Supabase project,
-- where anon / authenticated / service_role / postgres are standard roles.
schema_privileges AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'schema_name', 'public',
      'role', r.rolname,
      'has_usage', has_schema_privilege(r.rolname, 'public', 'USAGE'),
      'has_create', has_schema_privilege(r.rolname, 'public', 'CREATE')
    ) ORDER BY r.rolname
  ) AS j
  FROM pg_roles r
  WHERE r.rolname IN ('anon', 'authenticated', 'service_role', 'postgres')
),

-- Effective, currently-live Data API exposure per table, derived directly
-- from catalogue ACLs via has_table_privilege() (STABLE, read-only check).
-- This is what actually determines whether PostgREST/GraphQL can reach a
-- table today — independent of, and in addition to, RLS.
data_api_exposure AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', c.relname,
      'anon_select', has_table_privilege('anon', c.oid, 'SELECT'),
      'anon_insert', has_table_privilege('anon', c.oid, 'INSERT'),
      'anon_update', has_table_privilege('anon', c.oid, 'UPDATE'),
      'anon_delete', has_table_privilege('anon', c.oid, 'DELETE'),
      'authenticated_select', has_table_privilege('authenticated', c.oid, 'SELECT'),
      'authenticated_insert', has_table_privilege('authenticated', c.oid, 'INSERT'),
      'authenticated_update', has_table_privilege('authenticated', c.oid, 'UPDATE'),
      'authenticated_delete', has_table_privilege('authenticated', c.oid, 'DELETE'),
      'service_role_select', has_table_privilege('service_role', c.oid, 'SELECT')
    ) ORDER BY c.relname
  ) AS j
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
),

publication_membership AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'publication_name', p.pubname,
      'table_name', pt.tablename
    ) ORDER BY p.pubname, pt.tablename
  ) AS j
  FROM pg_publication p
  JOIN pg_publication_tables pt ON pt.pubname = p.pubname
  WHERE pt.schemaname = 'public'
),

table_names AS (
  SELECT jsonb_agg(c.relname ORDER BY c.relname) AS j
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
)

SELECT jsonb_build_object(
  'capture_format_version', '1.0',
  'query_executed_at', now(),
  'postgres_version', version(),
  'public_table_count', (SELECT jsonb_array_length(j) FROM table_names),
  'public_table_names', COALESCE((SELECT j FROM table_names), '[]'::jsonb),
  'schemas', COALESCE((SELECT j FROM schemas), '[]'::jsonb),
  'extensions', COALESCE((SELECT j FROM extensions), '[]'::jsonb),
  'tables', COALESCE((SELECT j FROM tables), '[]'::jsonb),
  'columns', COALESCE((SELECT j FROM columns), '[]'::jsonb),
  'generated_columns', COALESCE((SELECT j FROM generated_columns), '[]'::jsonb),
  'sequences', COALESCE((SELECT j FROM sequences), '[]'::jsonb),
  'enums', COALESCE((SELECT j FROM enums), '[]'::jsonb),
  'domains', COALESCE((SELECT j FROM domains), '[]'::jsonb),
  'constraints', COALESCE((SELECT j FROM constraints), '[]'::jsonb),
  'indexes', COALESCE((SELECT j FROM indexes), '[]'::jsonb),
  'views', COALESCE((SELECT j FROM views), '[]'::jsonb),
  'materialized_views', COALESCE((SELECT j FROM materialized_views), '[]'::jsonb),
  'functions', COALESCE((SELECT j FROM functions), '[]'::jsonb),
  'triggers', COALESCE((SELECT j FROM triggers), '[]'::jsonb),
  'policies', COALESCE((SELECT j FROM policies), '[]'::jsonb),
  'table_privileges', COALESCE((SELECT j FROM table_privileges), '[]'::jsonb),
  'column_privileges', COALESCE((SELECT j FROM column_privileges), '[]'::jsonb),
  'routine_privileges', COALESCE((SELECT j FROM routine_privileges), '[]'::jsonb),
  'schema_privileges', COALESCE((SELECT j FROM schema_privileges), '[]'::jsonb),
  'data_api_exposure', COALESCE((SELECT j FROM data_api_exposure), '[]'::jsonb),
  'publication_membership', COALESCE((SELECT j FROM publication_membership), '[]'::jsonb)
) AS mig001_schema_capture;
