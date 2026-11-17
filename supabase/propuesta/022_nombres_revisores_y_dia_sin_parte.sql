-- =====================================================================
-- 022 · Nombres de quien revisa y último día sin parte (16/11/2026)
--
-- 1) operarios_nombres(): el OPERARIO solo recibía su propia ficha, así que en el "Seguimiento" de sus partes
--    veía el código de quien lo aprobó ("T001") en vez del nombre. Ahora recibe también a los ADMIN y
--    SUPERVISOR (activos o no, porque un parte antiguo puede haberlo revisado alguien ya dado de baja).
--    Sigue sin ver a los demás operarios. ADMIN y SUPERVISOR siguen viendo a todos. Misma firma.
--
-- 2) ultimo_dia_sin_parte(p_operario): el operario está obligado a hacer todos los partes. Devuelve el día
--    laborable (lunes a viernes) más reciente, hasta hoy incluido, en el que el operario no tiene parte, para
--    que la app lo proponga en "Parte de otro día". Busca desde la fecha más reciente de estas tres:
--      · el día siguiente al último archivado (antes no se pueden crear partes),
--      · su primer parte (antes no estaba obligado),
--      · hace 60 días.
--    Sin partes todavía → hoy. Ningún día pendiente → null. No tiene en cuenta los festivos.
--    El OPERARIO siempre consulta lo suyo (p_operario se ignora); ADMIN y SUPERVISOR pueden pasar un código.
-- =====================================================================

create or replace function public.operarios_nombres()
returns table(cod_ope text, usuario text, activo boolean)
language sql
stable security definer
set search_path to 'public'
as $function$
  select o.cod_ope, o.usuario, o.activo
  from public.operarios o
  where public.app_es_gestor()
     or o.cod_ope = public.app_cod_ope()
     or (public.app_rol() is not null and o.rol_app in ('ADMIN', 'SUPERVISOR'))
  order by o.usuario
$function$;

create or replace function public.ultimo_dia_sin_parte(p_operario text default null)
returns date
language plpgsql
stable security definer
set search_path to 'public'
set "TimeZone" to 'Europe/Madrid'
as $function$
declare
  v_ope text;
  v_primero date;
  v_desde date;
  v_dia date;
begin
  if public.app_rol() is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;

  v_ope := case when public.app_es_gestor() and p_operario is not null then p_operario
                else public.app_cod_ope() end;

  select min(fecha) into v_primero from public.partes_cab where operario = v_ope;
  if v_primero is null then
    return current_date;
  end if;

  v_desde := greatest(v_primero,
                      current_date - 60,
                      coalesce((select max(hasta) + 1 from public.archivos_partes), v_primero));

  select max(d)::date into v_dia
  from generate_series(v_desde, current_date, interval '1 day') d
  where extract(isodow from d) between 1 and 5
    and not exists (select 1 from public.partes_cab c where c.operario = v_ope and c.fecha = d::date);

  return v_dia;
end $function$;

revoke all on function public.ultimo_dia_sin_parte(text) from public, anon;
grant execute on function public.ultimo_dia_sin_parte(text) to authenticated;
