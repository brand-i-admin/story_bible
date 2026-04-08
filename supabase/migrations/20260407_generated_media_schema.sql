alter table public.persons
add column if not exists avatar_thumb_url text;

update public.persons
set avatar_thumb_url = replace(avatar_url, 'assets/avatars/', 'assets/avatars_thumbs/')
where coalesce(avatar_thumb_url, '') = ''
  and coalesce(avatar_url, '') like 'assets/avatars/%';

alter table public.events
add column if not exists thumb_url text;

alter table public.events
add column if not exists story_asset_dir text;

alter table public.events
add column if not exists story_thumbnail_dir text;

alter table public.events
add column if not exists story_scene_count integer not null default 0;

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

create index if not exists idx_event_scene_generated_assets_event_scene
on public.event_scene_generated_assets (event_id, scene_index);

drop trigger if exists set_person_generated_assets_updated_at on public.person_generated_assets;
create trigger set_person_generated_assets_updated_at
before update on public.person_generated_assets
for each row execute function public.touch_updated_at();

drop trigger if exists set_event_scene_generated_assets_updated_at on public.event_scene_generated_assets;
create trigger set_event_scene_generated_assets_updated_at
before update on public.event_scene_generated_assets
for each row execute function public.touch_updated_at();

grant select on table public.person_generated_assets to anon, authenticated;
grant select on table public.event_scene_generated_assets to anon, authenticated;
