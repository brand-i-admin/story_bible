create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  photo_url text,
  prayer_request text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_saved_verses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  translation text not null default 'KRV',
  book_no smallint not null check (book_no between 1 and 66),
  book_name text not null,
  chapter_no smallint not null check (chapter_no > 0),
  verse_no smallint not null check (verse_no > 0),
  verse_text text not null,
  created_at timestamptz not null default now(),
  unique (user_id, translation, book_no, chapter_no, verse_no)
);

create table if not exists public.user_daily_attendance (
  user_id uuid not null references auth.users(id) on delete cascade,
  attended_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, attended_on)
);

create table if not exists public.user_daily_study (
  user_id uuid not null references auth.users(id) on delete cascade,
  studied_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, studied_on)
);

create index if not exists idx_user_notes_user_created
on public.user_notes (user_id, created_at desc);

create index if not exists idx_user_saved_verses_user_created
on public.user_saved_verses (user_id, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_user_profiles_updated_at on public.user_profiles;
create trigger set_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.touch_updated_at();

drop trigger if exists set_user_notes_updated_at on public.user_notes;
create trigger set_user_notes_updated_at
before update on public.user_notes
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  derived_nickname text;
begin
  derived_nickname := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(trim(split_part(new.email, '@', 1)), ''),
    '사용자'
  );

  insert into public.user_profiles (user_id, nickname)
  values (new.id, derived_nickname)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user_profile();

grant select, insert, update on table public.user_profiles to authenticated;
grant select, insert, update on table public.user_notes to authenticated;
grant select, insert, delete on table public.user_saved_verses to authenticated;
grant select, insert on table public.user_daily_attendance to authenticated;
grant select, insert on table public.user_daily_study to authenticated;

alter table public.user_profiles enable row level security;
alter table public.user_notes enable row level security;
alter table public.user_saved_verses enable row level security;
alter table public.user_daily_attendance enable row level security;
alter table public.user_daily_study enable row level security;

drop policy if exists user_profiles_read_own on public.user_profiles;
create policy user_profiles_read_own on public.user_profiles
for select using (auth.uid() = user_id);

drop policy if exists user_profiles_insert_own on public.user_profiles;
create policy user_profiles_insert_own on public.user_profiles
for insert with check (auth.uid() = user_id);

drop policy if exists user_profiles_update_own on public.user_profiles;
create policy user_profiles_update_own on public.user_profiles
for update using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists user_notes_read_own on public.user_notes;
create policy user_notes_read_own on public.user_notes
for select using (auth.uid() = user_id);

drop policy if exists user_notes_insert_own on public.user_notes;
create policy user_notes_insert_own on public.user_notes
for insert with check (auth.uid() = user_id);

drop policy if exists user_notes_update_own on public.user_notes;
create policy user_notes_update_own on public.user_notes
for update using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists user_saved_verses_read_own on public.user_saved_verses;
create policy user_saved_verses_read_own on public.user_saved_verses
for select using (auth.uid() = user_id);

drop policy if exists user_saved_verses_insert_own on public.user_saved_verses;
create policy user_saved_verses_insert_own on public.user_saved_verses
for insert with check (auth.uid() = user_id);

drop policy if exists user_saved_verses_delete_own on public.user_saved_verses;
create policy user_saved_verses_delete_own on public.user_saved_verses
for delete using (auth.uid() = user_id);

drop policy if exists user_daily_attendance_read_own on public.user_daily_attendance;
create policy user_daily_attendance_read_own on public.user_daily_attendance
for select using (auth.uid() = user_id);

drop policy if exists user_daily_attendance_insert_own on public.user_daily_attendance;
create policy user_daily_attendance_insert_own on public.user_daily_attendance
for insert with check (auth.uid() = user_id);

drop policy if exists user_daily_study_read_own on public.user_daily_study;
create policy user_daily_study_read_own on public.user_daily_study
for select using (auth.uid() = user_id);

drop policy if exists user_daily_study_insert_own on public.user_daily_study;
create policy user_daily_study_insert_own on public.user_daily_study
for insert with check (auth.uid() = user_id);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-images',
  'profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists profile_images_public_read on storage.objects;
create policy profile_images_public_read on storage.objects
for select using (bucket_id = 'profile-images');

drop policy if exists profile_images_insert_own on storage.objects;
create policy profile_images_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists profile_images_update_own on storage.objects;
create policy profile_images_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists profile_images_delete_own on storage.objects;
create policy profile_images_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
