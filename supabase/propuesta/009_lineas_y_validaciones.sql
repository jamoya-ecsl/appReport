-- =====================================================================
-- 009 · Módulo 1: tipos de tarea, cabecera sin finca/vehículo, 15 minutos,
--       escritura de líneas solo mediante guardar_parte() y validación del parte completo.
-- APLICADA 28/10/2026 desde el SQL Editor (tras 009a, con partes_cab vacía). Verificada 30/30 (pruebas_modulo1.sql).
--
-- Decisiones aplicadas (respuestas del 28/10):
--  * Nuevos tipos de tarea DESPLAZAMIENTO y MOTIVOS PERSONALES (TD001, TP001).
--  * Se eliminan partes_cab.finca, partes_cab.vehiculo y partes_cab.tiempo (vacía, sin significado confirmado).
--  * Todas las horas y duraciones en múltiplos de 15 min; h_ext >= 0 y en múltiplos de 0,25 h.
--  * Líneas ordenadas por h_ini. Reglas del parte completo (también para ADMIN):
--      - cada línea dentro de la jornada [h_ent, h_sal];
--      - sin solapes (se permiten huecos; una tarea puede empezar justo cuando acaba otra);
--      - MOTIVOS PERSONALES: solo horas (sin finca, parcela, vehículo ni apero);
--      - resto de tareas: finca obligatoria;
--      - DESPLAZAMIENTO: además vehículo obligatorio;
--      - la primera línea que no sea MOTIVOS PERSONALES debe ser un DESPLAZAMIENTO;
--      - para cambiar de finca hace falta un DESPLAZAMIENTO a la nueva finca
--        (las líneas de MOTIVOS PERSONALES no cuentan para la continuidad).
--  * partes_det solo se escribe mediante guardar_parte() (se elimina la política partes_det_write).
--  * Las reglas se comprueban al final de cada guardado (disparadores diferidos), también sin
--    sesión (SQL Editor), para que ningún camino las salte.
--
-- Fuera de este módulo (siguientes): estado Cerrado y funciones de cambio de estado (módulo 2),
-- configuración th_jornada y cálculo de h_ext (módulo 3), valores propuestos en la interfaz (módulo 4).
-- =====================================================================

-- 0) Precondición: los partes de prueba ya están borrados (009a).
do $$
begin
  if exists (select 1 from public.partes_cab) then
    raise exception 'La 009 exige partes_cab vacía: ejecuta antes 009a_borrar_partes_prueba.sql';
  end if;
end $$;

-- 1) Tipos de tarea nuevos -------------------------------------------------------------
alter table public.tareas drop constraint tareas_tipo_check;
alter table public.tareas add constraint tareas_tipo_check
  check (tipo in ('POR SUPERFICIE (HAS)', 'POR HORAS', 'DESPLAZAMIENTO', 'MOTIVOS PERSONALES'));

insert into public.tareas (cod_tar, tareas, tipo) values
  ('TD001', 'DESPLAZAMIENTO', 'DESPLAZAMIENTO'),
  ('TP001', 'MOTIVOS PERSONALES', 'MOTIVOS PERSONALES');

-- 2) Cabecera sin finca, vehículo ni tiempo ----------------------------------------------
-- El disparador de referencias activas de la cabecera solo vigilaba finca y vehiculo.
drop trigger partes_cab_referencias_activas on public.partes_cab;
alter table public.partes_cab
  drop column finca,
  drop column vehiculo,
  drop column tiempo;

-- 3) Múltiplos de 15 minutos (900 s) y horas extra -------------------------------------
alter table public.partes_cab
  add constraint partes_cab_cuartos_hora check (
        extract(epoch from h_ent) % 900 = 0 and extract(epoch from h_sal) % 900 = 0
    and extract(epoch from t_alm) % 900 = 0 and extract(epoch from t_com) % 900 = 0),
  add constraint partes_cab_h_ext_ok check (h_ext >= 0 and h_ext * 4 = trunc(h_ext * 4));

alter table public.partes_det
  add constraint partes_det_cuartos_hora check (
    extract(epoch from h_ini) % 900 = 0 and extract(epoch from h_fin) % 900 = 0);

alter table public.partes_mant
  add constraint partes_mant_cuartos_hora check (
        (h_ini is null or extract(epoch from h_ini) % 900 = 0)
    and (h_fin is null or extract(epoch from h_fin) % 900 = 0));

