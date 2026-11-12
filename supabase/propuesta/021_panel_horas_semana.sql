-- =====================================================================
-- 021 · Panel de inicio: horas de la semana solo de lunes a domingo
-- `horas_semana` y `horas_semana_por_finca` filtraban con `fecha >= v_lunes` sin límite superior,
-- así que sumaban también los partes de semanas futuras (con el mes de prueba, 717 h).
-- Ahora: `fecha between v_lunes and v_domingo`. El resto de la función (versión de la 010) no cambia.
-- CREATE OR REPLACE conserva los permisos (EXECUTE para authenticated).
-- =====================================================================
create or replace function public.panel_resumen()
returns jsonb
language plpgsql
stable
set search_path to 'public'
set "TimeZone" to 'Europe/Madrid'
as $function$
declare
  v_rol public.rol_app := public.app_rol();
  v_cod text := public.app_cod_ope();
  v_lunes date := date_trunc('week', current_date)::date;
  v_domingo date := date_trunc('week', current_date)::date + 6;
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
      'pendientes_revision', (select count(*) from public.partes_cab where estado = 'Cerrado'),
      'sin_cerrar', (select count(*) from public.partes_cab where estado = 'Pendiente'),
      'partes_hoy', (select count(*) from public.partes_cab where fecha = current_date),
      'horas_semana', (select coalesce(sum(tot_horas), 0) from public.partes_cab
                       where fecha between v_lunes and v_domingo),
      'horas_semana_por_finca', (select coalesce(jsonb_agg(jsonb_build_object('finca', f.cod_fin, 'nombre', f.finca, 'horas', s.h) order by s.h desc), '[]'::jsonb)
                                 from (select d.finca, sum(d.t_horas) h
                                       from public.partes_det d
                                       join public.partes_cab c on c.id_parte = d.id_parte
                                       where c.fecha between v_lunes and v_domingo and d.finca is not null
                                       group by d.finca) s
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
end $function$;
