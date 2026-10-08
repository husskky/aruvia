# Unverified database SQL drafts

These files are reconstructions from catalog output and have not been validated
against the live database or replayed locally. They are outside
`supabase/migrations` so `supabase db push` cannot apply them accidentally.

Do not move them into `supabase/migrations` or apply them until a schema-only
dump of the remote database has been compared with the baseline. The baseline
creates objects that already exist remotely; applying it to that database
would fail or cause damage.

The invitation SQL depends on the baseline and also requires local PostgreSQL
replay before it can be considered ready. Docker is currently unavailable on
this machine, so both validation steps are pending.

## Confirmed remote changes (2026-09-24)

The project owner ran `live_security_hardening.sql` in the Supabase SQL Editor.
The returned verification rows confirmed:

- `create_personal_workspace_for_user` and `handle_new_user` use an empty
  `search_path` and are not executable by `anon`, `authenticated`, or
  `service_role`.
- `rls_auto_enable` uses `search_path=pg_catalog` and is not executable by API
  roles.
- `set_updated_at` is not executable by API roles.
- `postgres` defaults in `public` grant sequence and function privileges only
  to `postgres`.

The remote catalog has no `supabase_migrations.schema_migrations` table. The
`supabase_admin` default privileges remain broad because the project owner
received a permission error when attempting to change them.

The linked CLI check (`supabase migration list --linked`, 2026-09-24) returned
an empty migration list. `supabase db pull` is still pending because Docker
cannot start on this machine.
