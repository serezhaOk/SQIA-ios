-- Sounds published from SQIA Lab, so new ones reach the app without a
-- release. A row is a sound; `preset` is the Lab's preset file as saved;
-- `samples` names a folder in the `sounds` bucket and the recordings in it.
--
-- `id` is the voice index a track stores in `projects.tracks`, so it is
-- chosen by the publisher, never reused and never deleted — hide a sound
-- with `visible = false` and the projects that use it keep playing it.
-- 0…4 are the original synths and are not rows; the bundle's sounds (5…9)
-- may have a row with no preset, which only re-labels, re-orders, hides or
-- locks them.
--
-- Everyone reads. Nobody writes through the API: the Lab publishes with
-- the project's secret key, which is not subject to these policies.
create table if not exists public.sounds (
  id integer primary key check (id >= 5),
  name text not null,
  hint text not null default '',
  preset jsonb,
  samples jsonb,
  position integer not null default 0,
  visible boolean not null default true,
  plus boolean not null default false,
  min_core integer not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.sounds enable row level security;

drop policy if exists "Sounds are public" on public.sounds;
create policy "Sounds are public" on public.sounds
  for select to anon, authenticated using (true);

grant select on public.sounds to anon, authenticated;

-- The recordings. Public, so the app fetches them by URL with no session;
-- written only with the secret key, like the table.
insert into storage.buckets (id, name, public)
values ('sounds', 'sounds', true)
on conflict (id) do update set public = true;
