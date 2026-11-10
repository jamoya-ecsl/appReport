-- =====================================================================
-- 018 · Módulo 9: el mantenimiento pasa a ser un tipo de tarea (docs/PLAN_MODULOS_9_Y_10.md, paso 2).
-- PROPUESTA pendiente de revisión: no aplicar hasta que se autorice.
-- Ejecutar en Dashboard → SQL Editor (contiene DROP TABLE, DROP COLUMN y DROP CONSTRAINT, que el conector bloquea).
-- IRREVERSIBLE: borra la tabla partes_mant y la columna partes_cab.mat_nave. Antes comprueba que están
-- vacías / sin uso y, si no, se para sin cambiar nada.
-- Precondición: 017 aplicada.
--
-- Decisiones (respuestas del 10/11/2026):
--  * Dos tipos de tarea nuevos, con una tarea cada uno (el ADMIN puede añadir más de cada tipo):
--      MANTENIMIENTO NAVE      (TN001): solo horas, como MOTIVOS PERSONALES. Puede ser la primera tarea.
--      MANTENIMIENTO VEHÍCULOS (TV001): vehículo o apero (al menos uno), sin finca ni parcela.
--                                       No puede ser la primera tarea.
--  * Los mantenimientos no llevan finca y no cambian la finca en la que se está: después de uno se puede
--    seguir en la misma finca sin otro DESPLAZAMIENTO.
--  * La primera tarea (sin contar MOTIVOS PERSONALES) es DESPLAZAMIENTO o MANTENIMIENTO NAVE.
--  * Para cerrar un parte (y para que uno ya cerrado siga siendo válido) hace falta al menos una tarea que no
--    sea MOTIVOS PERSONALES. Sustituye a la regla de mat_nave.
--  * Sin cambios en el archivo: archivar_partes() y tareas_resumen solo excluyen MOTIVOS PERSONALES y
--    DESPLAZAMIENTO, así que los mantenimientos se conservan en tareas_realizadas. fin_vuelta no se
--    pregunta en ellos (requiere_fin_vuelta solo mira POR SUPERFICIE y POR HORAS).
-- Funciones que cambian (partiendo de la versión aplicada, leída de la BD el 10/11/2026):
--   validar_parte() (014), tg_partes_cab_estado() (014), guardar_parte() (014), pdf_datos() (016).
-- Comprobado el 10/11/2026: partes_mant vacía, 0 partes con mat_nave, 0 PDF generados.
-- =====================================================================

-- 0) Precondiciones ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'partes_cab_pausas_ok') then
    raise exception 'La 018 exige la 017 aplicada';
  end if;
  if exists (select 1 from public.partes_mant) then
    raise exception 'partes_mant tiene filas: la 018 la borraría. Revisar antes de aplicar';
  end if;
  if exists (select 1 from public.partes_cab where mat_nave) then
    raise exception 'Hay partes con mat_nave marcado: la 018 borraría ese dato. Revisar antes de aplicar';
  end if;
end $$;

-- 1) Tipos y tareas nuevos ---------------------------------------------------------------------
alter table public.tareas drop constraint tareas_tipo_check;
alter table public.tareas add constraint tareas_tipo_check check (tipo in (
  'POR SUPERFICIE (HAS)', 'POR HORAS', 'DESPLAZAMIENTO', 'MOTIVOS PERSONALES',
  'MANTENIMIENTO NAVE', 'MANTENIMIENTO VEHÍCULOS'));

insert into public.tareas (cod_tar, tareas, tipo) values
  ('TN001', 'MANTENIMIENTO NAVE', 'MANTENIMIENTO NAVE'),
  ('TV001', 'MANTENIMIENTO VEHÍCULOS', 'MANTENIMIENTO VEHÍCULOS');

-- 2) ¿Tiene el parte alguna tarea que no sea MOTIVOS PERSONALES? ---------------------------------
create function public.parte_tiene_trabajo(p_id_parte uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.partes_det d
    join public.tareas t on t.cod_tar = d.tarea
    where d.id_parte = p_id_parte
      and t.tipo is distinct from 'MOTIVOS PERSONALES');
$$;

-- 3) validar_parte(): reglas de los mantenimientos ---------------------------------------------
-- Cambios respecto a la 014 (marcados con «018»).
create or replace function public.validar_parte(p_id_parte uuid)
returns void
language plpgsql stable security definer
set search_path = public
as $$
declare
  c record;
  l record;
  v_prev_fin time;
  v_finca text;
  v_desc text;
  v_pend text;
  v_hay_previa boolean := false;   -- «018» ya hay alguna tarea que no es MOTIVOS PERSONALES
