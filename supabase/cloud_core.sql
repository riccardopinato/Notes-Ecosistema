-- Notes Ecosistema 0.26A — Cloud Core
-- Eseguire sul progetto Supabase dell'app. Nessuna service/secret key deve entrare nell'APK.

create schema if not exists private;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null default '',
    display_name text not null default '',
    updated_at timestamptz not null default now(),
    constraint profiles_display_name_len check (char_length(display_name) <= 80)
);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
grant select, insert, update on public.profiles to authenticated;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles for select to authenticated
using ((select auth.uid()) = id);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert to authenticated
with check ((select auth.uid()) = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create table if not exists public.workspace_records (
    id uuid primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    visibility text not null default 'PRIVATE',
    space_id uuid null,
    payload jsonb not null,
    client_updated_at bigint not null,
    deleted_at bigint null,
    revision bigint not null default 1,
    updated_by uuid not null references auth.users(id),
    updated_at timestamptz not null default now(),
    constraint workspace_visibility check (visibility in ('PRIVATE', 'SHARED')),
    constraint workspace_private_shape check (
        (visibility = 'PRIVATE' and space_id is null) or visibility = 'SHARED'
    ),
    constraint workspace_payload_size check (octet_length(payload::text) <= 393216),
    constraint workspace_client_updated_at check (client_updated_at >= 0),
    constraint workspace_deleted_at check (deleted_at is null or deleted_at >= 0),
    constraint workspace_revision check (revision > 0)
);

create index if not exists workspace_records_owner_visibility_idx
    on public.workspace_records(owner_id, visibility, updated_at desc);
create index if not exists workspace_records_space_idx
    on public.workspace_records(space_id) where space_id is not null;

alter table public.workspace_records enable row level security;
revoke all on public.workspace_records from anon;
grant select, insert, update, delete on public.workspace_records to authenticated;

drop policy if exists workspace_private_select on public.workspace_records;
create policy workspace_private_select on public.workspace_records for select to authenticated
using (
    visibility = 'PRIVATE'
    and space_id is null
    and owner_id = (select auth.uid())
);

drop policy if exists workspace_private_insert on public.workspace_records;
create policy workspace_private_insert on public.workspace_records for insert to authenticated
with check (
    visibility = 'PRIVATE'
    and space_id is null
    and owner_id = (select auth.uid())
    and updated_by = (select auth.uid())
);

drop policy if exists workspace_private_update on public.workspace_records;
create policy workspace_private_update on public.workspace_records for update to authenticated
using (
    visibility = 'PRIVATE'
    and space_id is null
    and owner_id = (select auth.uid())
)
with check (
    visibility = 'PRIVATE'
    and space_id is null
    and owner_id = (select auth.uid())
    and updated_by = (select auth.uid())
);

drop policy if exists workspace_private_delete on public.workspace_records;
create policy workspace_private_delete on public.workspace_records for delete to authenticated
using (
    visibility = 'PRIVATE'
    and space_id is null
    and owner_id = (select auth.uid())
);

create or replace function private.apply_workspace_record(p_record jsonb, p_base_revision bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
    v_user uuid := auth.uid();
    v_id uuid;
    v_current public.workspace_records%rowtype;
    v_next public.workspace_records%rowtype;
begin
    if v_user is null then
        raise exception 'authentication required' using errcode = '42501';
    end if;

    v_id := (p_record->>'id')::uuid;
    if coalesce(p_record->>'visibility', '') <> 'PRIVATE' or nullif(p_record->>'space_id', '') is not null then
        raise exception '0.26A accepts private records only' using errcode = '22023';
    end if;
    if p_base_revision < 0 then
        raise exception 'invalid base revision' using errcode = '22023';
    end if;

    select * into v_current from public.workspace_records where id = v_id for update;

    if not found then
        if p_base_revision <> 0 then
            return jsonb_build_object('applied', false, 'record', null);
        end if;
        insert into public.workspace_records(
            id, owner_id, visibility, space_id, payload, client_updated_at, deleted_at, revision, updated_by
        ) values (
            v_id,
            v_user,
            'PRIVATE',
            null,
            p_record->'payload',
            (p_record->>'client_updated_at')::bigint,
            nullif(p_record->>'deleted_at', '')::bigint,
            1,
            v_user
        ) returning * into v_next;
        return jsonb_build_object('applied', true, 'record', to_jsonb(v_next) - 'owner_id' - 'visibility' - 'space_id' - 'updated_at');
    end if;

    if v_current.owner_id <> v_user or v_current.visibility <> 'PRIVATE' or v_current.space_id is not null then
        raise exception 'record not owned by caller' using errcode = '42501';
    end if;

    if v_current.revision <> p_base_revision then
        return jsonb_build_object('applied', false, 'record', to_jsonb(v_current) - 'owner_id' - 'visibility' - 'space_id' - 'updated_at');
    end if;

    update public.workspace_records
    set payload = p_record->'payload',
        client_updated_at = (p_record->>'client_updated_at')::bigint,
        deleted_at = nullif(p_record->>'deleted_at', '')::bigint,
        revision = revision + 1,
        updated_by = v_user,
        updated_at = now()
    where id = v_id
    returning * into v_next;

    return jsonb_build_object('applied', true, 'record', to_jsonb(v_next) - 'owner_id' - 'visibility' - 'space_id' - 'updated_at');
end;
$$;

revoke all on function private.apply_workspace_record(jsonb, bigint) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.apply_workspace_record(jsonb, bigint) to authenticated;

create or replace function public.apply_workspace_record(p_record jsonb, p_base_revision bigint)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, public, private
as $$
    select private.apply_workspace_record(p_record, p_base_revision);
$$;

revoke all on function public.apply_workspace_record(jsonb, bigint) from public, anon;
grant execute on function public.apply_workspace_record(jsonb, bigint) to authenticated;
