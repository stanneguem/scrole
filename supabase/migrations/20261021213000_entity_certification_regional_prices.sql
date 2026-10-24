create table if not exists public.scrole_entity_certification_prices (
  id uuid primary key default gen_random_uuid(),
  pricing_group text not null unique,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.scrole_entity_certification_prices (pricing_group, amount, currency, active)
values
  ('Afrique centrale', 1500, 'XAF', true),
  ('Afrique', 2000, 'XAF', true),
  ('Hors Afrique', 3, 'EUR', true)
on conflict (pricing_group) do update
set amount = excluded.amount,
    currency = excluded.currency,
    active = excluded.active,
    updated_at = now();

alter table public.scrole_entity_certification_prices enable row level security;
revoke all on public.scrole_entity_certification_prices from anon, authenticated;
drop policy if exists "Authenticated users can read active entity certification prices" on public.scrole_entity_certification_prices;
create policy "Authenticated users can read active entity certification prices"
on public.scrole_entity_certification_prices
for select to authenticated
using (active = true);
grant select on public.scrole_entity_certification_prices to authenticated;