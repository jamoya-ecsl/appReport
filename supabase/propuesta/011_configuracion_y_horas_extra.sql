-- =====================================================================
-- 011 · Módulo 3: configuración (th_jornada) y cálculo de horas extra; ht_tareas al consultar.
-- APLICADA 28/10/2026 desde el SQL Editor (tras 009 y 010). Verificada 19/19 (pruebas_modulo3.sql).
--
-- Decisiones aplicadas (respuestas del 28/10 y propuestas aceptadas):
--  * Tabla clave/valor 'configuracion'. De momento un solo parámetro: th_jornada = 8 (horas).
--    Solo el ADMIN la ve y la modifica (no se crean ni borran claves desde la app).
--  * h_ext = max(tot_horas − th_jornada, 0), calculado por la BD al crear el parte y cada vez que
--    cambian entrada, salida, almuerzo o comida.
--  * Corrección a mano: solo ADMIN (columna h_ext_manual = true). El valor corregido se mantiene
--    hasta que cambien entrada, salida o pausas; entonces se vuelve a calcular.
--    Lo que envíe otro rol en h_ext se ignora.
--  * Si cambia th_jornada, se recalculan solo los partes Pendientes sin corrección manual
--    (Cerrados, Aprobados y Rechazados conservan su valor).
--  * ht_tareas (horas de tareas sin MOTIVOS PERSONALES) no se guarda: se calcula al consultar con
--    la función ht_tareas(partes_cab), usable desde la API como columna: select('*, ht_tareas').
--  * La auditoría de la configuración solo la ve el ADMIN.
-- =====================================================================

-- 1) Configuración ------------------------------------------------------------------------
create table public.configuracion (
  clave            text primary key,
  valor            text not null,
  descripcion      text,
  fch_modificacion timestamptz not null default now(),
  modificado_por   text,
  -- th_jornada: horas en múltiplos de 0,25 entre 0,25 y 24 (CASE anidado para no convertir texto no numérico)
  constraint configuracion_th_jornada_ok check (
    case when clave = 'th_jornada' then
      case when valor ~ '^[0-9]{1,2}(\.[0-9]{1,2})?$'
           then valor::numeric > 0 and valor::numeric <= 24 and valor::numeric * 4 = trunc(valor::numeric * 4)
           else false end
    else true end)
);

insert into public.configuracion (clave, valor, descripcion, modificado_por)
values ('th_jornada', '8', 'Horas de la jornada ordinaria; por encima se cuentan horas extra', 'sistema');

alter table public.configuracion enable row level security;

create policy configuracion_select on public.configuracion
  for select to authenticated using ((select public.app_rol()) = 'ADMIN');
create policy configuracion_update on public.configuracion
  for update to authenticated
  using ((select public.app_rol()) = 'ADMIN') with check ((select public.app_rol()) = 'ADMIN');
-- Sin políticas de INSERT ni DELETE: las claves se crean y retiran por migración.

-- Quién y cuándo (los fija la BD)
create function public.tg_configuracion_autor()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.clave := old.clave;  -- la clave no se renombra
  new.fch_modificacion := now();
  new.modificado_por := coalesce(public.app_cod_ope(), 'sistema');
  return new;
end $$;

create trigger configuracion_autor
  before update on public.configuracion
  for each row execute function public.tg_configuracion_autor();

create trigger configuracion_auditoria
  after insert or update or delete on public.configuracion
  for each row execute function public.tg_auditoria('clave');

-- El supervisor no ve la auditoría de la configuración (ni la de operarios, como hasta ahora).
alter policy auditoria_select_supervisor on public.auditoria
  using ((select public.app_rol()) = 'SUPERVISOR' and tabla not in ('operarios', 'configuracion'));

-- 2) Horas extra --------------------------------------------------------------------------
alter table public.partes_cab
  add column h_ext_manual boolean not null default false;

-- SECURITY DEFINER para leer th_jornada aunque el usuario (operario) no vea la configuración.
-- app_rol() sigue leyendo la sesión del usuario conectado.
create function public.tg_partes_cab_h_ext()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_th numeric;
  v_tot numeric;
  v_auto numeric;
  v_admin boolean := auth.jwt() ->> 'email' is null or public.app_rol() = 'ADMIN';  -- sin sesión = SQL Editor
  v_horas_cambian boolean := true;
  v_respetar boolean;
