-- Complete schema migration for Story Bible
-- Combines user features, generated media, and import jobs
-- Generated: 2026-04-18

-- ============================================================================
-- COMMON UTILITIES
-- ============================================================================

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- USER PERSONAL FEATURES
-- ============================================================================

-- User profiles
create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  photo_url text,
  prayer_request text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- User notes
create table if not exists public.user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- User saved verses
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

-- User daily attendance
create table if not exists public.user_daily_attendance (
  user_id uuid not null references auth.users(id) on delete cascade,
  attended_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, attended_on)
);

-- User daily study
create table if not exists public.user_daily_study (
  user_id uuid not null references auth.users(id) on delete cascade,
  studied_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, studied_on)
);

-- Indexes for user tables
create index if not exists idx_user_notes_user_created
on public.user_notes (user_id, created_at desc);

create index if not exists idx_user_saved_verses_user_created
on public.user_saved_verses (user_id, created_at desc);

-- Triggers for user tables
drop trigger if exists set_user_profiles_updated_at on public.user_profiles;
create trigger set_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.touch_updated_at();

drop trigger if exists set_user_notes_updated_at on public.user_notes;
create trigger set_user_notes_updated_at
before update on public.user_notes
for each row execute function public.touch_updated_at();

-- Auto-create user profile on signup
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

-- Grants for user tables
grant select, insert, update on table public.user_profiles to authenticated;
grant select, insert, update on table public.user_notes to authenticated;
grant select, insert, delete on table public.user_saved_verses to authenticated;
grant select, insert on table public.user_daily_attendance to authenticated;
grant select, insert on table public.user_daily_study to authenticated;

-- RLS policies for user tables
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

-- Storage bucket for profile images
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

-- Storage policies for profile images
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

-- ============================================================================
-- GENERATED MEDIA SCHEMA
-- ============================================================================

-- Add avatar thumbnail URL to persons
alter table public.persons
add column if not exists avatar_thumb_url text;

update public.persons
set avatar_thumb_url = replace(avatar_url, 'assets/avatars/', 'assets/avatars_thumbs/')
where coalesce(avatar_thumb_url, '') = ''
  and coalesce(avatar_url, '') like 'assets/avatars/%';

-- Add thumbnail and asset fields to events
alter table public.events
add column if not exists thumb_url text;

alter table public.events
add column if not exists story_asset_dir text;

alter table public.events
add column if not exists story_thumbnail_dir text;

alter table public.events
add column if not exists story_scene_count integer not null default 0;

-- Person generated assets
create table if not exists public.person_generated_assets (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.persons(id) on delete cascade,
  original_path text,
  thumbnail_path text,
  status text not null default 'ready',
  generator text,
  generator_model text,
  generated_at timestamptz,
  content_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint person_generated_assets_person_id_key unique (person_id)
);

-- Event scene generated assets
create table if not exists public.event_scene_generated_assets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  scene_index integer not null check (scene_index > 0),
  original_path text,
  thumbnail_path text,
  status text not null default 'ready',
  prompt_text text,
  generator text,
  generator_model text,
  generated_at timestamptz,
  content_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_scene_generated_assets_event_scene_key unique (event_id, scene_index)
);

-- Indexes for generated assets
create index if not exists idx_event_scene_generated_assets_event_scene
on public.event_scene_generated_assets (event_id, scene_index);

-- Triggers for generated assets
drop trigger if exists set_person_generated_assets_updated_at on public.person_generated_assets;
create trigger set_person_generated_assets_updated_at
before update on public.person_generated_assets
for each row execute function public.touch_updated_at();

drop trigger if exists set_event_scene_generated_assets_updated_at on public.event_scene_generated_assets;
create trigger set_event_scene_generated_assets_updated_at
before update on public.event_scene_generated_assets
for each row execute function public.touch_updated_at();

-- Grants for generated assets
grant select on table public.person_generated_assets to anon, authenticated;
grant select on table public.event_scene_generated_assets to anon, authenticated;

-- ============================================================================
-- IMPORT JOBS AND TIMELINE ORDER
-- ============================================================================

-- Import jobs table
create table if not exists public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  submitted_by_user_id uuid references auth.users(id) on delete set null,
  source_name text not null,
  source_sha256 text not null,
  source_storage_key text,
  status text not null default 'received' check (
    status in (
      'received',
      'failed_validation',
      'validated',
      'under_review',
      'build_ready',
      'approved',
      'promoted',
      'failed',
      'cancelled'
    )
  ),
  requested_at timestamptz not null default now(),
  validated_at timestamptz,
  approved_at timestamptz,
  promoted_at timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Import job artifacts
