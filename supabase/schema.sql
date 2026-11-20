-- =========================================================
-- GlowFit 💖 — base de datos en Supabase
-- Cómo usarlo: Supabase → SQL Editor → New query → pega todo esto → Run
-- Cada persona solo puede ver y tocar SUS propios datos (Row Level Security).
-- =========================================================

-- Perfil, plan, ejercicios, XP, insignias, retos, camino a la dominada...
create table if not exists public.user_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Cada entreno: día y hora de inicio y fin, ejercicios y series
create table if not exists public.workouts (
  id         text not null,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at   timestamptz not null,
  title      text,
  day        int,
  entries    jsonb not null default '[]'::jsonb,  -- [{exId, target, sets:[{w, r, t, done}]}]
  prs        jsonb not null default '[]'::jsonb,
  xp         int not null default 0,
  paused_ms  bigint not null default 0,  -- tiempo en pausa (ms)
  meta       jsonb not null default '{}'::jsonb,  -- energía, síntomas, modo suave, día y fase del ciclo
  created_at timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.workouts add column if not exists paused_ms bigint not null default 0;
alter table public.workouts add column if not exists meta jsonb not null default '{}'::jsonb;
create index if not exists workouts_user_started on public.workouts (user_id, started_at);

-- Fotos de antes / después (el archivo va al bucket privado "photos")
create table if not exists public.photos (
  id         text not null,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  taken_at   timestamptz not null default now(),
  path       text not null,
  primary key (user_id, id)
);

-- ---------- Seguridad: cada una solo ve lo suyo ----------
alter table public.user_state enable row level security;
alter table public.workouts   enable row level security;
alter table public.photos     enable row level security;

drop policy if exists "own state"    on public.user_state;
drop policy if exists "own workouts" on public.workouts;
drop policy if exists "own photos"   on public.photos;
create policy "own state"    on public.user_state for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own workouts" on public.workouts   for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own photos"   on public.photos     for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- Almacenamiento privado de fotos ----------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists "own photo files select" on storage.objects;
drop policy if exists "own photo files insert" on storage.objects;
drop policy if exists "own photo files delete" on storage.objects;
create policy "own photo files select" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own photo files insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own photo files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- Vista cómoda para mirar tus entrenos en el Table Editor ----------
create or replace view public.workouts_resumen with (security_invoker = on) as
select
  user_id,
  to_char(started_at at time zone 'Europe/Madrid', 'DD/MM/YYYY') as dia,
  to_char(started_at at time zone 'Europe/Madrid', 'HH24:MI')    as hora_inicio,
  to_char(ended_at   at time zone 'Europe/Madrid', 'HH24:MI')    as hora_fin,
  round((extract(epoch from ended_at - started_at) * 1000 - paused_ms) / 60000) as minutos,
  round(paused_ms / 60000.0)                                     as minutos_pausa,
  title as entreno,
  meta->>'energy'   as energia,
  meta->>'phase'    as fase_ciclo,
  (meta->>'cycleDay')::int as dia_ciclo,
  xp
from public.workouts
order by started_at desc;
