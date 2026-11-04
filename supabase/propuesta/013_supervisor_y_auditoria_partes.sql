-- =====================================================================
-- 013 · Módulo 5: el supervisor crea y corrige partes; auditoría de partes y tareas.
-- APLICADA 04/11/2026 desde el SQL Editor (contiene DROP TRIGGER/FUNCTION, que el conector bloquea).
-- Verificada 18/18 (pruebas_modulo5.sql); módulos 1, 2, 3, 4 y por rol siguen correctos.
-- Precondición: 012 aplicada.
--
-- Decisiones aplicadas (respuestas del 04/11/2026, docs/DECISIONES_MODULOS_4_A_8.md):
--  * El SUPERVISOR crea partes a nombre de cualquier operario activo (como el ADMIN) y puede
--    aprobar o rechazar los que él creó. Sigue sin poder revisar partes cuyo titular es él mismo.
--  * El SUPERVISOR edita (cabecera y tareas) los partes en Pendiente y en Cerrado, de cualquier
--    operario. Aprobados y Rechazados: solo el ADMIN. OPERARIO: sin cambios (los suyos en Pendiente).
--  * Ningún parte puede crearse a nombre de un operario dado de baja (tampoco por el ADMIN).
--  * Un parte que ya no está Pendiente y no es de mantenimiento en nave debe conservar al menos una
--    tarea (antes solo se comprobaba al cerrar; ahora también al corregirlo, para todos los roles).
--  * Auditoría de partes_cab y partes_det en la tabla auditoria, como los catálogos:
--      - registro = nº de parte (también en las tareas), para ver todo el historial de un parte;
--      - ALTA (fila completa), MODIFICACION (solo lo que cambia: {campo: {antes, despues}}),
--        BORRADO (parte completo con sus tareas, una sola fila);
--      - quién (email y cod_ope) y cuándo. Quien crea = ALTA; quien cierra/aprueba = MODIFICACION
--        de 'estado' (además de cerrado_por y supervisor_revisa en el propio parte).
--      - Lectura: ADMIN y SUPERVISOR (política actual); OPERARIO nada.
--    borrar_parte() deja de escribir su propia copia: la escribe el disparador, también cuando se
--    borra desde el SQL Editor (usuario 'sistema').
--  * Se eliminan los disparadores que impedían al supervisor tocar el contenido (004 y 008): sus
--    reglas pasan a tg_partes_cab_estado y tg_partes_det_parte_abierto (010), y la escritura directa
--    por la API sigue cerrada (sin políticas de escritura en partes_cab ni partes_det).
-- =====================================================================

-- 0) Precondición ------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.valores_iniciales_parte()') is null then
    raise exception 'La 013 exige la 012 aplicada';
  end if;
end $$;

-- 1) Fuera los bloqueos del supervisor de la 004 y la 008 ----------------------------------
drop trigger partes_cab_supervisor_solo_revision on public.partes_cab;
drop function public.tg_partes_cab_supervisor_solo_revision();
drop trigger partes_det_supervisor_solo_revision on public.partes_det;
drop function public.tg_partes_det_supervisor_solo_revision();

-- 2) Contenido de un parte que ya no está Pendiente ----------------------------------------
-- Cambio respecto a la 010: el SUPERVISOR también puede modificar el contenido de un parte Cerrado.
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
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'Pendiente' then
      raise exception 'Un parte nuevo empieza siempre en Pendiente';
    end if;
    new.cerrado_por := null;
    new.fecha_cierre := null;
    return new;
  end if;

  -- Transiciones permitidas (para todos, también sin sesión)
  if new.estado is distinct from old.estado then
    if not ((old.estado = 'Pendiente' and new.estado = 'Cerrado')
         or (old.estado = 'Cerrado'   and new.estado in ('Aprobado', 'Rechazado'))) then
      raise exception 'Cambio de estado no permitido: % → %', old.estado, new.estado;
    end if;
    if new.estado = 'Cerrado' then
      if not new.mat_nave and not exists (select 1 from public.partes_det where id_parte = new.id_parte) then
        raise exception 'Para cerrar un parte sin mantenimiento en nave hace falta al menos una tarea';
      end if;
      new.cerrado_por := public.app_cod_ope();
      new.fecha_cierre := now();
    end if;
  else
    new.cerrado_por := old.cerrado_por;
    new.fecha_cierre := old.fecha_cierre;
  end if;

  -- Contenido de un parte que no está Pendiente: ADMIN siempre; SUPERVISOR si está Cerrado
  -- (sin sesión, SQL Editor: sin límite).
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

