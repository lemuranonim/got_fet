-- GOT revision: Village Coordinate, structured Off-Type, and evidence rules.
-- Run after supabase/got_fet_samples_schema.sql.

alter table public.got_fet_samples
  add column if not exists lot_id text,
  add column if not exists sample_id text,
  add column if not exists village_desa text,
  add column if not exists sub_district_kec text,
  add column if not exists district_kab text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

update public.got_fet_samples
set
  lot_id = coalesce(nullif(lot_id, ''), batch),
  sample_id = coalesce(nullif(sample_id, ''), batch)
where lot_id is null
   or lot_id = ''
   or sample_id is null
   or sample_id = '';

create index if not exists got_fet_samples_lot_sample_idx
  on public.got_fet_samples (lot_id, sample_id);

create table if not exists public.got_fet_off_type_rules (
  id text primary key,
  category_no integer not null check (category_no between 1 and 3),
  type_code text not null default '',
  label text not null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.got_fet_off_type_rules (
  id,
  category_no,
  type_code,
  label,
  sort_order
)
values
  ('category_1_a', 1, 'A', 'Mirip FI / Adv', 10),
  ('category_1_b', 1, 'B', 'Mirip karakter', 20),
  (
    'category_2',
    2,
    '',
    'Karakter berbeda - perlu verifikasi',
    30
  ),
  (
    'category_3',
    3,
    '',
    'Tidak teridentifikasi - investigasi lanjut',
    40
  )
on conflict (id) do nothing;

alter table public.got_fet_off_type_rules enable row level security;

drop policy if exists "Authenticated users can read off-type rules"
  on public.got_fet_off_type_rules;
create policy "Authenticated users can read off-type rules"
  on public.got_fet_off_type_rules
  for select
  to authenticated
  using (auth.uid() is not null);

create table if not exists public.got_fet_off_type_details (
  id uuid primary key default gen_random_uuid(),
  lot_id text not null,
  sample_id text not null,
  plot_id text not null,
  observation_stage text not null,
  rule_id text not null references public.got_fet_off_type_rules (id),
  category_no integer not null check (category_no between 1 and 3),
  type_code text not null default '',
  type_label text not null,
  character_note text not null check (length(trim(character_note)) > 0),
  similarity_assessment text not null check (
    similarity_assessment in (
      'similar_fi_or_hybrid',
      'not_similar_fi_or_hybrid'
    )
  ),
  reference_hybrid text not null default '',
  required_photo_count integer not null
    check (required_photo_count between 1 and 12),
  sort_order integer not null default 0,
  created_by text,
  updated_by text,
  created_by_user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists got_fet_off_type_details_lookup_idx
  on public.got_fet_off_type_details (
    lot_id,
    sample_id,
    plot_id,
    observation_stage,
    sort_order
  );

alter table public.got_fet_off_type_details enable row level security;

drop policy if exists "Owners and reviewers can read off-type details"
  on public.got_fet_off_type_details;
create policy "Owners and reviewers can read off-type details"
  on public.got_fet_off_type_details
  for select
  to authenticated
  using (
    created_by_user_id = auth.uid()
    or exists (
      select 1
      from public.app_users current_user_profile
      where current_user_profile.id = auth.uid()
        and current_user_profile.action = 'all'
        and current_user_profile.is_active = true
    )
  );

drop policy if exists "Owners can insert off-type details"
  on public.got_fet_off_type_details;
create policy "Owners can insert off-type details"
  on public.got_fet_off_type_details
  for insert
  to authenticated
  with check (created_by_user_id = auth.uid());

drop policy if exists "Owners and reviewers can update off-type details"
  on public.got_fet_off_type_details;
create policy "Owners and reviewers can update off-type details"
  on public.got_fet_off_type_details
  for update
  to authenticated
  using (
    created_by_user_id = auth.uid()
    or exists (
      select 1
      from public.app_users current_user_profile
      where current_user_profile.id = auth.uid()
        and current_user_profile.action = 'all'
        and current_user_profile.is_active = true
    )
  )
  with check (
    created_by_user_id = auth.uid()
    or exists (
      select 1
      from public.app_users current_user_profile
      where current_user_profile.id = auth.uid()
        and current_user_profile.action = 'all'
        and current_user_profile.is_active = true
    )
  );

drop policy if exists "Owners and reviewers can delete off-type details"
  on public.got_fet_off_type_details;
create policy "Owners and reviewers can delete off-type details"
  on public.got_fet_off_type_details
  for delete
  to authenticated
  using (
    created_by_user_id = auth.uid()
    or exists (
      select 1
      from public.app_users current_user_profile
      where current_user_profile.id = auth.uid()
        and current_user_profile.action = 'all'
        and current_user_profile.is_active = true
    )
  );

do $$
begin
  alter publication supabase_realtime
    add table public.got_fet_off_type_details;
exception
  when duplicate_object then null;
end $$;

alter table public.got_fet_photo_evidence
  add column if not exists off_type_detail_id uuid
    references public.got_fet_off_type_details (id) on delete cascade;

drop index if exists public.got_fet_photo_evidence_got_slot_uidx;

create unique index got_fet_photo_evidence_got_slot_uidx
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
    and rcv_no is not null
    and off_type_detail_id is null;

create unique index if not exists
  got_fet_photo_evidence_off_type_slot_uidx
  on public.got_fet_photo_evidence (off_type_detail_id, rcv_no)
  where off_type_detail_id is not null;