-- 4) Validación del parte completo ------------------------------------------------------
-- SECURITY DEFINER: debe ver todas las líneas del parte sea quien sea el usuario.
-- No se expone a la API (ver revoke al final): solo la llaman guardar_parte() y los disparadores.
create function public.validar_parte(p_id_parte uuid)
returns void
language plpgsql stable security definer
set search_path = public
as $$
declare
  c record;
  l record;
  v_prev_fin time;
  v_finca text;          -- finca en la que está el operario (la del último desplazamiento)
  v_desc text;
begin
  select h_ent, h_sal into c from public.partes_cab where id_parte = p_id_parte;
  if not found then
    return;  -- parte borrado: nada que validar
  end if;

  for l in
    select d.h_ini, d.h_fin, d.finca, d.parcela, d.vehiculo, d.apero, t.tipo, t.tareas
    from public.partes_det d
    join public.tareas t on t.cod_tar = d.tarea
    where d.id_parte = p_id_parte
    order by d.h_ini, d.h_fin
  loop
    v_desc := format('Tarea %s–%s (%s)', left(l.h_ini::text, 5), left(l.h_fin::text, 5), l.tareas);

    -- Dentro de la jornada
    if l.h_ini < c.h_ent or l.h_fin > c.h_sal then
      raise exception '%: debe estar dentro de la jornada (% – %)',
        v_desc, left(c.h_ent::text, 5), left(c.h_sal::text, 5);
    end if;

    -- Sin solapes (orden por h_ini)
    if v_prev_fin is not null and l.h_ini < v_prev_fin then
      raise exception '%: se solapa con la tarea anterior, que termina a las %', v_desc, left(v_prev_fin::text, 5);
    end if;
    v_prev_fin := l.h_fin;

    -- Campos según el tipo de tarea
    if l.tipo = 'MOTIVOS PERSONALES' then
      if l.finca is not null or l.parcela is not null or l.vehiculo is not null or l.apero is not null then
        raise exception '%: en MOTIVOS PERSONALES solo se indican las horas (sin finca, parcela, vehículo ni apero)', v_desc;
      end if;
      continue;  -- no cuenta para la continuidad de finca
    end if;

    if l.finca is null then
      raise exception '%: falta la finca', v_desc;
    end if;

    if l.tipo = 'DESPLAZAMIENTO' then
      if l.vehiculo is null then
        raise exception '%: un DESPLAZAMIENTO necesita vehículo', v_desc;
      end if;
      v_finca := l.finca;  -- destino del desplazamiento
    elsif v_finca is null then
      raise exception '%: la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un DESPLAZAMIENTO', v_desc;
    elsif l.finca <> v_finca then
      raise exception '%: para pasar de la finca % a la finca % hace falta antes un DESPLAZAMIENTO',
        v_desc, v_finca, l.finca;
    end if;
  end loop;
end $$;

-- Disparadores diferidos: comprueban el parte completo al final de la transacción,
-- por cualquier camino (guardar_parte, API directa a partes_cab, SQL Editor).
create function public.tg_validar_parte_diferido()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_table_name = 'partes_det' then
    perform public.validar_parte(case when tg_op = 'DELETE' then old.id_parte else new.id_parte end);
    if tg_op = 'UPDATE' and old.id_parte is distinct from new.id_parte then
      perform public.validar_parte(old.id_parte);
    end if;
  else
    perform public.validar_parte(new.id_parte);
  end if;
  return null;
end $$;

create constraint trigger partes_det_validar_parte
  after insert or update or delete on public.partes_det
  deferrable initially deferred
  for each row execute function public.tg_validar_parte_diferido();

-- Acortar la jornada puede dejar tareas fuera: se revalida al cambiar entrada o salida.
create constraint trigger partes_cab_validar_parte
  after update of h_ent, h_sal on public.partes_cab
  deferrable initially deferred
  for each row execute function public.tg_validar_parte_diferido();

-- 5) Líneas: solo mediante guardar_parte() -----------------------------------------------
-- Se mantiene partes_det_select (lectura). Sin política de escritura, la API no puede
-- insertar, modificar ni borrar líneas directamente (tampoco ADMIN).
drop policy partes_det_write on public.partes_det;

