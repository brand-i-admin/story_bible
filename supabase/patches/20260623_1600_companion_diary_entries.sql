begin;

create table if not exists public.user_companion_diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  title text not null check (
    char_length(btrim(title)) > 0 and char_length(title) <= 80
  ),
  body text not null check (
    char_length(btrim(body)) > 0 and char_length(body) <= 1000
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, entry_date)
);

create index if not exists idx_user_companion_diary_entries_user_date
  on public.user_companion_diary_entries (user_id, entry_date desc);

drop trigger if exists set_user_companion_diary_entries_updated_at
  on public.user_companion_diary_entries;
create trigger set_user_companion_diary_entries_updated_at
before update on public.user_companion_diary_entries
for each row execute function public.touch_updated_at();

grant select, insert, update, delete
  on table public.user_companion_diary_entries
  to authenticated;

alter table public.user_companion_diary_entries enable row level security;

drop policy if exists user_companion_diary_entries_read_own
  on public.user_companion_diary_entries;
create policy user_companion_diary_entries_read_own
  on public.user_companion_diary_entries
for select using (auth.uid() = user_id);

drop policy if exists user_companion_diary_entries_write_own
  on public.user_companion_diary_entries;
create policy user_companion_diary_entries_write_own
  on public.user_companion_diary_entries
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

commit;
