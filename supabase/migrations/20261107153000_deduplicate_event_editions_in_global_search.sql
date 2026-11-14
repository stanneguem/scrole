-- Return a single searchable edition for each event series.
-- Prefer the edition currently in progress, then the nearest upcoming edition.
-- If no active/upcoming edition exists, return the most recently completed edition.
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
volatile
security definer
set search_path to 'public'
as $function$
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
         and e.id = (
           select preferred.id
           from public.events preferred
           where coalesce(preferred.series_id, preferred.id)
                 = coalesce(e.series_id, e.id)
             and preferred.status in ('active', 'completed')
             and preferred.scheduled_deletion_at is null
           order by
             case
               when preferred.status = 'active'
                and preferred.starts_at <= now()
                and preferred.ends_at >= now() then 0
               when preferred.status = 'active'
                and preferred.starts_at > now() then 1
               when preferred.status = 'completed' then 2
               else 3
             end,
             case when preferred.status = 'completed'
               then preferred.ends_at end desc nulls last,
             case when preferred.status = 'active'
               then preferred.starts_at end asc nulls last,
             preferred.edition_number desc nulls last,
             preferred.created_at desc
           limit 1
         )
     );
$function$;
