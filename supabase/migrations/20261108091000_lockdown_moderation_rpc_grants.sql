revoke all on function public.report_content(text, uuid, uuid, text) from public, anon;
grant execute on function public.report_content(text, uuid, uuid, text) to authenticated;

revoke all on function public.get_platform_reports(text, integer, integer) from public, anon;
grant execute on function public.get_platform_reports(text, integer, integer) to authenticated;

revoke all on function public.resolve_platform_report(uuid, text, text) from public, anon;
grant execute on function public.resolve_platform_report(uuid, text, text) to authenticated;

revoke all on function public.get_community_feed(uuid, integer, text) from public, anon;
grant execute on function public.get_community_feed(uuid, integer, text) to authenticated;

revoke all on function public.get_post(uuid) from public, anon;
grant execute on function public.get_post(uuid) to authenticated;