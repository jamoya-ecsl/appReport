-- =====================================================================
-- 007 · Funciones para la app (Lovable)
--  * panel_resumen(): datos del panel de inicio según el rol del usuario.
--  * operarios_sin_parte(): operarios con rol OPERARIO activos sin parte en una fecha (solo gestores).
--  * guardar_parte() está en 007b_guardar_parte.sql.
-- Fechas "de hoy" en hora de España (Europe/Madrid); la BD trabaja en UTC.
-- =====================================================================

-- Operarios (rol OPERARIO, activos) sin parte en la fecha indicada. Solo para gestores.
create function public.operarios_sin_parte(p_fecha date default null)
returns table (cod_ope text, usuario text)
language sql stable security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
  select o.cod_ope, o.usuario
  from public.operarios o
  where public.app_es_gestor()
    and o.activo and o.rol_app = 'OPERARIO'
    and not exists (select 1 from public.partes_cab c
                    where c.operario = o.cod_ope and c.fecha = coalesce(p_fecha, current_date))
  order by o.usuario
$$;

-- Panel de inicio. Con permisos del usuario: cada rol solo cuenta lo que puede ver.
create function public.panel_resumen()
returns jsonb
language plpgsql stable security invoker
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_rol public.rol_app := public.app_rol();
  v_cod text := public.app_cod_ope();
  v_lunes date := date_trunc('week', current_date)::date;
  r jsonb;
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;

  r := jsonb_build_object(
    'rol', v_rol,
    'cod_ope', v_cod,
    'hoy', current_date,
    'partes_por_estado', (select coalesce(jsonb_object_agg(estado::text, n), '{}'::jsonb)
                          from (select estado, count(*) n from public.partes_cab group by estado) s),
    'mi_parte_hoy', (select jsonb_build_object('id_parte', id_parte, 'num_parte', num_parte, 'estado', estado)
                     from public.partes_cab where operario = v_cod and fecha = current_date),
    'ultimos_partes', (select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha desc, x.num_parte desc), '[]'::jsonb)
                       from (select id_parte, num_parte, operario, fecha, estado, tot_horas, comentario_supervisor
                             from public.partes_cab order by fecha desc, num_parte desc limit 5) x)
  );

  if v_rol in ('ADMIN', 'SUPERVISOR') then
    r := r || jsonb_build_object(
      'pendientes_revision', (select count(*) from public.partes_cab where estado = 'Pendiente'),
      'partes_hoy', (select count(*) from public.partes_cab where fecha = current_date),
      'horas_semana', (select coalesce(sum(tot_horas), 0) from public.partes_cab where fecha >= v_lunes),
      'horas_semana_por_finca', (select coalesce(jsonb_agg(jsonb_build_object('finca', f.cod_fin, 'nombre', f.finca, 'horas', s.h) order by s.h desc), '[]'::jsonb)
                                 from (select finca, sum(tot_horas) h from public.partes_cab where fecha >= v_lunes group by finca) s
                                 join public.fincas f on f.cod_fin = s.finca),
      'operarios_sin_parte_hoy', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb) from public.operarios_sin_parte(current_date) o),
      'maestros_activos', jsonb_build_object(
        'fincas',    (select count(*) from public.fincas    where activo),
        'parcelas',  (select count(*) from public.parcelas  where activo),
        'tareas',    (select count(*) from public.tareas    where activo),
        'vehiculos', (select count(*) from public.vehiculos where activo),
        'aperos',    (select count(*) from public.aperos    where activo))
    );
  end if;

  if v_rol = 'ADMIN' then
    r := r || jsonb_build_object('usuarios', (
      select jsonb_build_object(
        'activos', count(*) filter (where activo),
        'inactivos', count(*) filter (where not activo),
        'sin_cuenta_login', count(*) filter (where user_id is null))
      from public.operarios));
  end if;

  return r;
end $$;

revoke execute on function public.operarios_sin_parte(date), public.panel_resumen() from public, anon;
grant  execute on function public.operarios_sin_parte(date), public.panel_resumen() to authenticated, service_role;
