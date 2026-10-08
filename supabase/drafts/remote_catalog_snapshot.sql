-- Read-only snapshot for comparing the live Supabase catalog with the local
-- SQL drafts. Run in the Supabase SQL Editor; this makes no database changes.

WITH public_relations AS (
  SELECT c.oid, c.relname, c.relkind, c.relowner, c.relrowsecurity, c.relforcerowsecurity,
         c.relacl
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
),
public_functions AS (
  SELECT p.oid, p.proname, p.proowner, p.prosecdef, p.provolatile, p.proconfig,
         p.proacl, l.lanname, pg_catalog.pg_get_function_identity_arguments(p.oid) AS args,
         pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'create_personal_workspace_for_user', 'handle_new_user',
      'is_workspace_member', 'workspace_role', 'set_updated_at', 'rls_auto_enable',
      'create_workspace_invitation', 'accept_workspace_invitation',
      'decline_workspace_invitation', 'revoke_workspace_invitation'
    )
),
table_privileges AS (
  SELECT r.relname AS table_name,
         CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS grantee,
         x.privilege_type,
         x.is_grantable
  FROM public_relations AS r
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(r.relacl, pg_catalog.acldefault('r', r.relowner))
  ) AS x
  LEFT JOIN pg_catalog.pg_roles AS grantee ON grantee.oid = x.grantee
),
function_privileges AS (
  SELECT p.proname || '(' || p.args || ')' AS function_signature,
         CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS grantee,
         x.privilege_type,
         x.is_grantable
  FROM public_functions AS p
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
  ) AS x
  LEFT JOIN pg_catalog.pg_roles AS grantee ON grantee.oid = x.grantee
)
SELECT pg_catalog.jsonb_pretty(pg_catalog.jsonb_build_object(
  'server_version', current_setting('server_version'),
  'migration_history_table_exists',
    pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NOT NULL,
  'public_tables_and_views', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', r.relname,
      'kind', r.relkind,
      'owner', pg_catalog.pg_get_userbyid(r.relowner),
      'rls_enabled', r.relrowsecurity,
      'rls_forced', r.relforcerowsecurity,
      'columns', (
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', a.attname,
          'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
          'not_null', a.attnotnull,
          'default', pg_catalog.pg_get_expr(d.adbin, d.adrelid)
        ) ORDER BY a.attnum)
        FROM pg_catalog.pg_attribute AS a
        LEFT JOIN pg_catalog.pg_attrdef AS d
          ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
      )
    ) ORDER BY r.relname)
    FROM public_relations AS r
  ), '[]'::jsonb),
  'constraints', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', c.conrelid::regclass::text,
      'name', c.conname,
      'type', c.contype,
      'definition', pg_catalog.pg_get_constraintdef(c.oid, true)
    ) ORDER BY c.conrelid::regclass::text, c.conname)
    FROM pg_catalog.pg_constraint AS c
    JOIN public_relations AS r ON r.oid = c.conrelid
  ), '[]'::jsonb),
  'indexes', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', schemaname || '.' || tablename,
      'name', indexname,
      'definition', indexdef
    ) ORDER BY tablename, indexname)
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
  ), '[]'::jsonb),
  'enum_types', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'type', t.typname,
      'labels', (
        SELECT pg_catalog.jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
        FROM pg_catalog.pg_enum AS e
        WHERE e.enumtypid = t.oid
      )
    ) ORDER BY t.typname)
    FROM pg_catalog.pg_type AS t
    JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e'
  ), '[]'::jsonb),
  'policies', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p)
      ORDER BY p.tablename, p.policyname)
    FROM pg_catalog.pg_policies AS p
    WHERE p.schemaname = 'public'
  ), '[]'::jsonb),
  'functions', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'signature', p.proname || '(' || p.args || ')',
      'owner', pg_catalog.pg_get_userbyid(p.proowner),
      'language', p.lanname,
      'security_definer', p.prosecdef,
      'volatility', p.provolatile,
      'settings', p.proconfig,
      'definition', p.definition
    ) ORDER BY p.proname, p.args)
    FROM public_functions AS p
  ), '[]'::jsonb),
  'table_privileges', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t)
      ORDER BY t.table_name, t.grantee, t.privilege_type)
    FROM table_privileges AS t
  ), '[]'::jsonb),
  'function_privileges', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(f)
      ORDER BY f.function_signature, f.grantee, f.privilege_type)
    FROM function_privileges AS f
  ), '[]'::jsonb),
  'triggers', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'table', c.relname,
      'name', t.tgname,
      'enabled', t.tgenabled,
      'definition', pg_catalog.pg_get_triggerdef(t.oid, true)
    ) ORDER BY n.nspname, c.relname, t.tgname)
    FROM pg_catalog.pg_trigger AS t
    JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE NOT t.tgisinternal
      AND ((n.nspname = 'public' AND c.relname IN (
        'profiles', 'workspaces', 'workspace_members', 'workspace_invitations'
      )) OR (n.nspname = 'auth' AND c.relname = 'users'))
  ), '[]'::jsonb),
  'event_triggers', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', e.evtname,
      'owner', pg_catalog.pg_get_userbyid(e.evtowner),
      'event', e.evtevent,
      'enabled', e.evtenabled,
      'definition', pg_catalog.format(
        'CREATE EVENT TRIGGER %I ON %s EXECUTE FUNCTION %I.%I()',
        e.evtname,
        e.evtevent,
        fn_schema.nspname,
        fn.proname
      )
    ) ORDER BY e.evtname)
    FROM pg_catalog.pg_event_trigger AS e
    JOIN pg_catalog.pg_proc AS fn ON fn.oid = e.evtfoid
    JOIN pg_catalog.pg_namespace AS fn_schema ON fn_schema.oid = fn.pronamespace
    WHERE e.evtname = 'ensure_rls'
  ), '[]'::jsonb),
  'default_privileges', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(d.defaclrole),
      'schema', n.nspname,
      'object_type', d.defaclobjtype,
      'grantee', CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END,
      'privileges', x.privilege_type,
      'grantable', x.is_grantable
    ) ORDER BY pg_catalog.pg_get_userbyid(d.defaclrole), n.nspname,
               d.defaclobjtype, x.grantee, x.privilege_type)
    FROM pg_catalog.pg_default_acl AS d
    LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) AS x
    LEFT JOIN pg_catalog.pg_roles AS grantee ON grantee.oid = x.grantee
    WHERE n.nspname = 'public' OR d.defaclnamespace = 0
  ), '[]'::jsonb)
)) AS remote_catalog_snapshot;
