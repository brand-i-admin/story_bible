create table if not exists public.user_saved_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

create index if not exists idx_user_saved_events_user_created
  on public.user_saved_events (user_id, created_at desc);

grant select, insert, delete on table public.user_saved_events to authenticated;

alter table public.user_saved_events enable row level security;

drop policy if exists user_saved_events_read_own on public.user_saved_events;
create policy user_saved_events_read_own on public.user_saved_events
for select using (auth.uid() = user_id);

drop policy if exists user_saved_events_insert_own on public.user_saved_events;
create policy user_saved_events_insert_own on public.user_saved_events
for insert with check (auth.uid() = user_id);

drop policy if exists user_saved_events_delete_own on public.user_saved_events;
create policy user_saved_events_delete_own on public.user_saved_events
for delete using (auth.uid() = user_id);
