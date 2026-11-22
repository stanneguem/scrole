-- Event posts are available only to users with a validated presence check-in.
create or replace function public.get_my_valid_checked_in_events()
returns table(id uuid, name text, photo text, starts_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct e.id, e.name, e.photo, e.starts_at
  from public.events e
  join public.event_checkins ec on ec.event_id = e.id
  where ec.user_id = auth.uid()
    and ec.status = 'valid'
    and ec.activity_id is null
  order by e.starts_at desc;
$$;

revoke all on function public.get_my_valid_checked_in_events() from public, anon;
grant execute on function public.get_my_valid_checked_in_events() to authenticated;

create or replace function public.link_post_to_checked_in_event(p_post_id uuid, p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.community_posts p
    where p.id = p_post_id and p.author_id = v_user_id and p.deleted_at is null
  ) then
    raise exception 'post_not_owned_by_user' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.event_checkins ec
    where ec.event_id = p_event_id and ec.user_id = v_user_id
      and ec.status = 'valid' and ec.activity_id is null
  ) then
    raise exception 'validated_event_checkin_required' using errcode = '42501';
  end if;

  insert into public.event_post_links(event_id, post_id, created_by)
  values (p_event_id, p_post_id, v_user_id)
  on conflict (event_id, post_id) do nothing;
end;
$$;

revoke all on function public.link_post_to_checked_in_event(uuid, uuid) from public, anon;
grant execute on function public.link_post_to_checked_in_event(uuid, uuid) to authenticated;

create or replace function private.post_extras(p_post_id uuid, p_viewer uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_shared uuid;
  v_scomment uuid;
  v_snapshot jsonb;
  v_card jsonb := null;
  v_ccard jsonb := null;
  v_orig public.community_posts;
  v_event jsonb := null;
begin
  select shared_post_id, shared_comment_id, shared_post_snapshot
    into v_shared, v_scomment, v_snapshot
  from public.community_posts where id = p_post_id;

  if v_shared is not null then
    select * into v_orig from public.community_posts where id = v_shared;
    if found and v_orig.status = 'active'
       and private.story_can_open_original(v_shared, p_viewer) then
      v_card := private.post_item(v_shared, p_viewer) || jsonb_build_object('available', true, 'can_open_original', true);
    elsif v_snapshot is not null then
      v_card := private.redact_shared_snapshot(v_snapshot) || jsonb_build_object('available', true, 'can_open_original', false);
    else
      v_card := jsonb_build_object('available', false, 'can_open_original', false);
    end if;
  end if;

  if v_scomment is not null then
    v_ccard := private.comment_card(v_scomment, p_viewer);
  end if;

  select jsonb_build_object(
    'id', e.id,
    'name', e.name,
    'photo', e.photo,
    'starts_at', e.starts_at,
    'city', c.nom
  )
  into v_event
  from public.event_post_links l
  join public.events e on e.id = l.event_id
  left join public.cities c on c.id = e.city_id
  where l.post_id = p_post_id
  order by l.created_at desc
  limit 1;

  return jsonb_build_object(
    'views_count', (select coalesce(sum(v.view_count), 0)::bigint from public.post_views v where v.post_id = p_post_id),
    'viewers_count', (select count(*) from public.post_views v where v.post_id = p_post_id),
    'shares_count', (select count(*) from public.community_posts s where s.shared_post_id = p_post_id and s.status = 'active'),
    'viewer_has_shared', exists (select 1 from public.community_posts s where s.shared_post_id = p_post_id and s.author_id = p_viewer),
    'shared_post_id', case when v_card is not null and coalesce((v_card ->> 'can_open_original')::boolean, false) then v_shared else null end,
    'shared_post', v_card,
    'shared_post_can_open_original', coalesce((v_card ->> 'can_open_original')::boolean, false),
    'shared_comment_id', v_scomment,
    'shared_comment', v_ccard,
    'event', v_event
  );
end
$$;
