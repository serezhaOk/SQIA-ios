-- The mixer's knobs, per project: `{"delay": 0…1, "scatter": 0…1}`. iOS
-- reads and writes it; the web does not know it yet, so its writes leave it
-- alone. Existing rows get `{}`, which iOS reads as every knob at zero — a
-- dry mix, which is what a project with no knobs of its own should be.
alter table public.projects
  add column if not exists effects jsonb not null default '{}'::jsonb
  constraint projects_effects_object check (jsonb_typeof(effects) = 'object');
