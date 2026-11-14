-- Trigger-only functions must not be callable as ordinary RPCs.
revoke all on function public.e2ee_mark_group_rekey_required() from public, anon, authenticated;
revoke all on function public.e2ee_mark_device_groups_rekey_required() from public, anon, authenticated;
revoke all on function public.e2ee_mark_groups_rekey_on_key_package() from public, anon, authenticated;

-- Internal claim worker is callable only through the scope-checked wrapper.
revoke all on function private.e2ee_claim_key_package(uuid, uuid) from public, anon, authenticated;
revoke all on function private.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  from public, anon;
grant execute on function private.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  to authenticated;