begin
  select h_ent, h_sal, estado into c from public.partes_cab where id_parte = p_id_parte;
  if not found then
    return;
  end if;

  if c.estado <> 'Pendiente' and not public.parte_tiene_trabajo(p_id_parte) then              -- «018»
    raise exception 'El parte está %: necesita al menos una tarea (sin contar MOTIVOS PERSONALES)', c.estado;
  end if;

  if c.estado <> 'Pendiente' then
    v_pend := public.fin_vuelta_pendientes(p_id_parte);
    if v_pend is not null then
      raise exception 'El parte está %: indica si termina la vuelta en: %', c.estado, v_pend;
    end if;
  end if;

  for l in
    select d.h_ini, d.h_fin, d.finca, d.parcela, d.vehiculo, d.apero, t.tipo, t.tareas
    from public.partes_det d
    join public.tareas t on t.cod_tar = d.tarea
    where d.id_parte = p_id_parte
    order by d.h_ini, d.h_fin
  loop
    v_desc := format('Tarea %s–%s (%s)', left(l.h_ini::text, 5), left(l.h_fin::text, 5), l.tareas);

    if l.h_ini < c.h_ent or l.h_fin > c.h_sal then
      raise exception '%: debe estar dentro de la jornada (% – %)',
        v_desc, left(c.h_ent::text, 5), left(c.h_sal::text, 5);
    end if;

    if v_prev_fin is not null and l.h_ini < v_prev_fin then
      raise exception '%: se solapa con la tarea anterior, que termina a las %', v_desc, left(v_prev_fin::text, 5);
    end if;
    v_prev_fin := l.h_fin;

    if l.tipo = 'MOTIVOS PERSONALES' then
      if l.finca is not null or l.parcela is not null or l.vehiculo is not null or l.apero is not null then
        raise exception '%: en MOTIVOS PERSONALES solo se indican las horas (sin finca, parcela, vehículo ni apero)', v_desc;
      end if;
      continue;
    end if;

    if l.tipo = 'MANTENIMIENTO NAVE' then                                                      -- «018»
      if l.finca is not null or l.parcela is not null or l.vehiculo is not null or l.apero is not null then
        raise exception '%: en MANTENIMIENTO NAVE solo se indican las horas (sin finca, parcela, vehículo ni apero)', v_desc;
      end if;
      v_hay_previa := true;
      continue;
    end if;

    if l.tipo = 'MANTENIMIENTO VEHÍCULOS' then                                                 -- «018»
      if not v_hay_previa then
        raise exception '%: la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un DESPLAZAMIENTO o un MANTENIMIENTO NAVE', v_desc;
      end if;
      if l.finca is not null or l.parcela is not null then
        raise exception '%: en MANTENIMIENTO VEHÍCULOS no se indica finca ni parcela', v_desc;
      end if;
      if l.vehiculo is null and l.apero is null then
        raise exception '%: un MANTENIMIENTO VEHÍCULOS necesita vehículo o apero', v_desc;
      end if;
      continue;
    end if;

    if l.finca is null then
      raise exception '%: falta la finca', v_desc;
    end if;

    if l.tipo = 'DESPLAZAMIENTO' then
      if l.vehiculo is null then
        raise exception '%: un DESPLAZAMIENTO necesita vehículo', v_desc;
      end if;
      v_finca := l.finca;
    elsif not v_hay_previa then                                                                -- «018»
      raise exception '%: la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un DESPLAZAMIENTO o un MANTENIMIENTO NAVE', v_desc;
    elsif v_finca is null then                                                                 -- «018» tras MANTENIMIENTO NAVE
      raise exception '%: para trabajar en la finca % hace falta antes un DESPLAZAMIENTO', v_desc, l.finca;
    elsif l.finca <> v_finca then
      raise exception '%: para pasar de la finca % a la finca % hace falta antes un DESPLAZAMIENTO',
        v_desc, v_finca, l.finca;
    end if;
    v_hay_previa := true;
  end loop;
end $$;