begin
  select valor::numeric into v_th from public.configuracion where clave = 'th_jornada';
  if v_th is null then
    raise exception 'Falta el parámetro th_jornada en la tabla configuracion';
  end if;
  -- Igual que la columna generada tot_horas (que aún no está calculada en un disparador BEFORE).
  v_tot := round(extract(epoch from (new.h_sal - new.h_ent) - new.t_alm - new.t_com) / 3600, 2);
  v_auto := floor(greatest(v_tot - v_th, 0) * 4) / 4;

  if tg_op = 'UPDATE' then
    v_horas_cambian := (new.h_ent, new.h_sal, new.t_alm, new.t_com)
                       is distinct from (old.h_ent, old.h_sal, old.t_alm, old.t_com);
  end if;

  if not v_admin then
    -- Otros roles no corrigen h_ext: se ignora lo que envíen.
    if not v_horas_cambian then
      new.h_ext := old.h_ext;              -- solo llega aquí en UPDATE
      new.h_ext_manual := old.h_ext_manual;
    else
      new.h_ext := v_auto;
      new.h_ext_manual := false;
    end if;
    return new;
  end if;

  -- ADMIN: se respeta el valor corregido salvo que cambien las horas sin tocar h_ext.
  v_respetar := new.h_ext_manual;
  if v_respetar and tg_op = 'UPDATE' and v_horas_cambian
     and new.h_ext is not distinct from old.h_ext and old.h_ext_manual then
    v_respetar := false;
  end if;
  if not v_respetar then
    new.h_ext := v_auto;
    new.h_ext_manual := false;
  end if;
  return new;
end $$;

create trigger partes_cab_h_ext
  before insert or update on public.partes_cab
  for each row execute function public.tg_partes_cab_h_ext();

-- Al cambiar th_jornada: recalcular los partes Pendientes sin corrección manual.
create function public.tg_configuracion_recalcular()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.clave = 'th_jornada' and new.valor is distinct from old.valor then
    -- Tocar la fila basta: tg_partes_cab_h_ext recalcula (h_ext_manual = false → automático).
    update public.partes_cab set h_ext = h_ext
    where estado = 'Pendiente' and not h_ext_manual;
  end if;
  return null;
end $$;

create trigger configuracion_recalcular
  after update on public.configuracion
  for each row execute function public.tg_configuracion_recalcular();

-- Nota: h_ext y h_ext_manual cuentan como "contenido" para los disparadores 004 y 010, así que
-- un supervisor no puede cambiarlos y, en un parte no Pendiente, solo los cambia un ADMIN.

-- 3) guardar_parte(): pasa h_ext_manual -------------------------------------------------------
-- Cambios respecto a la 009: al crear, h_ext_manual = p_cab.h_ext_manual (por defecto false);
-- al editar, h_ext y h_ext_manual conservan su valor si p_cab no los trae.
-- El disparador decide si el valor se respeta (ADMIN) o se calcula.
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
    v_operario := coalesce(nullif(p_cab ->> 'operario', ''), v_cod);
    if v_operario is distinct from v_cod and v_rol <> 'ADMIN' then
      raise exception 'Solo un ADMIN puede crear partes de otro operario' using errcode = '42501';
    end if;
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, mat_nave, obs)
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      (p_cab ->> 'h_ent')::time,
      (p_cab ->> 'h_sal')::time,
      coalesce((p_cab ->> 't_alm')::interval, '0'),
      coalesce((p_cab ->> 't_com')::interval, '0'),
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
       or not (v_rol = 'ADMIN' or (v_rol = 'OPERARIO' and v_operario = v_cod and v_estado = 'Pendiente')) then
      raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
    end if;

    update public.partes_cab set
      fecha        = coalesce((p_cab ->> 'fecha')::date, fecha),
      h_ent        = (p_cab ->> 'h_ent')::time,
      h_sal        = (p_cab ->> 'h_sal')::time,
      t_alm        = coalesce((p_cab ->> 't_alm')::interval, '0'),
      t_com        = coalesce((p_cab ->> 't_com')::interval, '0'),
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

-- 4) ht_tareas: horas de tareas sin MOTIVOS PERSONALES, calculadas al consultar -------------
-- SECURITY INVOKER: respeta RLS (cada uno solo suma líneas de partes que puede ver).
-- Desde la API: sb.from('partes_cab').select('*, ht_tareas')
create function public.ht_tareas(p public.partes_cab)
returns numeric
language sql stable security invoker
set search_path = public
as $$
  select coalesce(sum(d.t_horas), 0)
  from public.partes_det d
  join public.tareas t on t.cod_tar = d.tarea
  where d.id_parte = p.id_parte and t.tipo <> 'MOTIVOS PERSONALES'
$$;

-- 5) Permisos -----------------------------------------------------------------------------
grant select, update on public.configuracion to authenticated;
revoke all on public.configuracion from anon;
revoke execute on function public.ht_tareas(public.partes_cab) from public, anon;
grant  execute on function public.ht_tareas(public.partes_cab) to authenticated, service_role;
revoke execute on function public.tg_partes_cab_h_ext(), public.tg_configuracion_recalcular(),
                           public.tg_configuracion_autor()
  from public, anon, authenticated;
