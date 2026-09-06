-- Follow-up for field review dated 30-31 July 2026.
-- Run after the existing GOT/FET schema and revision scripts.

alter table public.got_fet_samples
  add column if not exists purity_class text,
  add column if not exists suspicious_percent numeric,
  add column if not exists total_percent numeric,
  add column if not exists final_suspicious_percent numeric,
  add column if not exists final_total_percent numeric;

update public.got_fet_samples
set purity_class = case
  when lower(concat_ws(
    ' ',
    type_seed,
    category,
    process_stage,
    reason_testing,
    gender
  )) ~ '(^|[^a-z0-9])(ps|parent seed|parent stock|parental|inbred|male|female|jantan|betina)([^a-z0-9]|$)'
    then 'PS'
  else 'Komersil'
end
where purity_class is null
   or purity_class not in ('PS', 'Komersil');

alter table public.got_fet_samples
  alter column purity_class set default 'Komersil',
  alter column purity_class set not null;

do $$
begin
  alter table public.got_fet_samples
    add constraint got_fet_samples_purity_class_check
    check (purity_class in ('PS', 'Komersil'));
exception
  when duplicate_object then null;
end $$;

alter table public.got_fet_off_type_details
  add column if not exists characterization jsonb not null default '{}'::jsonb;

alter table public.got_fet_fet_observation
  drop constraint if exists
    got_fet_fet_observation_lot_id_sample_id_plot_id_replication_key;

drop index if exists public.got_fet_fet_observation_slot_uidx;

create unique index got_fet_fet_observation_slot_uidx
  on public.got_fet_fet_observation (
    lot_id,
    sample_id,
    plot_id,
    dap,
    replication
  );

create or replace view public.got_fet_off_type_characterization_export
with (security_invoker = true)
as
select
  lot_id,
  sample_id,
  plot_id,
  observation_stage,
  category_no,
  type_code,
  type_label,
  character_note,
  similarity_assessment,
  reference_hybrid,
  characterization ->> 'stem_anthocyanin_pigmentation'
    as stem_anthocyanin_pigmentation,
  characterization ->> 'branch_attitude' as branch_attitude,
  characterization ->> 'tassel_type' as tassel_type,
  characterization ->> 'anther_color' as anther_color,
  characterization ->> 'glume_color' as glume_color,
  characterization ->> 'ear_at_silk_emergence_color'
    as ear_at_silk_emergence_color,
  characterization ->> 'brace_root_anthocyanin_pigmentation'
    as brace_root_anthocyanin_pigmentation,
  characterization ->> 'brace_root_color' as brace_root_color,
  characterization ->> 'leaf_edge_color' as leaf_edge_color,
  characterization ->> 'tassel_breaking_time' as tassel_breaking_time,
  characterization ->> 'silking_50_days' as silking_50_days,
  characterization ->> 'silking_compared_to_true_type'
    as silking_compared_to_true_type,
  characterization ->> 'pollen_50_days' as pollen_50_days,
  characterization ->> 'pollen_compared_to_true_type'
    as pollen_compared_to_true_type,
  updated_at
from public.got_fet_off_type_details;

grant select on public.got_fet_off_type_characterization_export
  to authenticated;

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
