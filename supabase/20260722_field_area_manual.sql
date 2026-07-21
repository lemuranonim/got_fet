-- Mengaktifkan catatan khusus untuk luasan manual pada data tanam GOT/FET.
alter table public.got_fet_samples
  add column if not exists field_area_note text;

comment on column public.got_fet_samples.field_area_note is
  'Catatan opsional untuk luasan/field area yang diinput manual.';
