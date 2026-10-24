-- Current country is verified from a recent GPS fix on the server.
-- Raw latitude/longitude is deliberately not persisted.
create table if not exists public.user_country_verifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 country_id uuid references public.countries(id) on delete set null,
 city_id uuid references public.cities(id) on delete set null,
 country_code text,
 status text not null check(status in ('verified','rejected','expired','review_required')),
 method text not null default 'gps',
 accuracy_m numeric check(accuracy_m is null or accuracy_m >= 0),
 captured_at timestamptz not null,
 verified_at timestamptz,
 expires_at timestamptz,
 applied_at timestamptz,
 request_id uuid not null,
 rejection_reason text,
 created_at timestamptz not null default now(),
 constraint user_country_verifications_request_unique unique(user_id,request_id),
 constraint user_country_verifications_country_code_check check(country_code is null or country_code ~ '^[A-Z]{2}$')
);
create index if not exists user_country_verifications_user_latest_idx on public.user_country_verifications(user_id,created_at desc);
create index if not exists user_country_verifications_valid_idx on public.user_country_verifications(user_id,expires_at desc) where status='verified';
alter table public.user_country_verifications enable row level security;
revoke all on table public.user_country_verifications from anon,authenticated;
grant all on table public.user_country_verifications to service_role;

create or replace function public.guard_profile_current_country()
returns trigger language plpgsql set search_path='' as $$
begin
 if (new.country_id is distinct from old.country_id or new.city_id is distinct from old.city_id or new.location_updated_at is distinct from old.location_updated_at)
    and coalesce(current_setting('scrole.country_verification_update',true),'') <> 'on' then
  raise exception 'current_country_requires_server_verification' using errcode='42501';
 end if;
 return new;
end; $$;
drop trigger if exists guard_profile_current_country on public.user_profiles;
create trigger guard_profile_current_country before update of country_id,city_id,location_updated_at on public.user_profiles for each row execute function public.guard_profile_current_country();

drop function if exists public.apply_verified_current_country(uuid,uuid);
create function public.apply_verified_current_country(p_user_id uuid,p_verification_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_verification public.user_country_verifications%rowtype;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role' then
  raise exception 'service_role_required' using errcode='42501';
 end if;
 select * into v_verification from public.user_country_verifications
 where id=p_verification_id and user_id=p_user_id and status='verified' and expires_at>now() for update;
 if not found then raise exception 'valid_country_verification_not_found' using errcode='42501'; end if;
 if v_verification.city_id is not null and not exists(select 1 from public.cities c where c.id=v_verification.city_id and c.country_id=v_verification.country_id and c.is_active is true) then
  raise exception 'city_does_not_belong_to_verified_country' using errcode='22023';
 end if;
 perform set_config('scrole.country_verification_update','on',true);
 update public.user_profiles set country_id=v_verification.country_id,city_id=v_verification.city_id,location_updated_at=v_verification.verified_at,updated_at=now() where user_id=p_user_id;
 if not found then raise exception 'user_profile_not_found' using errcode='P0002'; end if;
 update public.user_country_verifications set applied_at=now() where id=p_verification_id;
 return jsonb_build_object('country_id',v_verification.country_id,'city_id',v_verification.city_id,'verified_at',v_verification.verified_at,'expires_at',v_verification.expires_at);
end; $$;
revoke all on function public.apply_verified_current_country(uuid,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_current_country(uuid,uuid) to service_role;
