-- GirlGym 💖 — Permisos para que la app pueda usar las tablas.
-- Es seguro ejecutarlo varias veces. La seguridad la siguen poniendo las reglas RLS:
-- cada persona solo puede ver y tocar lo suyo (y lo de sus amigas aceptadas).
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.is_friend(uuid, uuid) to authenticated;
grant execute on function public.is_connected(uuid, uuid) to authenticated;
grant execute on function public.find_friend_code(text) to authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
notify pgrst, 'reload schema';
