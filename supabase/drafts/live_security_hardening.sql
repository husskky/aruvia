-- Targeted hardening for functions confirmed by the 2026-09-24 live catalog
-- snapshot. Review, then run once in the Supabase SQL Editor.
-- This does not create or alter tables and is safe to rerun.

BEGIN;

-- Both SECURITY DEFINER signup functions use schema-qualified application
-- objects; pinning the path prevents public-schema object shadowing.
ALTER FUNCTION public.create_personal_workspace_for_user(uuid)
  SET search_path = '';
ALTER FUNCTION public.handle_new_user()
  SET search_path = '';

-- These functions are invoked by their existing triggers, not by API callers.
REVOKE ALL PRIVILEGES ON FUNCTION public.handle_new_user()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.rls_auto_enable()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.set_updated_at()
  FROM PUBLIC, anon, authenticated, service_role;

-- Restrict future objects created by postgres in public. Supabase-owned
-- supabase_admin defaults remain unchanged because that role is not writable
-- from this project's SQL Editor.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

-- Verify search paths and direct EXECUTE grants after the transaction.
SELECT
  p.oid::regprocedure AS function_signature,
  p.proconfig AS function_settings,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('create_personal_workspace_for_user', 'handle_new_user', 'rls_auto_enable', 'set_updated_at')
ORDER BY p.proname;

-- Verify postgres-owned defaults for future sequences and functions in public.
SELECT
  d.defaclobjtype AS object_type,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE r.rolname END AS grantee,
  x.privilege_type
FROM pg_catalog.pg_default_acl AS d
CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) AS x
LEFT JOIN pg_catalog.pg_roles AS r ON r.oid = x.grantee
WHERE d.defaclrole = 'postgres'::regrole
  AND d.defaclnamespace = 'public'::regnamespace
  AND d.defaclobjtype IN ('S', 'f')
ORDER BY d.defaclobjtype, grantee, x.privilege_type;
