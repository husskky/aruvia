-- Workspace invitation foundation.
-- Invitations are created and accepted through narrowly granted functions.
-- The caller generates a random token and submits only its SHA-256 hash here.

CREATE TYPE public.workspace_invitation_status AS ENUM (
  'pending',
  'accepted',
  'declined',
  'expired',
  'revoked'
);

CREATE TABLE public.workspace_invitations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  email text NOT NULL,
  role public.workspace_member_role NOT NULL,
  invited_by uuid NOT NULL,
  token_hash text NOT NULL,
  status public.workspace_invitation_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  responded_at timestamptz,
  CONSTRAINT workspace_invitations_pkey PRIMARY KEY (id),
  CONSTRAINT workspace_invitations_workspace_id_fkey
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces (id) ON DELETE CASCADE,
  CONSTRAINT workspace_invitations_invited_by_fkey
    FOREIGN KEY (invited_by) REFERENCES public.profiles (id) ON DELETE CASCADE,
  CONSTRAINT workspace_invitations_email_normalized
    CHECK (email = lower(btrim(email)) AND length(email) > 3),
  CONSTRAINT workspace_invitations_role_not_owner
    CHECK (role <> 'owner'),
  CONSTRAINT workspace_invitations_token_hash_sha256
    CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT workspace_invitations_expiry_after_creation
    CHECK (expires_at > created_at),
  CONSTRAINT workspace_invitations_response_timestamp
    CHECK (
      (status = 'pending' AND responded_at IS NULL)
      OR (status <> 'pending' AND responded_at IS NOT NULL)
    )
);

CREATE INDEX workspace_invitations_workspace_id_idx
  ON public.workspace_invitations USING btree (workspace_id);
CREATE UNIQUE INDEX workspace_invitations_token_hash_idx
  ON public.workspace_invitations USING btree (token_hash);
CREATE UNIQUE INDEX workspace_invitations_one_pending_email_idx
  ON public.workspace_invitations USING btree (workspace_id, email)
  WHERE status = 'pending';

ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Workspace managers and invitees can view invitations"
  ON public.workspace_invitations FOR SELECT TO authenticated
  USING (
    public.workspace_role(workspace_id) IN ('owner', 'admin')
    OR email = lower(COALESCE((SELECT auth.jwt() ->> 'email'), ''))
  );

REVOKE ALL PRIVILEGES ON TABLE public.workspace_invitations
  FROM anon, authenticated, service_role;
GRANT SELECT (
  id,
  workspace_id,
  email,
  role,
  invited_by,
  status,
  created_at,
  expires_at,
  responded_at
) ON TABLE public.workspace_invitations TO authenticated;
REVOKE ALL PRIVILEGES ON TYPE public.workspace_invitation_status
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON TYPE public.workspace_invitation_status TO authenticated;

