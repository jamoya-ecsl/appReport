-- =====================================================================
-- 014 · Módulo 6: fin_vuelta en las tareas del parte.
-- APLICADA 04/11/2026 desde el SQL Editor (contiene UPDATE, que el conector bloquea). Precondición: 013 aplicada.
-- Verificada 10/10 (pruebas_modulo6.sql); por rol y módulos 1 a 5 siguen correctos.
--
-- Decisiones aplicadas (docs/DECISIONES_MODULOS_4_A_8.md):
--  * partes_det.fin_vuelta: Sí (true) / No (false) / sin responder (null).
--  * Vuelta = parcela + código de tarea. La pregunta solo se aplica a las tareas con PARCELA y de tipo
--    'POR SUPERFICIE (HAS)' o 'POR HORAS'. En el resto (sin parcela, tarea sin tipo, DESPLAZAMIENTO,
--    MOTIVOS PERSONALES) la BD guarda siempre No, se envíe lo que se envíe.
--  * Mientras el parte está Pendiente puede quedar sin responder. Para CERRARLO todas las tareas a las
--    que se aplica deben tener respuesta (también desde el SQL Editor). Un parte ya cerrado que se
--    corrige (supervisor o ADMIN) tampoco puede quedar con tareas sin responder.
--  * El supervisor verifica y corrige fin_vuelta antes de aprobar (permisos de la 013).
--  * Para la app: requiere_fin_vuelta(partes_det) indica en qué tareas mostrar la pregunta:
--      sb.from('partes_det').select('*, requiere_fin_vuelta')  o  partes_cab ... partes_det(*, requiere_fin_vuelta)
--  * guardar_parte() recibe 'fin_vuelta' en cada línea (true / false / null o ausente = sin responder).
--
-- Partes ya existentes: las tareas a las que NO se aplica quedan en No. Las que sí se aplica quedan
-- sin responder (no se inventa la respuesta); en partes Pendientes se responderán al cerrarlos; en
-- partes ya Cerrados/Aprobados/Rechazados solo se exigirá si alguien corrige ese parte.
-- =====================================================================

-- 0) Precondición ------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'partes_det_auditoria') then
    raise exception 'La 014 exige la 013 aplicada';
  end if;
end $$;

-- Comprobaciones diferidas pendientes: que se hagan ahora, con las reglas actuales.
set constraints all immediate;

-- 1) Columna ---------------------------------------------------------------------------------
alter table public.partes_det add column fin_vuelta boolean;
comment on column public.partes_det.fin_vuelta is
  'Termina la vuelta de esta tarea en esta parcela: true = Sí, false = No, null = sin responder';

-- 2) ¿A qué tareas se aplica? ------------------------------------------------------------------
-- Campo calculado para la API (como ht_tareas): select('*, requiere_fin_vuelta').
create function public.requiere_fin_vuelta(d public.partes_det)
returns boolean
language sql stable
set search_path = public
as $$
  select d.parcela is not null
     and exists (select 1 from public.tareas t
                 where t.cod_tar = d.tarea and t.tipo in ('POR SUPERFICIE (HAS)', 'POR HORAS'))
$$;

-- 3) Partes existentes: No en las tareas a las que no se aplica -------------------------------
-- (queda en la auditoría como modificación de 'sistema').
update public.partes_det d set fin_vuelta = false
where not public.requiere_fin_vuelta(d);

-- 4) Al guardar una tarea a la que no se aplica, la BD pone No --------------------------------
create function public.tg_partes_det_fin_vuelta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.requiere_fin_vuelta(new) then
    new.fin_vuelta := false;
  end if;
  return new;
end $$;

create trigger partes_det_fin_vuelta
  before insert or update on public.partes_det
  for each row execute function public.tg_partes_det_fin_vuelta();