-- Mismo criterio para las tareas.
create or replace function public.tg_partes_det_parte_abierto()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_estado public.estado_parte;
  v_rol text;
begin
  if auth.jwt() ->> 'email' is not null then
    v_rol := coalesce(public.app_rol()::text, '');
    if v_rol <> 'ADMIN' then
      select estado into v_estado from public.partes_cab
      where id_parte = case when tg_op = 'DELETE' then old.id_parte else new.id_parte end;
      if found and v_estado <> 'Pendiente' and not (v_rol = 'SUPERVISOR' and v_estado = 'Cerrado') then
        raise exception 'El parte está %: %', v_estado,
          case when v_estado = 'Cerrado' then 'solo un SUPERVISOR o un ADMIN pueden modificar sus tareas'
               else 'solo un ADMIN puede modificar sus tareas' end;
      end if;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- 3) validar_parte(): un parte no Pendiente sin nave conserva al menos una tarea --------------
-- Único cambio respecto a la 009: lee también estado y mat_nave y comprueba esa regla.
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
begin
  select h_ent, h_sal, estado, mat_nave into c from public.partes_cab where id_parte = p_id_parte;
  if not found then
    return;  -- parte borrado: nada que validar
  end if;

  -- «013» Al corregir un parte ya cerrado no se pueden quitar todas sus tareas.
  if c.estado <> 'Pendiente' and not c.mat_nave
     and not exists (select 1 from public.partes_det where id_parte = p_id_parte) then
    raise exception 'El parte está %: sin mantenimiento en nave necesita al menos una tarea', c.estado;
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

    if l.finca is null then
      raise exception '%: falta la finca', v_desc;
    end if;

    if l.tipo = 'DESPLAZAMIENTO' then
      if l.vehiculo is null then
        raise exception '%: un DESPLAZAMIENTO necesita vehículo', v_desc;
      end if;
      v_finca := l.finca;
    elsif v_finca is null then
      raise exception '%: la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un DESPLAZAMIENTO', v_desc;
    elsif l.finca <> v_finca then
      raise exception '%: para pasar de la finca % a la finca % hace falta antes un DESPLAZAMIENTO',
        v_desc, v_finca, l.finca;
    end if;
  end loop;
end $$;

-- 4) guardar_parte(): permisos del supervisor y titular activo ---------------------------------
-- Cambios respecto a la 012 (marcados con «013»):
--  * Crear a nombre de otro: ADMIN o SUPERVISOR. El titular debe existir y estar activo (todos).
--  * Editar: ADMIN cualquiera; SUPERVISOR en Pendiente o Cerrado; OPERARIO los suyos en Pendiente.
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

  -- Valores de la cabecera: lo enviado o, si llega vacío, el de la configuración (012).
  v_ini   := public.valores_iniciales_parte();
  v_h_ent := coalesce(nullif(trim(p_cab ->> 'h_ent'), ''), v_ini ->> 'h_ent')::time;
  v_h_sal := coalesce(nullif(trim(p_cab ->> 'h_sal'), ''), v_ini ->> 'h_sal')::time;
  v_t_alm := coalesce(nullif(trim(p_cab ->> 't_alm'), ''), (v_ini ->> 't_alm_min') || ' minutes')::interval;
  v_t_com := coalesce(nullif(trim(p_cab ->> 't_com'), ''), (v_ini ->> 't_com_min') || ' minutes')::interval;

  if v_id is null then
    v_operario := coalesce(nullif(p_cab ->> 'operario', ''), v_cod);
    if v_operario is distinct from v_cod and v_rol not in ('ADMIN', 'SUPERVISOR') then          -- «013»
      raise exception 'Solo un ADMIN o un SUPERVISOR pueden crear partes de otro operario' using errcode = '42501';
    end if;
    if not exists (select 1 from public.operarios where cod_ope = v_operario and activo) then    -- «013»
      raise exception 'El operario % no existe o está dado de baja', v_operario;
    end if;
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, mat_nave, obs)
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      v_h_ent,
      v_h_sal,
      v_t_alm,
      v_t_com,
      coalesce((p_cab ->> 'h_ext')::numeric, 0),
      coalesce((p_cab ->> 'h_ext_manual')::boolean, false),
      coalesce((p_cab ->> 'mat_nave')::boolean, false),
      nullif(p_cab ->> 'obs', '')
    )
    returning id_parte into v_id;
  else
    select operario, estado into v_operario, v_estado
    from public.partes_cab where id_parte = v_id
    for update;
    if not found
       or not (v_rol = 'ADMIN'
               or (v_rol = 'SUPERVISOR' and v_estado in ('Pendiente', 'Cerrado'))                -- «013»
               or (v_rol = 'OPERARIO' and v_operario = v_cod and v_estado = 'Pendiente')) then
      raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
    end if;

    update public.partes_cab set
      fecha        = coalesce((p_cab ->> 'fecha')::date, fecha),
      h_ent        = v_h_ent,
      h_sal        = v_h_sal,
      t_alm        = v_t_alm,
      t_com        = v_t_com,
      h_ext        = coalesce((p_cab ->> 'h_ext')::numeric, h_ext),
      h_ext_manual = coalesce((p_cab ->> 'h_ext_manual')::boolean, h_ext_manual),
      mat_nave     = coalesce((p_cab ->> 'mat_nave')::boolean, false),
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

  perform public.validar_parte(v_id);
  return v_id;
