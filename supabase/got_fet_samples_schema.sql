create table if not exists public.got_fet_samples (
  id uuid primary key default gen_random_uuid(),
  no integer,
  hybrid_all text,
  gender text,
  type_seed text,
  category text,
  crop_year integer,
  process_stage text,
  batch text not null unique,
  note_sample text,
  qty_by_dss numeric,
  commercial_qty_inventory numeric,
  flagging text,
  reason_testing text,
  purity_class text not null default 'Komersil'
    check (purity_class in ('PS', 'Komersil')),
  delivery_date_1 date,
  delivery_date_2 date,
  planting_date date,
  week_of_planting integer,
  result_estimation date,
  week_of_result_estimation integer,
  note_tanam text,
  land_area_name text,
  batch_lot_field text,
  location text,
  field_area numeric,
  status_got_2 text,
  status_sample text,
  workflow_status text not null default 'Open',
  result_percent numeric,
  offtype_percent numeric,
  selfing_percent numeric,
  male_percent numeric,
  suspicious_percent numeric,
  total_percent numeric,
  vegetative_total numeric,
  status_got_veg text,
  vegetative_no_obs text,
  final_result_percent numeric,
  final_offtype_percent numeric,
  final_selfing_percent numeric,
  final_male_percent numeric,
  final_suspicious_percent numeric,
  final_total_percent numeric,
  final_total numeric,
  final_status_got text,
  final_no_obs text,
  payment text,
  test_type text generated always as (
    case
      when coalesce(status_got_2, status_got_veg, final_status_got) is not null then 'GOT'
      else 'FET'
    end
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists got_fet_samples_batch_idx
  on public.got_fet_samples (batch);

create index if not exists got_fet_samples_test_type_idx
  on public.got_fet_samples (test_type);

alter table public.got_fet_samples enable row level security;

drop policy if exists "Authenticated users can read GOT FET samples"
  on public.got_fet_samples;

create policy "Authenticated users can read GOT FET samples"
  on public.got_fet_samples
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can update GOT FET planning fields"
  on public.got_fet_samples;

create policy "Authenticated users can update GOT FET planning fields"
  on public.got_fet_samples
  for update
  to authenticated
  using (true)
  with check (true);

create table if not exists public.got_fet_got_observation (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  hybrid text,
  plot_id text not null,
  observation_stage text not null,
  total_observed integer not null default 0,
  off_type_count integer not null default 0,
  selfing_count integer not null default 0,
  male_count integer not null default 0,
  suspicious_count integer not null default 0,
  true_type_count integer not null default 0,
  purity_percent numeric not null default 0,
  remarks text,
  submitted_by text,
  submitted_datetime timestamptz not null default now(),
  review_status text not null default 'Draft',
  created_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lot_id, sample_id, plot_id, observation_stage)
);

create index if not exists got_fet_got_observation_lookup_idx
  on public.got_fet_got_observation (
    lot_id,
    sample_id,
    plot_id,
    observation_stage,
    submitted_datetime desc
  );

alter table public.got_fet_got_observation enable row level security;

drop policy if exists "Authenticated users can read GOT observations"
  on public.got_fet_got_observation;

create policy "Authenticated users can read GOT observations"
  on public.got_fet_got_observation
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert GOT observations"
  on public.got_fet_got_observation;

create policy "Authenticated users can insert GOT observations"
  on public.got_fet_got_observation
  for insert
  to authenticated
  with check (true);

drop policy if exists "Authenticated users can update GOT observations"
  on public.got_fet_got_observation;

create policy "Authenticated users can update GOT observations"
  on public.got_fet_got_observation
  for update
  to authenticated
  using (true)
  with check (true);

do $$
begin
  alter publication supabase_realtime
    add table public.got_fet_got_observation;
exception
  when duplicate_object then null;
end $$;

create table if not exists public.got_fet_fet_observation (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  hybrid text,
  plot_id text not null,
  replication integer not null,
  dap integer not null default 0,
  total_points integer not null default 0,
  grown_count integer not null default 0,
  not_grown_count integer not null default 0,
  review_count integer not null default 0,
  not_readable_count integer not null default 0,
  emergence_percent numeric not null default 0,
  point_statuses jsonb not null default '[]'::jsonb,
  plot_photo_url text,
  remarks text,
  remark_status text not null default 'Done'
    check (remark_status in ('Retest', 'Resampling', 'Done')),
  submitted_by text,
  submitted_datetime timestamptz not null default now(),
  review_status text not null default 'Draft',
  created_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lot_id, sample_id, plot_id, dap, replication)
);

alter table public.got_fet_fet_observation
  add column if not exists updated_at timestamptz not null default now();

create index if not exists got_fet_fet_observation_lookup_idx
  on public.got_fet_fet_observation (
    lot_id,
    sample_id,
    plot_id,
    dap,
    replication,
    submitted_datetime desc
  );

create unique index if not exists got_fet_fet_observation_slot_uidx
  on public.got_fet_fet_observation (
    lot_id,
    sample_id,
    plot_id,
    dap,
    replication
  );

alter table public.got_fet_fet_observation enable row level security;

drop policy if exists "Authenticated users can read FET observations"
  on public.got_fet_fet_observation;

create policy "Authenticated users can read FET observations"
  on public.got_fet_fet_observation
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert FET observations"
  on public.got_fet_fet_observation;

create policy "Authenticated users can insert FET observations"
  on public.got_fet_fet_observation
  for insert
  to authenticated
  with check (true);

drop policy if exists "Authenticated users can update FET observations"
  on public.got_fet_fet_observation;

create policy "Authenticated users can update FET observations"
  on public.got_fet_fet_observation
  for update
  to authenticated
  using (true)
  with check (true);