-- 4) Regla de cierre ----------------------------------------------------------------------------
-- Único cambio respecto a la 014: al cerrar, al menos una tarea que no sea MOTIVOS PERSONALES («018»).
create or replace function public.tg_partes_cab_estado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  c_no_contenido constant text[] := array['estado', 'comentario_supervisor', 'supervisor_revisa', 'fecha_revision',
                                          'cerrado_por', 'fecha_cierre', 'fch_modificacion', 'tot_horas'];
  v_con_sesion boolean := auth.jwt() ->> 'email' is not null;
  v_rol text;
  v_pend text;
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'Pendiente' then
      raise exception 'Un parte nuevo empieza siempre en Pendiente';
    end if;
    new.cerrado_por := null;
    new.fecha_cierre := null;
    return new;
  end if;

  if new.estado is distinct from old.estado then
    if not ((old.estado = 'Pendiente' and new.estado = 'Cerrado')
         or (old.estado = 'Cerrado'   and new.estado in ('Aprobado', 'Rechazado'))) then
      raise exception 'Cambio de estado no permitido: % → %', old.estado, new.estado;
    end if;
    if new.estado = 'Cerrado' then
      if not public.parte_tiene_trabajo(new.id_parte) then                                     -- «018»
        raise exception 'Para cerrar un parte hace falta al menos una tarea (sin contar MOTIVOS PERSONALES)';
      end if;
      v_pend := public.fin_vuelta_pendientes(new.id_parte);
      if v_pend is not null then
        raise exception 'Para cerrar el parte indica si termina la vuelta en: %', v_pend;
      end if;
      new.cerrado_por := public.app_cod_ope();
      new.fecha_cierre := now();
    end if;
  else
    new.cerrado_por := old.cerrado_por;
    new.fecha_cierre := old.fecha_cierre;
  end if;

  if old.estado <> 'Pendiente' and v_con_sesion
     and (to_jsonb(new) - c_no_contenido) is distinct from (to_jsonb(old) - c_no_contenido) then
    v_rol := coalesce(public.app_rol()::text, '');
    if not (v_rol = 'ADMIN' or (v_rol = 'SUPERVISOR' and old.estado = 'Cerrado')) then
      raise exception 'El parte está %: %', old.estado,
        case when old.estado = 'Cerrado' then 'solo un SUPERVISOR o un ADMIN pueden modificar su contenido'
             else 'solo un ADMIN puede modificar su contenido' end;
    end if;
  end if;
  return new;
end $$;

-- 5) guardar_parte(): sin mat_nave ----------------------------------------------------------------
-- Único cambio respecto a la 014: ya no lee ni escribe mat_nave («018»). Si la app aún lo envía, se ignora.
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
  v_ini jsonb;
  v_h_ent time;
  v_h_sal time;
  v_t_alm interval;
  v_t_com interval;
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;
  if jsonb_typeof(v_lineas) <> 'array' then
    raise exception 'p_lineas debe ser un array';
  end if;

  v_ini   := public.valores_iniciales_parte();
  v_h_ent := coalesce(nullif(trim(p_cab ->> 'h_ent'), ''), v_ini ->> 'h_ent')::time;
  v_h_sal := coalesce(nullif(trim(p_cab ->> 'h_sal'), ''), v_ini ->> 'h_sal')::time;
  v_t_alm := coalesce(nullif(trim(p_cab ->> 't_alm'), ''), (v_ini ->> 't_alm_min') || ' minutes')::interval;
  v_t_com := coalesce(nullif(trim(p_cab ->> 't_com'), ''), (v_ini ->> 't_com_min') || ' minutes')::interval;

  if v_id is null then
    v_operario := coalesce(nullif(p_cab ->> 'operario', ''), v_cod);
    if v_operario is distinct from v_cod and v_rol not in ('ADMIN', 'SUPERVISOR') then
      raise exception 'Solo un ADMIN o un SUPERVISOR pueden crear partes de otro operario' using errcode = '42501';
    end if;
    if not exists (select 1 from public.operarios where cod_ope = v_operario and activo) then
      raise exception 'El operario % no existe o está dado de baja', v_operario;
    end if;
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, obs)   -- «018»
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      v_h_ent,
      v_h_sal,
      v_t_alm,
      v_t_com,
      coalesce((p_cab ->> 'h_ext')::numeric, 0),
      coalesce((p_cab ->> 'h_ext_manual')::boolean, false),
      nullif(p_cab ->> 'obs', '')
    )
    returning id_parte into v_id;
  else
    select operario, estado into v_operario, v_estado
    from public.partes_cab where id_parte = v_id
    for update;
    if not found
       or not (v_rol = 'ADMIN'
               or (v_rol = 'SUPERVISOR' and v_estado in ('Pendiente', 'Cerrado'))
               or (v_rol = 'OPERARIO' and v_operario = v_cod and v_estado = 'Pendiente')) then
      raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
    end if;

    update public.partes_cab set                                                               -- «018» sin mat_nave
      fecha        = coalesce((p_cab ->> 'fecha')::date, fecha),
      h_ent        = v_h_ent,
      h_sal        = v_h_sal,
      t_alm        = v_t_alm,
      t_com        = v_t_com,
      h_ext        = coalesce((p_cab ->> 'h_ext')::numeric, h_ext),
      h_ext_manual = coalesce((p_cab ->> 'h_ext_manual')::boolean, h_ext_manual),
      obs          = nullif(p_cab ->> 'obs', '')
    where id_parte = v_id;
  end if;

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
    tarea      = l ->> 'tarea',
    finca      = nullif(l ->> 'finca', ''),
    parcela    = nullif(l ->> 'parcela', ''),
    vehiculo   = nullif(l ->> 'vehiculo', ''),
    apero      = nullif(l ->> 'apero', ''),
    h_ini      = (l ->> 'h_ini')::time,
    h_fin      = (l ->> 'h_fin')::time,
    obs        = nullif(l ->> 'obs', ''),
    fin_vuelta = nullif(l ->> 'fin_vuelta', '')::boolean
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is not null
    and d.id_linea = (l ->> 'id_linea')::uuid
    and d.id_parte = v_id;

  insert into public.partes_det (id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs, fin_vuelta)
  select v_id, l ->> 'tarea', nullif(l ->> 'finca', ''), nullif(l ->> 'parcela', ''),
         nullif(l ->> 'vehiculo', ''), nullif(l ->> 'apero', ''),
         (l ->> 'h_ini')::time, (l ->> 'h_fin')::time, nullif(l ->> 'obs', ''),
         nullif(l ->> 'fin_vuelta', '')::boolean
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is null;

  perform public.validar_parte(v_id);
  return v_id;