create table if not exists public.import_job_artifacts (
  id uuid primary key default gen_random_uuid(),
  import_job_id uuid not null references public.import_jobs(id) on delete cascade,
  artifact_type text not null,
  relative_path text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint import_job_artifacts_job_type_path_key unique (
    import_job_id,
    artifact_type,
    relative_path
  )
);

-- Indexes for import jobs
create index if not exists idx_import_jobs_status_requested
on public.import_jobs (status, requested_at desc);

create index if not exists idx_import_job_artifacts_job
on public.import_job_artifacts (import_job_id, artifact_type);

-- Trigger for import jobs
drop trigger if exists set_import_jobs_updated_at on public.import_jobs;
create trigger set_import_jobs_updated_at
before update on public.import_jobs
for each row execute function public.touch_updated_at();

-- Validate events.code uniqueness and add constraint atomically
do $$
declare
  duplicate_count int;
begin
  -- Check for duplicates
  select count(*) into duplicate_count
  from (
    select code, count(*) as cnt
    from public.events
    group by code
    having count(*) > 1
  ) duplicates;

  if duplicate_count > 0 then
    raise exception 'Found % duplicate event codes. Manual cleanup required before migration.', duplicate_count;
  end if;

  -- Add unique constraint if validation passed (within same transaction)
  alter table public.events drop constraint if exists events_code_key;
  alter table public.events add constraint events_code_key unique (code);
end $$;

-- Add source_import_job_id to events
alter table public.events
add column if not exists source_import_job_id uuid references public.import_jobs(id) on delete restrict;

-- Add display_number to events
alter table public.events
add column if not exists display_number text;

-- Add timeline_rank to events
alter table public.events
add column if not exists timeline_rank double precision;

-- Initialize timeline_rank and display_number with validation
do $$
declare
  uninitialized_count int;
  invalid_rank_count int;
  duplicate_rank_count int;
begin
  -- Initialize timeline_rank from story number portion of time_sort_key
  -- IMPORTANT: Assumes time_sort_key format is (year * 1000 + story_number)
  -- Example: year 30 story 151 → time_sort_key = 30151 → timeline_rank = 151
  update public.events
  set timeline_rank = (time_sort_key % 1000)::double precision
  where timeline_rank is null;

  -- Initialize display_number from code if not set
  update public.events
  set display_number = coalesce(
    nullif(display_number, ''),
    lpad(
      coalesce(substring(code from '(\d+)$'), '0'),
      3,
      '0'
    )
  )
  where coalesce(display_number, '') = '';

  -- Verify all events have valid timeline_rank
  select count(*) into uninitialized_count
  from public.events
  where timeline_rank is null;

  if uninitialized_count > 0 then
    raise exception 'Failed to initialize timeline_rank for % events', uninitialized_count;
  end if;

  -- Validate timeline_rank is in expected range (1-999)
  select count(*) into invalid_rank_count
  from public.events
  where timeline_rank < 1 or timeline_rank > 999;

  if invalid_rank_count > 0 then
    raise exception 'Found % events with timeline_rank outside expected range (1-999). Check time_sort_key format.', invalid_rank_count;
  end if;

  -- Check for timeline_rank collisions within same era
  select count(*) into duplicate_rank_count
  from (
    select era_id, timeline_rank, count(*) as cnt
    from public.events
    group by era_id, timeline_rank
    having count(*) > 1
  ) duplicates;

  if duplicate_rank_count > 0 then
    -- Auto-fix collisions by adding small increments
    raise notice 'Found % timeline_rank collisions. Auto-fixing by adding 0.001 increments...', duplicate_rank_count;

    with ranked as (
      select id, era_id, timeline_rank,
             row_number() over (partition by era_id, timeline_rank order by id) - 1 as dup_rank
      from public.events
    )
    update public.events e
    set timeline_rank = timeline_rank + (r.dup_rank * 0.001)
    from ranked r
    where e.id = r.id and r.dup_rank > 0;

    raise notice 'Collision auto-fix complete.';
  end if;
end $$;

-- Set timeline_rank as not null
alter table public.events
alter column timeline_rank set not null;

-- Indexes for events timeline ordering
create index if not exists idx_events_timeline_order
on public.events (era_id, timeline_rank, time_sort_key, id);

-- Prevent timeline_rank collisions within same era
create unique index if not exists idx_events_era_timeline_rank_unique
on public.events (era_id, timeline_rank);

-- Add index for source_import_job_id lookups (for rollback)
create index if not exists idx_events_source_import_job
on public.events (source_import_job_id)
where source_import_job_id is not null;

-- Add index for display_number searches
create index if not exists idx_events_display_number
on public.events (display_number)
where display_number is not null;