do $$
begin
  alter publication supabase_realtime
    add table public.got_fet_fet_observation;
exception
  when duplicate_object then null;
end $$;

create table if not exists public.got_fet_sample_tracking (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  status text not null,
  actor text,
  event_datetime timestamptz not null default now(),
  remarks text,
  created_by_user_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists got_fet_sample_tracking_lookup_idx
  on public.got_fet_sample_tracking (lot_id, event_datetime desc);

alter table public.got_fet_sample_tracking enable row level security;

drop policy if exists "Authenticated users can read sample tracking"
  on public.got_fet_sample_tracking;

create policy "Authenticated users can read sample tracking"
  on public.got_fet_sample_tracking
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert sample tracking"
  on public.got_fet_sample_tracking;

create policy "Authenticated users can insert sample tracking"
  on public.got_fet_sample_tracking
  for insert
  to authenticated
  with check (true);

create table if not exists public.got_fet_review_history (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  module text not null,
  previous_status text,
  new_status text not null,
  review_action text not null,
  reviewer text,
  review_datetime timestamptz not null default now(),
  remarks text,
  created_by_user_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists got_fet_review_history_lookup_idx
  on public.got_fet_review_history (
    lot_id,
    sample_id,
    module,
    review_datetime desc
  );

alter table public.got_fet_review_history enable row level security;

drop policy if exists "Authenticated users can read review history"
  on public.got_fet_review_history;

create policy "Authenticated users can read review history"
  on public.got_fet_review_history
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert review history"
  on public.got_fet_review_history;

create policy "Authenticated users can insert review history"
  on public.got_fet_review_history
  for insert
  to authenticated
  with check (true);

create table if not exists public.got_fet_final_decision (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  module text not null,
  decision text not null,
  decided_by text,
  decision_datetime timestamptz not null default now(),
  remarks text,
  created_by_user_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists got_fet_final_decision_lookup_idx
  on public.got_fet_final_decision (
    lot_id,
    sample_id,
    module,
    decision_datetime desc
  );

alter table public.got_fet_final_decision enable row level security;

drop policy if exists "Authenticated users can read final decisions"
  on public.got_fet_final_decision;

create policy "Authenticated users can read final decisions"
  on public.got_fet_final_decision
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert final decisions"
  on public.got_fet_final_decision;

create policy "Authenticated users can insert final decisions"
  on public.got_fet_final_decision
  for insert
  to authenticated
  with check (true);

create table if not exists public.got_fet_photo_evidence (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  test_type text not null,
  module text not null,
  plot_id text,
  replication text,
  observation_stage text,
  evidence_category text,
  rcv_no integer,
  rcv_label text,
  storage_path text,
  photo_url text not null,
  uploaded_by text,
  uploaded_datetime timestamptz not null default now(),
  review_status text not null default 'Submitted',
  created_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.got_fet_photo_evidence
  add column if not exists id uuid default gen_random_uuid();

create unique index if not exists got_fet_photo_evidence_id_uidx
  on public.got_fet_photo_evidence (id);

alter table public.got_fet_photo_evidence
  add column if not exists observation_stage text;

alter table public.got_fet_photo_evidence
  add column if not exists evidence_category text;

alter table public.got_fet_photo_evidence
  add column if not exists rcv_no integer;

alter table public.got_fet_photo_evidence
  add column if not exists rcv_label text;

alter table public.got_fet_photo_evidence
  add column if not exists storage_path text;

alter table public.got_fet_photo_evidence
  add column if not exists updated_at timestamptz not null default now();

create index if not exists got_fet_photo_evidence_got_lookup_idx
  on public.got_fet_photo_evidence (
    lot_id,
    sample_id,
    module,
    plot_id,
    observation_stage,
    evidence_category,
    rcv_no
  );

create unique index if not exists got_fet_photo_evidence_got_slot_uidx
  on public.got_fet_photo_evidence (
    lot_id,
    sample_id,
    module,
    plot_id,
    observation_stage,
    evidence_category,
    rcv_no
  )
  where module = 'got'
    and observation_stage is not null
    and evidence_category is not null
    and rcv_no is not null;

alter table public.got_fet_photo_evidence enable row level security;

drop policy if exists "Authenticated users can read photo evidence"
  on public.got_fet_photo_evidence;

create policy "Authenticated users can read photo evidence"
  on public.got_fet_photo_evidence
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can insert photo evidence"
  on public.got_fet_photo_evidence;

create policy "Authenticated users can insert photo evidence"
  on public.got_fet_photo_evidence
  for insert
  to authenticated
  with check (true);

drop policy if exists "Authenticated users can update photo evidence"
  on public.got_fet_photo_evidence;

create policy "Authenticated users can update photo evidence"
  on public.got_fet_photo_evidence
  for update
  to authenticated
  using (true)
  with check (true);

do $$
begin
  alter publication supabase_realtime
    add table public.got_fet_photo_evidence;
exception
  when duplicate_object then null;
end $$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'got_fet_evidence',
  'got_fet_evidence',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users can read GOT FET evidence objects"
  on storage.objects;

create policy "Authenticated users can read GOT FET evidence objects"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'got_fet_evidence');

drop policy if exists "Authenticated users can upload GOT FET evidence objects"
  on storage.objects;

create policy "Authenticated users can upload GOT FET evidence objects"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'got_fet_evidence');

drop policy if exists "Authenticated users can update GOT FET evidence objects"
  on storage.objects;

create policy "Authenticated users can update GOT FET evidence objects"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'got_fet_evidence')
  with check (bucket_id = 'got_fet_evidence');

notify pgrst, 'reload schema';