-- 5) Tareas sin responder de un parte (texto para los mensajes; null si no hay) ----------------
-- No se expone a la API: la usan validar_parte() y tg_partes_cab_estado().
create function public.fin_vuelta_pendientes(p_id_parte uuid)
returns text
language sql stable security definer
set search_path = public
as $$
  select string_agg(format('%s–%s (%s, parcela %s)', left(d.h_ini::text, 5), left(d.h_fin::text, 5),
                           t.tareas, coalesce(p.nom_parc, d.parcela)), '; ' order by d.h_ini)
  from public.partes_det d
  join public.tareas t on t.cod_tar = d.tarea
  left join public.parcelas p on p.cod_par = d.parcela
  where d.id_parte = p_id_parte
    and d.fin_vuelta is null
    and public.requiere_fin_vuelta(d)
$$;

-- 6) Cerrar exige respuesta -------------------------------------------------------------------
-- Único cambio respecto a la 013: al pasar a Cerrado se comprueba fin_vuelta («014»).
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
      if not new.mat_nave and not exists (select 1 from public.partes_det where id_parte = new.id_parte) then
        raise exception 'Para cerrar un parte sin mantenimiento en nave hace falta al menos una tarea';
      end if;
      v_pend := public.fin_vuelta_pendientes(new.id_parte);                                   -- «014»
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

-- 7) validar_parte(): un parte ya cerrado no puede quedar con tareas sin responder ---------------
-- Único cambio respecto a la 013: bloque «014».
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
begin
  select h_ent, h_sal, estado, mat_nave into c from public.partes_cab where id_parte = p_id_parte;
  if not found then
    return;
  end if;

  if c.estado <> 'Pendiente' and not c.mat_nave
     and not exists (select 1 from public.partes_det where id_parte = p_id_parte) then
    raise exception 'El parte está %: sin mantenimiento en nave necesita al menos una tarea', c.estado;
  end if;

  if c.estado <> 'Pendiente' then                                                              -- «014»
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

-- 8) guardar_parte(): recibe fin_vuelta en cada línea -------------------------------------------
-- Único cambio respecto a la 013: 'fin_vuelta' en el UPDATE y el INSERT de líneas («014»).
-- Como el resto de campos de la línea, si no se envía queda vacío (sin responder).
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
               or (v_rol = 'SUPERVISOR' and v_estado in ('Pendiente', 'Cerrado'))
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
    tarea      = l ->> 'tarea',
    finca      = nullif(l ->> 'finca', ''),
    parcela    = nullif(l ->> 'parcela', ''),
    vehiculo   = nullif(l ->> 'vehiculo', ''),
    apero      = nullif(l ->> 'apero', ''),
    h_ini      = (l ->> 'h_ini')::time,
    h_fin      = (l ->> 'h_fin')::time,
    obs        = nullif(l ->> 'obs', ''),
    fin_vuelta = nullif(l ->> 'fin_vuelta', '')::boolean                                      -- «014»
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is not null
    and d.id_linea = (l ->> 'id_linea')::uuid
    and d.id_parte = v_id;

  insert into public.partes_det (id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs, fin_vuelta)
  select v_id, l ->> 'tarea', nullif(l ->> 'finca', ''), nullif(l ->> 'parcela', ''),
         nullif(l ->> 'vehiculo', ''), nullif(l ->> 'apero', ''),
         (l ->> 'h_ini')::time, (l ->> 'h_fin')::time, nullif(l ->> 'obs', ''),
         nullif(l ->> 'fin_vuelta', '')::boolean                                              -- «014»
  from jsonb_array_elements(v_lineas) l
  where nullif(l ->> 'id_linea', '') is null;

  perform public.validar_parte(v_id);
  return v_id;
end $$;

-- 9) Permisos ---------------------------------------------------------------------------------
revoke execute on function public.requiere_fin_vuelta(public.partes_det) from public, anon;
grant  execute on function public.requiere_fin_vuelta(public.partes_det) to authenticated, service_role;
revoke execute on function public.fin_vuelta_pendientes(uuid) from public, anon, authenticated;
revoke execute on function public.tg_partes_det_fin_vuelta() from public, anon, authenticated;