end $$;

-- 6) pdf_datos(): sin mat_nave --------------------------------------------------------------------
-- Único cambio respecto a la 016: fuera 'mat_nave' («018»). Se sustituye ANTES de borrar la columna:
-- al ser una función SQL, la BD no impediría borrarla y la función fallaría después.
create or replace function public.pdf_datos(p_id_parte uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'num_parte', c.num_parte,
    'fecha', c.fecha,
    'campana', public.campana_de(c.fecha),
    'operario', c.operario,
    'nom_operario', (select o.usuario from operarios o where o.cod_ope = c.operario),
    'h_ent', to_char(c.h_ent, 'HH24:MI'),
    'h_sal', to_char(c.h_sal, 'HH24:MI'),
    't_alm_min', (extract(epoch from c.t_alm) / 60)::int,
    't_com_min', (extract(epoch from c.t_com) / 60)::int,
    'tot_horas', c.tot_horas,
    'h_ext', c.h_ext,
    'ht_tareas', public.ht_tareas(c),
    'obs', c.obs,
    'cerrado_por', c.cerrado_por,
    'nom_cerrado_por', (select o.usuario from operarios o where o.cod_ope = c.cerrado_por),
    'fecha_cierre', c.fecha_cierre,
    'supervisor_revisa', c.supervisor_revisa,
    'nom_supervisor', (select o.usuario from operarios o where o.cod_ope = c.supervisor_revisa),
    'fecha_revision', c.fecha_revision,
    'comentario_supervisor', c.comentario_supervisor,
    'lineas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'h_ini', to_char(d.h_ini, 'HH24:MI'),
               'h_fin', to_char(d.h_fin, 'HH24:MI'),
               'horas', d.t_horas,
               'tarea', d.tarea,
               'nom_tarea', t.tareas,
               'tipo', t.tipo,
               'finca', f.finca,
               'parcela', p.nom_parc,
               'vehiculo', case when v.id_mat is null then null else v.alias || ' · ' || v.equipo end,
               'apero', case when a.id_bas is null then null else a.alias || ' · ' || a.equipo end,
               'fin_vuelta', case when not public.requiere_fin_vuelta(d) then null
                                  when d.fin_vuelta then 'Sí' else 'No' end,
               'obs', d.obs)
             order by d.h_ini, d.h_fin)
      from partes_det d
      left join tareas t on t.cod_tar = d.tarea
      left join fincas f on f.cod_fin = d.finca
      left join parcelas p on p.cod_par = d.parcela
      left join vehiculos v on v.id_mat = d.vehiculo
      left join aperos a on a.id_bas = d.apero
      where d.id_parte = c.id_parte), '[]'::jsonb))
  from partes_cab c
  where c.id_parte = p_id_parte;
$$;

-- 7) Fuera partes_mant y mat_nave -------------------------------------------------------------------
-- Con la tabla se van sus políticas y sus disparadores (partes_mant_autor, partes_mant_referencias_activas).
-- tg_validar_referencias_activas() se queda: la usan partes_cab y partes_det.
drop table public.partes_mant;
drop function public.tg_partes_mant_autor();
alter table public.partes_cab drop column mat_nave;

-- 8) Permisos ---------------------------------------------------------------------------------------
revoke execute on function public.parte_tiene_trabajo(uuid) from public, anon, authenticated;
