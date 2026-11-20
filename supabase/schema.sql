-- =========================================================
-- GirlGym 💖 — base de datos en Supabase
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

-- ---------- Coach 💬: contador de preguntas (límite diario de gasto) ----------
create table if not exists public.coach_usage (
  id         bigserial primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists coach_usage_user_time on public.coach_usage (user_id, created_at);
alter table public.coach_usage enable row level security;
drop policy if exists "own coach usage" on public.coach_usage;
create policy "own coach usage" on public.coach_usage for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =========================================================
-- 👯‍♀️ AMIGAS: perfiles, amistades, actividad, respuestas, reacciones y mensajes de ánimo
-- Nadie ve nada tuyo salvo tus amigas aceptadas. Tu ciclo y tus fotos NUNCA se comparten.
-- =========================================================
create table if not exists public.friend_profiles (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  emoji      text not null default '🌸' check (char_length(emoji) <= 8),
  code       text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.friendships (
  id         uuid primary key default gen_random_uuid(),
  requester  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  addressee  uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));

create or replace function public.is_friend(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where status = 'accepted'
    and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;
create or replace function public.is_connected(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships
    where (requester = a and addressee = b) or (requester = b and addressee = a));
$$;
-- Buscar a una amiga por su código (devuelve solo nombre y emoji de esa persona)
create or replace function public.find_friend_code(p_code text)
returns table (user_id uuid, name text, emoji text)
language sql stable security definer set search_path = public as $$
  select user_id, name, emoji from friend_profiles
  where code = upper(trim(p_code)) and user_id <> auth.uid() limit 1;
$$;
revoke all on function public.find_friend_code(text) from public, anon;
grant execute on function public.find_friend_code(text) to authenticated;

create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('workout','badge','road','answer')),
  text       text check (char_length(text) <= 500),
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists posts_user_time on public.posts (user_id, created_at desc);

create table if not exists public.post_replies (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 300),
  created_at timestamptz not null default now()
);
create table if not exists public.post_reactions (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  emoji      text not null check (emoji in ('💖','🔥','👏')),
  primary key (post_id, user_id)
);
create table if not exists public.cheers (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 200),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists cheers_to_time on public.cheers (to_user, created_at desc);

alter table public.friend_profiles enable row level security;
alter table public.friendships     enable row level security;
alter table public.posts           enable row level security;
alter table public.post_replies    enable row level security;
alter table public.post_reactions  enable row level security;
alter table public.cheers          enable row level security;

drop policy if exists "fp select" on public.friend_profiles;
drop policy if exists "fp insert" on public.friend_profiles;
drop policy if exists "fp update" on public.friend_profiles;
create policy "fp select" on public.friend_profiles for select to authenticated using (user_id = auth.uid() or public.is_connected(auth.uid(), user_id));
create policy "fp insert" on public.friend_profiles for insert to authenticated with check (user_id = auth.uid());
create policy "fp update" on public.friend_profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "fs select" on public.friendships;
drop policy if exists "fs insert" on public.friendships;
drop policy if exists "fs accept" on public.friendships;
drop policy if exists "fs delete" on public.friendships;
create policy "fs select" on public.friendships for select to authenticated using (auth.uid() in (requester, addressee));
create policy "fs insert" on public.friendships for insert to authenticated with check (requester = auth.uid() and status = 'pending');
create policy "fs accept" on public.friendships for update to authenticated using (addressee = auth.uid()) with check (addressee = auth.uid() and status = 'accepted');
create policy "fs delete" on public.friendships for delete to authenticated using (auth.uid() in (requester, addressee));

drop policy if exists "posts select" on public.posts;
drop policy if exists "posts insert" on public.posts;
drop policy if exists "posts delete" on public.posts;
create policy "posts select" on public.posts for select to authenticated using (user_id = auth.uid() or public.is_friend(auth.uid(), user_id));
create policy "posts insert" on public.posts for insert to authenticated with check (user_id = auth.uid());
create policy "posts delete" on public.posts for delete to authenticated using (user_id = auth.uid());

drop policy if exists "replies select" on public.post_replies;
drop policy if exists "replies insert" on public.post_replies;
drop policy if exists "replies delete" on public.post_replies;
create policy "replies select" on public.post_replies for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));   -- hereda la visibilidad del post
create policy "replies insert" on public.post_replies for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id));
create policy "replies delete" on public.post_replies for delete to authenticated using (user_id = auth.uid());

drop policy if exists "reactions select" on public.post_reactions;
drop policy if exists "reactions write" on public.post_reactions;
create policy "reactions select" on public.post_reactions for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));
create policy "reactions write" on public.post_reactions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id));

drop policy if exists "cheers select" on public.cheers;
drop policy if exists "cheers insert" on public.cheers;
drop policy if exists "cheers read" on public.cheers;
create policy "cheers select" on public.cheers for select to authenticated using (auth.uid() in (from_user, to_user));
create policy "cheers insert" on public.cheers for insert to authenticated with check (from_user = auth.uid() and public.is_friend(from_user, to_user));
create policy "cheers read" on public.cheers for update to authenticated using (to_user = auth.uid()) with check (to_user = auth.uid());

-- ---------- Permisos de acceso para la app (la seguridad la ponen las reglas RLS) ----------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.is_friend(uuid, uuid) to authenticated;
grant execute on function public.is_connected(uuid, uuid) to authenticated;
grant execute on function public.find_friend_code(text) to authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
notify pgrst, 'reload schema';
