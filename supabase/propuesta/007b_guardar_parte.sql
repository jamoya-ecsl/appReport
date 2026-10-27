-- =====================================================================
-- 007b · guardar_parte(): cabecera + líneas en UNA transacción.
-- Se ejecuta con los permisos del usuario (SECURITY INVOKER): aplica RLS y todos los disparadores.
-- Separado de la 007 porque contiene un DELETE (de las líneas que se quitan del parte) y el
-- conector de Supabase bloquea esas sentencias: aplicar desde el SQL Editor del Dashboard.
--
-- p_cab: fecha, h_ent, h_sal, t_alm, t_com (intervalos, p. ej. '30 minutes'), h_ext, mat_nave,
--        finca, vehiculo, obs; y operario solo al crear (si falta, el usuario conectado).
-- p_lineas: array. Con id_linea → se actualiza esa línea; sin id_linea → línea nueva;
--           las líneas del parte que no vengan en el array se borran.
-- Fechas "de hoy" en hora de España (Europe/Madrid).
-- =====================================================================
create function public.guardar_parte(p_id_parte uuid, p_cab jsonb, p_lineas jsonb default '[]')
returns uuid
language plpgsql security invoker
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_id uuid := p_id_parte;
  v_lineas jsonb := coalesce(p_lineas, '[]'::jsonb);
  v_conservar uuid[];
begin
  if jsonb_typeof(v_lineas) <> 'array' then
    raise exception 'p_lineas debe ser un array';
  end if;

  if v_id is null then
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, mat_nave, finca, vehiculo, obs)
    values (
      coalesce(nullif(p_cab ->> 'operario', ''), public.app_cod_ope()),
      coalesce((p_cab ->> 'fecha')::date, current_date),
      (p_cab ->> 'h_ent')::time,
      (p_cab ->> 'h_sal')::time,
      coalesce((p_cab ->> 't_alm')::interval, '0'),
      coalesce((p_cab ->> 't_com')::interval, '0'),
      coalesce((p_cab ->> 'h_ext')::numeric, 0),
      coalesce((p_cab ->> 'mat_nave')::boolean, false),
      nullif(p_cab ->> 'finca', ''),
      nullif(p_cab ->> 'vehiculo', ''),
      nullif(p_cab ->> 'obs', '')
    )
    returning id_parte into v_id;
  else
    update public.partes_cab set
      fecha    = coalesce((p_cab ->> 'fecha')::date, fecha),
      h_ent    = (p_cab ->> 'h_ent')::time,
      h_sal    = (p_cab ->> 'h_sal')::time,
      t_alm    = coalesce((p_cab ->> 't_alm')::interval, '0'),
      t_com    = coalesce((p_cab ->> 't_com')::interval, '0'),
      h_ext    = coalesce((p_cab ->> 'h_ext')::numeric, 0),
      mat_nave = coalesce((p_cab ->> 'mat_nave')::boolean, false),
      finca    = nullif(p_cab ->> 'finca', ''),
      vehiculo = nullif(p_cab ->> 'vehiculo', ''),
      obs      = nullif(p_cab ->> 'obs', '')
    where id_parte = v_id;
    if not found then
      raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
    end if;
  end if;

  select coalesce(array_agg((l ->> 'id_linea')::uuid), '{}')
    into v_conservar
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is not null;

  delete from public.partes_det
  where id_parte = v_id and not (id_linea = any (v_conservar));

  update public.partes_det d set
    tarea    = l ->> 'tarea',
    finca    = nullif(l ->> 'finca', ''),
    parcela  = nullif(l ->> 'parcela', ''),
    vehiculo = nullif(l ->> 'vehiculo', ''),
    apero    = nullif(l ->> 'apero', ''),
    h_ini    = (l ->> 'h_ini')::time,
    h_fin    = (l ->> 'h_fin')::time,
    obs      = nullif(l ->> 'obs', '')
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is not null
    and d.id_linea = (l ->> 'id_linea')::uuid
    and d.id_parte = v_id;

  insert into public.partes_det (id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs)
  select v_id, l ->> 'tarea', nullif(l ->> 'finca', ''), nullif(l ->> 'parcela', ''),
         nullif(l ->> 'vehiculo', ''), nullif(l ->> 'apero', ''),
         (l ->> 'h_ini')::time, (l ->> 'h_fin')::time, nullif(l ->> 'obs', '')
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is null;

  return v_id;
end $$;

revoke execute on function public.guardar_parte(uuid, jsonb, jsonb) from public, anon;
grant  execute on function public.guardar_parte(uuid, jsonb, jsonb) to authenticated, service_role;
