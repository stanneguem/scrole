-- Keep the existing search implementation/cache, but put a mandatory visibility
-- gate in front of every returned event (including rows read from old cache entries).
alter function public.search_all(text) rename to search_all_internal;

revoke all on function public.search_all_internal(text) from public, anon, authenticated;

create or replace function public.search_all(p_query text)
returns table(
  category text,
  id uuid,
  title text,
  subtitle text,
  photo_url text,
  friend_count integer,
  is_certified boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select result.category, result.id, result.title, result.subtitle,
         result.photo_url, result.friend_count, result.is_certified
  from public.search_all_internal(p_query) as result
  where result.category <> 'event'
     or exists (
       select 1
       from public.events e
       where e.id = result.id
         and e.status in ('active', 'completed')
         and e.scheduled_deletion_at is null
     );
$$;

grant execute on function public.search_all(text) to authenticated;
