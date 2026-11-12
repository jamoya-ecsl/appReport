-- =====================================================================
-- 020: permisos mínimos sobre las tablas (defensa en profundidad).
-- Hasta ahora RLS ya bloqueaba todo lo que no tiene política, pero los roles
-- conservaban permisos de tabla amplios (Supabase los da por defecto):
--   · anon (sin sesión): todos los permisos en casi todas las tablas.
--   · authenticated: escritura en partes_cab, partes_det, vistas y configuracion
--     sin política que la permita, y TRUNCATE (que RLS no controla).
-- Ahora cada rol tiene solo lo que sus políticas usan. Las funciones de la app
-- (SECURITY DEFINER) no dependen de estos permisos y no cambian.
-- Efecto visible: una escritura directa no permitida devuelve 42501 (antes, 0 filas).
-- =====================================================================

-- 1) Sin sesión: nada en el esquema public.
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- Lo que se cree en adelante tampoco nace abierto para anon.
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;

-- 2) Con sesión: se parte de cero y se da solo lo que usan las políticas.
revoke all on all tables in schema public from authenticated;

grant select on all tables in schema public to authenticated;   -- tablas y vistas; RLS decide las filas

-- Catálogos y usuarios: ADMIN todo; SUPERVISOR alta y edición (políticas *_admin, *_supervisor).
grant insert, update, delete on public.fincas, public.parcelas, public.tareas,
  public.vehiculos, public.aperos, public.operarios to authenticated;

-- Configuración: solo el ADMIN la modifica (política configuracion_update).
grant update on public.configuracion to authenticated;

-- partes_cab y partes_det: solo lectura directa; se escriben con guardar_parte(),
-- guardar_cabecera(), guardar_linea(), borrar_linea(), cerrar_parte(), revisar_parte() y borrar_parte().
-- auditoria, archivos_partes, tareas_realizadas, partes_pdf y las vistas: solo lectura.

-- Para deshacer (vuelve a lo de antes):
-- grant all on all tables in schema public to anon, authenticated;
-- grant all on all sequences in schema public to anon;
-- alter default privileges for role postgres in schema public grant all on tables to anon;
-- alter default privileges for role postgres in schema public grant all on sequences to anon;
-- alter default privileges for role postgres in schema public grant execute on functions to anon;
