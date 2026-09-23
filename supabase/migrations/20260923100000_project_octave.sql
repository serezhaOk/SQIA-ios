-- The octave a project's grid is shifted by, -2 to +2. iOS reads and writes
-- it; the web does not know it yet, so its writes leave it alone and its
-- projects play at 0. Existing rows get 0, which is what they already sound
-- like.
alter table public.projects
  add column if not exists octave smallint not null default 0
  constraint projects_octave_range check (octave between -2 and 2);
