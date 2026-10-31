-- Bug-report delivery and private Cloudflare R2 screenshot support.
-- Safe to apply more than once; no existing reports or media are deleted.

alter table public.bug_reports
  add column if not exists screenshot_object_key text,
  add column if not exists admin_note text,
  add column if not exists resolved_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists bug_reports_status_created_at_idx
  on public.bug_reports (status, created_at desc);

create index if not exists bug_reports_user_created_at_idx
  on public.bug_reports (user_id, created_at desc);

alter table public.bug_reports enable row level security;

drop policy if exists "Administrateurs voient les rapports de bugs" on public.bug_reports;
create policy "Administrateurs voient les rapports de bugs"
  on public.bug_reports
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_permissions_for_current_user() p(permission)
      where p.permission in ('reports.view', 'bug_reports.view')
    )
  );

drop policy if exists "Administrateurs mettent à jour les rapports de bugs" on public.bug_reports;
create policy "Administrateurs mettent à jour les rapports de bugs"
  on public.bug_reports
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.admin_permissions_for_current_user() p(permission)
      where p.permission in ('reports.resolve', 'bug_reports.manage')
    )
  )
  with check (
    exists (
      select 1
      from public.admin_permissions_for_current_user() p(permission)
      where p.permission in ('reports.resolve', 'bug_reports.manage')
    )
  );