end $$;

-- 5) Auditoría de partes ---------------------------------------------------------------------
-- 5a) Cabecera: alta y modificaciones con el disparador genérico de la 006 (registro = nº de parte).
create trigger partes_cab_auditoria
  after insert or update on public.partes_cab
  for each row execute function public.tg_auditoria('num_parte');

-- 5b) Borrado del parte: una sola fila con el parte completo y sus tareas.
-- BEFORE DELETE porque después las tareas ya se han borrado en cascada.
create function public.tg_auditoria_parte_borrado()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.auditoria (tabla, registro, accion, cambios, usuario_email, cod_ope)
  values (
    'partes_cab',
    old.num_parte::text,
    'BORRADO',
    to_jsonb(old) || jsonb_build_object('lineas',
      (select coalesce(jsonb_agg(to_jsonb(d) order by d.h_ini), '[]'::jsonb)
       from public.partes_det d where d.id_parte = old.id_parte)),
    coalesce(lower(auth.jwt() ->> 'email'), 'sistema'),
    public.app_cod_ope()
  );
  return old;
end $$;

create trigger partes_cab_auditoria_borrado
  before delete on public.partes_cab
  for each row execute function public.tg_auditoria_parte_borrado();

-- 5c) Tareas: registro = nº de parte; la fila de la tarea lleva su id_linea.
-- El borrado en cascada de las tareas al borrar un parte no se anota aparte (ya va en 5b).
create function public.tg_auditoria_parte_linea()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  nuevo jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  viejo jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_num bigint;
  v_cambios jsonb;
begin
  select num_parte into v_num from public.partes_cab
  where id_parte = coalesce(new.id_parte, old.id_parte);
  if not found then
    return null;  -- el parte se está borrando: su copia completa ya está en auditoría
  end if;

  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, jsonb_build_object('antes', viejo -> k, 'despues', nuevo -> k))
      into v_cambios
    from jsonb_object_keys(nuevo) k
    where (nuevo -> k) is distinct from (viejo -> k);
    if v_cambios is null then
      return null;  -- guardado sin cambios en esta tarea
    end if;
    v_cambios := jsonb_build_object('id_linea', new.id_linea) || v_cambios;
  else
    v_cambios := coalesce(nuevo, viejo);
  end if;

  insert into public.auditoria (tabla, registro, accion, cambios, usuario_email, cod_ope)
  values (
    'partes_det',
    v_num::text,
    case tg_op when 'INSERT' then 'ALTA' when 'UPDATE' then 'MODIFICACION' else 'BORRADO' end,
    v_cambios,
    coalesce(lower(auth.jwt() ->> 'email'), 'sistema'),
    public.app_cod_ope()
  );
  return null;
end $$;

create trigger partes_det_auditoria
  after insert or update or delete on public.partes_det
  for each row execute function public.tg_auditoria_parte_linea();

-- 5d) borrar_parte(): la copia la hace ahora el disparador 5b.
-- Único cambio respecto a la 010: se quita el INSERT en auditoria.
create or replace function public.borrar_parte(p_id_parte uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if public.app_rol() is distinct from 'ADMIN' then
    raise exception 'Solo un ADMIN puede borrar partes' using errcode = '42501';
  end if;
  perform 1 from public.partes_cab where id_parte = p_id_parte for update;
  if not found then
    raise exception 'Parte no encontrado';
  end if;
  delete from public.partes_cab where id_parte = p_id_parte;  -- copia en auditoría por disparador; tareas en cascada
end $$;

-- 6) Permisos ---------------------------------------------------------------------------------
revoke execute on function public.tg_auditoria_parte_borrado(), public.tg_auditoria_parte_linea()
  from public, anon, authenticated;
