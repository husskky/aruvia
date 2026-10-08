-- Baseline reconstructed from the live Supabase catalog on 2026-09-24.
-- This migration describes the current app-owned schema and security posture.

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

CREATE TYPE public.workspace_member_role AS ENUM (
  'owner',
  'admin',
  'treasurer',
  'member',
  'viewer'
);

CREATE TYPE public.workspace_member_status AS ENUM (
  'active',
  'removed'
);

CREATE TYPE public.workspace_status AS ENUM (
  'active',
  'closed'
);

CREATE TYPE public.workspace_type AS ENUM (
  'personal',
  'organization'
);

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  display_name text,
  avatar_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id)
    REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE TABLE public.workspaces (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  type public.workspace_type NOT NULL,
  status public.workspace_status NOT NULL DEFAULT 'active',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  closed_at timestamp with time zone,
  CONSTRAINT workspaces_pkey PRIMARY KEY (id),
  CONSTRAINT closed_workspace_has_closed_at CHECK (
    (status = 'active' AND closed_at IS NULL)
    OR (status = 'closed' AND closed_at IS NOT NULL)
  ),
  CONSTRAINT workspace_name_not_empty CHECK (length(trim(name)) > 0)
);

CREATE TABLE public.workspace_members (
  workspace_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role public.workspace_member_role NOT NULL DEFAULT 'member',
  status public.workspace_member_status NOT NULL DEFAULT 'active',
  joined_at timestamp with time zone NOT NULL DEFAULT now(),
  removed_at timestamp with time zone,
  CONSTRAINT workspace_members_pkey PRIMARY KEY (workspace_id, user_id),
  CONSTRAINT workspace_members_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public.profiles (id) ON DELETE CASCADE,
  CONSTRAINT workspace_members_workspace_id_fkey FOREIGN KEY (workspace_id)
    REFERENCES public.workspaces (id) ON DELETE CASCADE,
  CONSTRAINT removed_member_has_removed_at CHECK (
    (status = 'active' AND removed_at IS NULL)
    OR (status = 'removed' AND removed_at IS NOT NULL)
  )
);

CREATE INDEX workspace_members_user_id_idx
  ON public.workspace_members USING btree (user_id);
CREATE INDEX workspace_members_workspace_id_idx
  ON public.workspace_members USING btree (workspace_id);
CREATE UNIQUE INDEX workspace_one_active_owner_idx
  ON public.workspace_members USING btree (workspace_id)
  WHERE role = 'owner' AND status = 'active';
CREATE INDEX workspaces_status_idx
  ON public.workspaces USING btree (status);
CREATE INDEX workspaces_type_idx
  ON public.workspaces USING btree (type);

CREATE OR REPLACE FUNCTION public.create_personal_workspace_for_user(target_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  new_workspace_id uuid;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_user_id::text, 0)
  );

  SELECT wm.workspace_id
    INTO new_workspace_id
  FROM public.workspace_members AS wm
  JOIN public.workspaces AS w ON w.id = wm.workspace_id
  WHERE wm.user_id = target_user_id
    AND wm.role = 'owner'
    AND wm.status = 'active'
    AND w.type = 'personal'
  LIMIT 1;

  IF new_workspace_id IS NOT NULL THEN
    RETURN new_workspace_id;
  END IF;

  INSERT INTO public.workspaces (name, type)
  VALUES ('Personal', 'personal')
  RETURNING id INTO new_workspace_id;

  INSERT INTO public.workspace_members (workspace_id, user_id, role, status)
  VALUES (new_workspace_id, target_user_id, 'owner', 'active');

  RETURN new_workspace_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data ->> 'full_name',
      NEW.raw_user_meta_data ->> 'name',
      NEW.email
    ),
    NEW.raw_user_meta_data ->> 'avatar_url'
  );

  PERFORM public.create_personal_workspace_for_user(NEW.id);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_workspace_member(target_workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_members AS wm
    WHERE wm.workspace_id = target_workspace_id
      AND wm.user_id = (SELECT auth.uid())
      AND wm.status = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table', 'partitioned table')
      AND schema_name = 'public'
  LOOP
    EXECUTE format(
      'ALTER TABLE %s ENABLE ROW LEVEL SECURITY',
      cmd.object_identity
    );

    RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.workspace_role(target_workspace_id uuid)
RETURNS public.workspace_member_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT wm.role
  FROM public.workspace_members AS wm
  WHERE wm.workspace_id = target_workspace_id
    AND wm.user_id = (SELECT auth.uid())
    AND wm.status = 'active'
  LIMIT 1;
$function$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid());
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());
CREATE POLICY "Members can view workspace members"
  ON public.workspace_members FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id));
CREATE POLICY "Members can view their workspaces"
  ON public.workspaces FOR SELECT TO authenticated
  USING (public.is_workspace_member(id));

REVOKE ALL PRIVILEGES ON TABLE
  public.profiles,
  public.workspaces,
  public.workspace_members
FROM anon, authenticated, service_role;

GRANT SELECT, UPDATE ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.workspaces, public.workspace_members TO authenticated;
GRANT ALL PRIVILEGES ON TABLE
  public.profiles,
  public.workspaces,
  public.workspace_members
TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.create_personal_workspace_for_user(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.handle_new_user()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.is_workspace_member(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.rls_auto_enable()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.set_updated_at()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.workspace_role(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.workspace_role(uuid)
  TO authenticated, service_role;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER workspaces_set_updated_at
  BEFORE UPDATE ON public.workspaces
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE EVENT TRIGGER ensure_rls
  ON ddl_command_end
  EXECUTE FUNCTION public.rls_auto_enable();
