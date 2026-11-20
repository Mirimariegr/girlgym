-- GirlGym 💖 — Actualización: nombre de usuario (@nombre) y foto de perfil.
-- Pégalo entero en Supabase → SQL Editor → Run. Es seguro ejecutarlo varias veces.

-- 1) Nombre de usuario único y foto de perfil
alter table public.friend_profiles add column if not exists username text;
alter table public.friend_profiles add column if not exists avatar_path text;
alter table public.friend_profiles drop constraint if exists friend_profiles_username_format;
alter table public.friend_profiles add constraint friend_profiles_username_format check (username is null or username ~ '^[a-z0-9._]{3,20}$');
create unique index if not exists friend_profiles_username_key on public.friend_profiles (username);

-- 2) Buscar a una amiga por su @nombre (solo devuelve esa persona, nombre y emoji)
create or replace function public.find_friend_username(p_username text)
returns table (user_id uuid, name text, emoji text)
language sql stable security definer set search_path = public as $$
  select user_id, name, emoji from friend_profiles
  where username = lower(trim(both '@' from trim(p_username))) and user_id <> auth.uid() limit 1;
$$;
revoke all on function public.find_friend_username(text) from public, anon;
grant execute on function public.find_friend_username(text) to authenticated;

-- 3) Fotos de perfil: carpeta privada. Las ven tú y quien esté conectada contigo (amigas o solicitudes).
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', false) on conflict (id) do nothing;
drop policy if exists "avatar files select" on storage.objects;
drop policy if exists "avatar files insert" on storage.objects;
drop policy if exists "avatar files delete" on storage.objects;
create policy "avatar files select" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and ((storage.foldername(name))[1] = auth.uid()::text
         or public.is_connected(auth.uid(), ((storage.foldername(name))[1])::uuid)));
create policy "avatar files insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

notify pgrst, 'reload schema';