-- 6) guardar_parte(): ahora SECURITY DEFINER con sus propias comprobaciones de permiso ----
-- Como el propietario (postgres) se salta RLS, la función replica los permisos que antes
-- aplicaban las políticas. Los disparadores de partes_cab/partes_det siguen actuando con el
-- usuario conectado (app_rol() lee su sesión): guardas, supervisor solo revisa (004 y 008),
-- referencias activas, parcela↔finca.
create or replace function public.guardar_parte(p_id_parte uuid, p_cab jsonb, p_lineas jsonb default '[]')
returns uuid
language plpgsql security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_id uuid := p_id_parte;
  v_lineas jsonb := coalesce(p_lineas, '[]'::jsonb);
  v_conservar uuid[];
  v_rol public.rol_app := public.app_rol();
  v_cod text := public.app_cod_ope();
  v_operario text;
  v_estado public.estado_parte;
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;
  if jsonb_typeof(v_lineas) <> 'array' then
    raise exception 'p_lineas debe ser un array';
  end if;

  if v_id is null then
    -- Crear: cada uno los suyos; solo ADMIN a nombre de otro.
    v_operario := coalesce(nullif(p_cab ->> 'operario', ''), v_cod);
    if v_operario is distinct from v_cod and v_rol <> 'ADMIN' then
      raise exception 'Solo un ADMIN puede crear partes de otro operario' using errcode = '42501';
    end if;
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, mat_nave, obs)
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      (p_cab ->> 'h_ent')::time,
      (p_cab ->> 'h_sal')::time,
      coalesce((p_cab ->> 't_alm')::interval, '0'),
      coalesce((p_cab ->> 't_com')::interval, '0'),
      coalesce((p_cab ->> 'h_ext')::numeric, 0),
      coalesce((p_cab ->> 'mat_nave')::boolean, false),
      nullif(p_cab ->> 'obs', '')
    )
    returning id_parte into v_id;
  else
    -- Editar: ADMIN cualquiera; OPERARIO los suyos en Pendiente; SUPERVISOR ninguno.
    select operario, estado into v_operario, v_estado
    from public.partes_cab where id_parte = v_id
    for update;
    if not found
       or not (v_rol = 'ADMIN' or (v_rol = 'OPERARIO' and v_operario = v_cod and v_estado = 'Pendiente')) then
      raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
    end if;

    update public.partes_cab set
      fecha    = coalesce((p_cab ->> 'fecha')::date, fecha),
      h_ent    = (p_cab ->> 'h_ent')::time,
      h_sal    = (p_cab ->> 'h_sal')::time,
      t_alm    = coalesce((p_cab ->> 't_alm')::interval, '0'),
      t_com    = coalesce((p_cab ->> 't_com')::interval, '0'),
      h_ext    = coalesce((p_cab ->> 'h_ext')::numeric, 0),
      mat_nave = coalesce((p_cab ->> 'mat_nave')::boolean, false),
      obs      = nullif(p_cab ->> 'obs', '')
    where id_parte = v_id;
  end if;

  -- Las líneas con id_linea deben ser de este parte.
  if exists (
    select 1 from jsonb_array_elements(v_lineas) l
    where nullif(l ->> 'id_linea', '') is not null
      and not exists (select 1 from public.partes_det d
                      where d.id_linea = (l ->> 'id_linea')::uuid and d.id_parte = v_id)) then
    raise exception 'Alguna línea no pertenece a este parte' using errcode = '42501';
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

  -- Error inmediato y claro (los disparadores diferidos lo vuelven a comprobar al confirmar).
  perform public.validar_parte(v_id);
  return v_id;
end $$;

-- 7) panel_resumen(): horas por finca a partir de las líneas (la cabecera ya no tiene finca) ---
-- Único cambio respecto a la 007: 'horas_semana_por_finca' suma t_horas de las líneas con finca
-- (los MOTIVOS PERSONALES no tienen finca y no cuentan).
create or replace function public.panel_resumen()
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
                                 from (select d.finca, sum(d.t_horas) h
                                       from public.partes_det d
                                       join public.partes_cab c on c.id_parte = d.id_parte
                                       where c.fecha >= v_lunes and d.finca is not null
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
end $$;

-- 8) Permisos de ejecución -----------------------------------------------------------------
-- validar_parte es SECURITY DEFINER y sus mensajes describen líneas: no se expone a la API.
revoke execute on function public.validar_parte(uuid) from public, anon, authenticated;
revoke execute on function public.tg_validar_parte_diferido() from public, anon, authenticated;
revoke execute on function public.guardar_parte(uuid, jsonb, jsonb) from public, anon;
grant  execute on function public.guardar_parte(uuid, jsonb, jsonb) to authenticated, service_role;
revoke execute on function public.panel_resumen() from public, anon;
grant  execute on function public.panel_resumen() to authenticated, service_role;
-- (Coherencia con las anteriores: las funciones de disparador de la 008 tampoco se exponen.)
revoke execute on function public.tg_partes_cab_no_autorrevision(), public.tg_partes_det_supervisor_solo_revision()
  from public, anon, authenticated;
