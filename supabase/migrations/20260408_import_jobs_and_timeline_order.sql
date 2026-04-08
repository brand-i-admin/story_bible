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

create index if not exists idx_import_jobs_status_requested
on public.import_jobs (status, requested_at desc);

create index if not exists idx_import_job_artifacts_job
on public.import_job_artifacts (import_job_id, artifact_type);

drop trigger if exists set_import_jobs_updated_at on public.import_jobs;
create trigger set_import_jobs_updated_at
before update on public.import_jobs
for each row execute function public.touch_updated_at();

alter table public.events
add column if not exists source_import_job_id uuid references public.import_jobs(id) on delete set null;

alter table public.events
add column if not exists display_number text;

alter table public.events
add column if not exists timeline_rank numeric(18, 6);

update public.events
set timeline_rank = time_sort_key::numeric
where timeline_rank is null;

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

alter table public.events
alter column timeline_rank set not null;

create index if not exists idx_events_timeline_order
on public.events (era_id, timeline_rank, time_sort_key, id);
