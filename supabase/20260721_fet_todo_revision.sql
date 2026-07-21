-- FET revision: Day 7/11 observation slots and structured remarks.
-- Run after supabase/got_fet_samples_schema.sql.

update public.got_fet_fet_observation
set dap = 7
where dap not in (7, 11);

alter table public.got_fet_fet_observation
  add column if not exists remark_status text,
  add column if not exists updated_at timestamptz not null default now();

update public.got_fet_fet_observation
set remark_status = 'Done'
where remark_status is null
   or remark_status not in ('Retest', 'Resampling', 'Done');

alter table public.got_fet_fet_observation
  alter column remark_status set default 'Done',
  alter column remark_status set not null;

do $$
begin
  alter table public.got_fet_fet_observation
    add constraint got_fet_fet_observation_dap_check
    check (dap in (7, 11));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.got_fet_fet_observation
    add constraint got_fet_fet_observation_remark_status_check
    check (remark_status in ('Retest', 'Resampling', 'Done'));
exception
  when duplicate_object then null;
end $$;

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

create index if not exists got_fet_fet_observation_day_lookup_idx
  on public.got_fet_fet_observation (
    lot_id,
    sample_id,
    dap,
    replication,
    submitted_datetime desc
  );
