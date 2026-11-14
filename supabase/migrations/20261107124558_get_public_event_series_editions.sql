create or replace function public.get_public_event_series_editions(p_event_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with target as (
    select coalesce(e.series_id, e.id) as series_id
    from public.events e
    where e.id = p_event_id
      and e.status in ('active', 'completed')
      and e.is_public = true
  ),
  editions as (
    select e.id, e.series_id, e.edition_number, e.name, e.slug,
           e.description, e.photo, e.starts_at, e.ends_at,
           e.status, e.is_public, e.is_virtual, e.address,
           e.city_id, e.country_id, e.creator_id, e.created_at
    from public.events e
    join target t on coalesce(e.series_id, e.id) = t.series_id
    where e.status in ('active', 'completed')
      and e.is_public = true
      and public.can_view_event(e.id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'series_id', series_id,
        'edition_number', edition_number,
        'name', name,
        'slug', slug,
        'description', description,
        'photo', photo,
        'starts_at', starts_at,
        'ends_at', ends_at,
        'status', status,
        'is_public', is_public,
        'is_virtual', is_virtual,
        'address', address,
        'city_id', city_id,
        'country_id', country_id,
        'creator_id', creator_id,
        'created_at', created_at
      ) order by edition_number desc, starts_at desc, created_at desc
    ),
    '[]'::jsonb
  )
  from editions;
$$;

revoke all on function public.get_public_event_series_editions(uuid) from public;
grant execute on function public.get_public_event_series_editions(uuid) to anon, authenticated;
