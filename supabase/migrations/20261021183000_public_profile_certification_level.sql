-- Public-facing badge tier lookup; returns only the active level, not billing details.
create or replace function public.get_public_profile_certification_level(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_level text := 'none';
  v_legacy_verified boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_user_id is null then return 'none'; end if;

  select coalesce(up.is_verified, false)
    into v_legacy_verified
  from public.user_profiles up
  where up.user_id = p_user_id
    and up.deleted_at is null
    and lower(coalesce(up.account_status::text, 'active')) = 'active';

  if not found then return 'none'; end if;

  select case lower(ct.code)
           when 'premium' then 'premium'
           when 'pro' then 'pro'
           when 'basique' then 'basique'
           else 'none'
         end
    into v_level
  from public.user_certifications uc
  join public.certification_type ct on ct.id = uc.certification_type_id
  where uc.user_id = p_user_id
    and uc.status::text = 'active'
    and uc.issued_at <= now()
    and (uc.expires_at is null or uc.expires_at > now())
    and lower(ct.code) in ('basique', 'pro', 'premium')
  order by case lower(ct.code)
             when 'premium' then 3 when 'pro' then 2 when 'basique' then 1 else 0
           end desc
  limit 1;

  if coalesce(v_level, 'none') = 'none' and v_legacy_verified then return 'basique'; end if;
  return coalesce(v_level, 'none');
end;
$function$;

revoke all on function public.get_public_profile_certification_level(uuid) from public;
revoke all on function public.get_public_profile_certification_level(uuid) from anon;
grant execute on function public.get_public_profile_certification_level(uuid) to authenticated;
