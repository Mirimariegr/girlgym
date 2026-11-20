-- GirlGym 💞 — Actualización: Feed con fotos y mensajes + permisos.
-- Pégalo entero en Supabase → SQL Editor → Run. Es seguro ejecutarlo varias veces.

-- 1) Publicaciones libres ("post") además de entrenos, insignias, pasos y respuestas
alter table public.posts drop constraint if exists posts_kind_check;
alter table public.posts add constraint posts_kind_check check (kind in ('workout','badge','road','answer','post'));

-- 2) Fotos del feed: carpeta privada. Solo las ven tú y tus amigas aceptadas.
insert into storage.buckets (id, name, public) values ('feed', 'feed', false) on conflict (id) do nothing;
drop policy if exists "feed files select" on storage.objects;
drop policy if exists "feed files insert" on storage.objects;
drop policy if exists "feed files delete" on storage.objects;
create policy "feed files select" on storage.objects for select to authenticated
  using (bucket_id = 'feed' and ((storage.foldername(name))[1] = auth.uid()::text
         or public.is_friend(auth.uid(), ((storage.foldername(name))[1])::uuid)));
create policy "feed files insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'feed' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "feed files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'feed' and (storage.foldername(name))[1] = auth.uid()::text);

-- 3) Permisos de acceso para la app (la seguridad la siguen poniendo las reglas RLS)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.is_friend(uuid, uuid) to authenticated;
grant execute on function public.is_connected(uuid, uuid) to authenticated;
grant execute on function public.find_friend_code(text) to authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
notify pgrst, 'reload schema';
