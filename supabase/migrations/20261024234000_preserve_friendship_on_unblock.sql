begin;

-- Blocking a user must prevent interaction without destroying the underlying
-- follow edges. Friendship is derived from reciprocal rows in user_follows;
-- deleting those rows here made a block/unblock permanently end friendships.
-- Relationship/profile/feed RPCs already hide blocked users while the block is
-- active via private.users_blocked(). Keep pending requests cleared on block,
-- but preserve user_follows so the friendship returns after unblock.

create or replace function private.on_user_blocked()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.statut then
    -- Deliberately do NOT delete from public.user_follows.
    -- Those rows encode the existing relationship and must survive a block.
    delete from public.follow_requests
    where (requester_id = new.bloqueur_id and target_id = new.bloque_id)
       or (requester_id = new.bloque_id and target_id = new.bloqueur_id);

    perform private.broadcast_relationship(new.bloqueur_id, new.bloque_id);
  end if;

  return new;
end;
$function$;

-- Existing trigger trg_on_user_blocked continues to invoke this function on
-- block inserts/updates. No remote database migration is applied by this file.

commit;