CREATE OR REPLACE FUNCTION public.create_workspace_invitation(
  target_workspace_id uuid,
  target_email text,
  target_role public.workspace_member_role,
  target_token_hash text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  normalized_email text := lower(btrim(target_email));
  invitation_id uuid;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF target_workspace_id IS NULL
    OR target_email IS NULL
    OR target_role IS NULL
    OR target_token_hash IS NULL THEN
    RAISE EXCEPTION 'Workspace, email, role, and token hash are required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.workspace_members AS wm
  WHERE wm.workspace_id = target_workspace_id
    AND wm.user_id = actor_id
    AND wm.status = 'active'
    AND wm.role IN ('owner', 'admin')
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only workspace owners and admins can invite members'
      USING ERRCODE = '42501';
  END IF;

  IF target_role = 'owner' THEN
    RAISE EXCEPTION 'Invitations cannot grant the owner role'
      USING ERRCODE = '22023';
  END IF;

  IF normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'A valid email address is required' USING ERRCODE = '22023';
  END IF;

  IF target_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'A SHA-256 token hash is required' USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.workspaces AS w
  WHERE w.id = target_workspace_id
    AND w.type = 'organization'
    AND w.status = 'active'
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitations require an active organization workspace'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.workspace_invitations AS wi
  SET status = 'expired', responded_at = now()
  WHERE wi.workspace_id = target_workspace_id
    AND wi.email = normalized_email
    AND wi.status = 'pending'
    AND wi.expires_at <= now();

  IF EXISTS (
    SELECT 1
    FROM public.workspace_members AS wm
    WHERE wm.workspace_id = target_workspace_id
      AND wm.user_id = (
        SELECT u.id FROM auth.users AS u WHERE lower(u.email) = normalized_email
      )
      AND wm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'This user is already an active workspace member'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.workspace_invitations (
    workspace_id, email, role, invited_by, token_hash
  )
  VALUES (
    target_workspace_id, normalized_email, target_role, actor_id, target_token_hash
  )
  RETURNING id INTO invitation_id;

  RETURN invitation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(target_token_hash text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  actor_email text;
  invitation public.workspace_invitations%ROWTYPE;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF target_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Invalid invitation token' USING ERRCODE = '22023';
  END IF;

  SELECT lower(u.email)
  INTO actor_email
  FROM auth.users AS u
  WHERE u.id = actor_id
    AND u.email_confirmed_at IS NOT NULL;

  IF actor_email IS NULL THEN
    RAISE EXCEPTION 'A confirmed email address is required to accept an invitation'
      USING ERRCODE = '42501';
  END IF;

  SELECT wi.*
  INTO invitation
  FROM public.workspace_invitations AS wi
  WHERE wi.token_hash = target_token_hash
  FOR UPDATE;

  IF NOT FOUND
    OR invitation.status <> 'pending'
    OR invitation.expires_at <= now()
    OR invitation.email <> actor_email THEN
    RAISE EXCEPTION 'Invitation is invalid, expired, or addressed to another user'
      USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.workspaces AS w
  WHERE w.id = invitation.workspace_id
    AND w.type = 'organization'
    AND w.status = 'active'
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The invited workspace is no longer active'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      invitation.workspace_id::text || ':' || actor_id::text,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.workspace_members AS wm
    WHERE wm.workspace_id = invitation.workspace_id
      AND wm.user_id = actor_id
      AND wm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are already an active workspace member'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.workspace_members (
    workspace_id, user_id, role, status, joined_at, removed_at
  )
  VALUES (
    invitation.workspace_id, actor_id, invitation.role, 'active', now(), NULL
  )
  ON CONFLICT (workspace_id, user_id) DO UPDATE
  SET role = EXCLUDED.role,
      status = 'active',
      joined_at = now(),
      removed_at = NULL;

  UPDATE public.workspace_invitations
  SET status = 'accepted', responded_at = now()
  WHERE id = invitation.id;

  RETURN invitation.workspace_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_workspace_invitation(target_invitation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  invitation public.workspace_invitations%ROWTYPE;
BEGIN
  SELECT wi.*
  INTO invitation
  FROM public.workspace_invitations AS wi
  WHERE wi.id = target_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM 1
  FROM public.workspace_members AS wm
  WHERE wm.workspace_id = invitation.workspace_id
    AND wm.user_id = auth.uid()
    AND wm.status = 'active'
    AND wm.role IN ('owner', 'admin')
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only workspace owners and admins can revoke invitations'
      USING ERRCODE = '42501';
  END IF;

  IF invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending invitations can be revoked' USING ERRCODE = '22023';
  END IF;

  UPDATE public.workspace_invitations
  SET status = 'revoked', responded_at = now()
  WHERE id = invitation.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decline_workspace_invitation(target_token_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  actor_email text;
  invitation public.workspace_invitations%ROWTYPE;
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT lower(u.email)
  INTO actor_email
  FROM auth.users AS u
  WHERE u.id = actor_id
    AND u.email_confirmed_at IS NOT NULL;

  SELECT wi.*
  INTO invitation
  FROM public.workspace_invitations AS wi
  WHERE wi.token_hash = target_token_hash
  FOR UPDATE;

  IF NOT FOUND
    OR invitation.status <> 'pending'
    OR invitation.expires_at <= now()
    OR actor_email IS NULL
    OR invitation.email <> actor_email THEN
    RAISE EXCEPTION 'Invitation is invalid, expired, or addressed to another user'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.workspace_invitations
  SET status = 'declined', responded_at = now()
  WHERE id = invitation.id;
END;
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.create_workspace_invitation(
  uuid, text, public.workspace_member_role, text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.accept_workspace_invitation(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.revoke_workspace_invitation(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.decline_workspace_invitation(text)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.create_workspace_invitation(
  uuid, text, public.workspace_member_role, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_workspace_invitation(text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_workspace_invitation(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_workspace_invitation(text)
  TO authenticated;
