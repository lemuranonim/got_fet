-- GOT workflow revision: separate sample condition from operational status,
-- and add field-facing names without replacing the factory lot identity.

alter table public.got_fet_samples
  add column if not exists workflow_status text,
  add column if not exists land_area_name text,
  add column if not exists batch_lot_field text;

update public.got_fet_samples
set workflow_status = coalesce(
  nullif(trim(workflow_status), ''),
  case
    when lower(coalesce(final_status_got, '')) in (
      'approved',
      'confirmed',
      'completed',
      'done'
    ) then 'Approved'
    when nullif(trim(final_status_got), '') is not null then 'Waiting Review'
    when nullif(trim(status_got_veg), '') is not null then 'To Obs. Gen'
    when planting_date is not null then 'To Obs. Veg'
    when lower(coalesce(status_sample, '')) like '%request%' then
      'Request New Sample'
    when lower(coalesce(status_sample, '')) like '%ready%plant%' then
      'Ready to Plant'
    else 'Open'
  end
);

alter table public.got_fet_samples
  alter column workflow_status set default 'Open',
  alter column workflow_status set not null;

create index if not exists got_fet_samples_workflow_status_idx
  on public.got_fet_samples (workflow_status);

notify pgrst, 'reload schema';
