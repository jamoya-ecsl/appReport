-- Quita el permiso de ejecución público de public.rls_auto_enable() (aviso 0028/0029 de Supabase).
-- La función es la del disparador de eventos "ensure_rls", que activa RLS en cada tabla nueva de public.
-- Sigue funcionando: Postgres no comprueba EXECUTE al dispararse un disparador, solo al crearlo.
-- Conservan el permiso: postgres (propietario) y service_role.
-- No borra la función ni el disparador. Para deshacer:
--   grant execute on function public.rls_auto_enable() to public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
