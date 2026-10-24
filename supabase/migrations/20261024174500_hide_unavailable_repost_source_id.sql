-- Do not return the private source UUID when no safe snapshot exists.
CREATE OR REPLACE FUNCTION private.post_extras(p_post_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_shared uuid;
  v_scomment uuid;
  v_snapshot jsonb;
  v_card jsonb := null;
  v_ccard jsonb := null;
  v_orig public.community_posts;
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

  return jsonb_build_object(
    'views_count', (select coalesce(sum(v.view_count), 0)::bigint from public.post_views v where v.post_id = p_post_id),
    'viewers_count', (select count(*) from public.post_views v where v.post_id = p_post_id),
    'shares_count', (select count(*) from public.community_posts s where s.shared_post_id = p_post_id and s.status = 'active'),
    'viewer_has_shared', exists (select 1 from public.community_posts s where s.shared_post_id = p_post_id and s.author_id = p_viewer),
    'shared_post_id', case when v_card is not null and coalesce((v_card ->> 'can_open_original')::boolean, false) then v_shared else null end,
    'shared_post', v_card,
    'shared_post_can_open_original', coalesce((v_card ->> 'can_open_original')::boolean, false),
    'shared_comment_id', v_scomment,
    'shared_comment', v_ccard
  );
end
$function$
;
