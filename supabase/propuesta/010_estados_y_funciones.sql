-- =====================================================================
-- 010 · Módulo 2: estado Cerrado y cambios de estado solo mediante funciones.
-- APLICADA 28/10/2026 desde el SQL Editor (tras 010a). Verificada 32/32 (pruebas_modulo2.sql) y 32/32 (pruebas_por_rol.sql).
--
-- Decisiones aplicadas (respuestas del 28/10 y propuestas aceptadas):
--  * Ciclo de vida:  Pendiente ──cerrar──▶ Cerrado ──revisar──▶ Aprobado | Rechazado
--      - Un parte nuevo empieza siempre en Pendiente.
--      - Cerrado no se reabre (nadie vuelve a Pendiente). Aprobado y Rechazado son finales.
--      - Esta regla de transiciones vale para todos, también desde el SQL Editor.
--  * Quién hace cada paso:
--      - cerrar_parte():  OPERARIO (los suyos), SUPERVISOR y ADMIN (cualquiera).
--        Al cerrar se valida el parte completo; sin mantenimiento en nave necesita al menos una tarea.
--      - revisar_parte(): SUPERVISOR (solo partes de otros) y ADMIN; solo partes Cerrados;
--        rechazar exige comentario.
--      - borrar_parte():  solo ADMIN, en cualquier estado; deja copia del parte y sus líneas en auditoria.
--  * Contenido (cabecera y líneas) de un parte que ya no está Pendiente: solo lo cambia el ADMIN
--    (vía guardar_parte). Un Rechazado sigue Rechazado aunque el ADMIN lo corrija.
--  * Se eliminan las políticas de escritura directa en partes_cab: crear y editar → guardar_parte();
--    cambiar estado → cerrar_parte() / revisar_parte(); borrar → borrar_parte().
--  * Se sella quién y cuándo cierra (cerrado_por, fecha_cierre), igual que ya se hace con la revisión.
--  * panel_resumen(): 'pendientes_revision' cuenta los Cerrados; nueva clave 'sin_cerrar' (Pendientes).
--
-- Fuera de este módulo: configuración th_jornada y cálculo de h_ext (módulo 3).
-- =====================================================================

-- 0) Precondición: 010a aplicada ----------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_enum where enumtypid = 'public.estado_parte'::regtype and enumlabel = 'Cerrado') then
    raise exception 'La 010 exige el estado Cerrado: aplica antes 010a_estado_cerrado.sql';
  end if;
end $$;

-- 1) Quién y cuándo cierra (los fija la BD) ------------------------------------------------
alter table public.partes_cab
  add column cerrado_por  text references public.operarios (cod_ope),
  add column fecha_cierre timestamptz;

-- 2) Sin escritura directa en partes_cab ---------------------------------------------------
-- Se mantiene partes_cab_select (lectura). Todas las escrituras pasan por funciones.
drop policy partes_cab_insert on public.partes_cab;
drop policy partes_cab_update on public.partes_cab;
drop policy partes_cab_delete on public.partes_cab;

-- 3) Transiciones de estado y bloqueo del contenido -----------------------------------------
-- Se ejecuta antes que el resto de disparadores BEFORE de partes_cab (orden alfabético).
create function public.tg_partes_cab_estado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  -- Campos que cambian al cerrar o revisar; el resto es "contenido" del parte.
  c_no_contenido constant text[] := array['estado', 'comentario_supervisor', 'supervisor_revisa', 'fecha_revision',
                                          'cerrado_por', 'fecha_cierre', 'fch_modificacion', 'tot_horas'];
  v_con_sesion boolean := auth.jwt() ->> 'email' is not null;
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

  -- Contenido de un parte que ya no está Pendiente: solo ADMIN (o sin sesión: SQL Editor)
  if old.estado <> 'Pendiente' and v_con_sesion and public.app_rol() is distinct from 'ADMIN'
     and (to_jsonb(new) - c_no_contenido) is distinct from (to_jsonb(old) - c_no_contenido) then
    raise exception 'El parte está %: solo un ADMIN puede modificar su contenido', old.estado;
  end if;
  return new;
end $$;

create trigger partes_cab_estado
  before insert or update on public.partes_cab
  for each row execute function public.tg_partes_cab_estado();

-- Líneas de un parte que ya no está Pendiente: solo ADMIN (o sin sesión).
create function public.tg_partes_det_parte_abierto()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_estado public.estado_parte;
begin
  if auth.jwt() ->> 'email' is not null and public.app_rol() is distinct from 'ADMIN' then
    select estado into v_estado from public.partes_cab
    where id_parte = case when tg_op = 'DELETE' then old.id_parte else new.id_parte end;
    if found and v_estado <> 'Pendiente' then
      raise exception 'El parte está %: solo un ADMIN puede modificar sus tareas', v_estado;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger partes_det_parte_abierto
  before insert or update or delete on public.partes_det
  for each row execute function public.tg_partes_det_parte_abierto();

-- 4) Ajuste de los disparadores existentes al nuevo estado -----------------------------------
-- 4a) Guardas: el operario puede dejar su parte en Cerrado (vía cerrar_parte), nada más.
--     Único cambio respecto a la versión vigente: "new.estado <> 'Pendiente'" pasa a
--     "new.estado not in ('Pendiente', 'Cerrado')".
create or replace function public.tg_partes_cab_guardas()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_email text := lower(auth.jwt() ->> 'email');
  v_rol   public.rol_app;
begin
  if v_email is null then return new; end if;
  v_rol := public.app_rol();

  if v_rol = 'OPERARIO' and (
       new.estado not in ('Pendiente', 'Cerrado')
       or new.comentario_supervisor is distinct from (case when tg_op = 'UPDATE' then old.comentario_supervisor end))
  then
    raise exception 'Un operario no puede revisar ni cambiar el estado de un parte';
  end if;

  if tg_op = 'INSERT' then
    new.creado_por := v_email;
    new.fch_creacion := now();
    if new.estado in ('Aprobado', 'Rechazado') then
      new.supervisor_revisa := public.app_cod_ope();
      new.fecha_revision := now();
    else
      new.supervisor_revisa := null;
      new.fecha_revision := null;
    end if;
  else
    new.creado_por := old.creado_por;
    new.fch_creacion := old.fch_creacion;
    if new.estado is distinct from old.estado then
      if new.estado in ('Aprobado', 'Rechazado') then
        new.supervisor_revisa := public.app_cod_ope();
        new.fecha_revision := now();
      else
        new.supervisor_revisa := null;
        new.fecha_revision := null;
      end if;
    else
      new.supervisor_revisa := old.supervisor_revisa;
      new.fecha_revision := old.fecha_revision;
    end if;
  end if;
  return new;
end $$;

-- 4b) 008: el supervisor sí puede CERRAR su parte; sigue sin poder aprobarlo ni rechazarlo.
create or replace function public.tg_partes_cab_no_autorrevision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.app_rol() = 'SUPERVISOR' and new.operario = public.app_cod_ope() and (
       (tg_op = 'INSERT' and new.estado <> 'Pendiente')
    or (tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado in ('Aprobado', 'Rechazado'))) then
    raise exception 'Un supervisor no puede aprobar ni rechazar sus propios partes; debe revisarlos un ADMIN';
  end if;
  return new;
end $$;

-- 4c) 004: cerrar no es "modificar contenido" para el supervisor.
create or replace function public.tg_partes_cab_supervisor_solo_revision()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  revision constant text[] := array['estado', 'comentario_supervisor', 'supervisor_revisa', 'fecha_revision',
                                    'cerrado_por', 'fecha_cierre', 'fch_modificacion', 'tot_horas'];
begin
  if public.app_rol() = 'SUPERVISOR'
     and (to_jsonb(new) - revision) is distinct from (to_jsonb(old) - revision) then
    raise exception 'Un supervisor solo puede aprobar o rechazar el parte, no modificar su contenido';
  end if;
  return new;
end $$;

-- 5) Funciones de cambio de estado y borrado ---------------------------------------------------
-- SECURITY DEFINER con sus propias comprobaciones de permiso (como guardar_parte).
-- Los disparadores siguen viendo al usuario conectado (app_rol() lee su sesión).

create function public.cerrar_parte(p_id_parte uuid)
returns void
language plpgsql security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_rol public.rol_app := public.app_rol();
  v_cod text := public.app_cod_ope();
  v_operario text;
  v_estado public.estado_parte;
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;

  select operario, estado into v_operario, v_estado
  from public.partes_cab where id_parte = p_id_parte
  for update;
  if not found or (v_rol = 'OPERARIO' and v_operario is distinct from v_cod) then
    raise exception 'Parte no encontrado o sin permiso para cerrarlo' using errcode = '42501';
  end if;
  if v_estado <> 'Pendiente' then
    raise exception 'Solo se puede cerrar un parte Pendiente (este está %)', v_estado;
  end if;

  perform public.validar_parte(p_id_parte);
  update public.partes_cab set estado = 'Cerrado' where id_parte = p_id_parte;
end $$;

create function public.revisar_parte(p_id_parte uuid, p_estado text, p_comentario text default null)
returns void
language plpgsql security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_rol public.rol_app := public.app_rol();
  v_estado public.estado_parte;
  v_comentario text := nullif(trim(p_comentario), '');
begin
  if v_rol is null or v_rol not in ('SUPERVISOR', 'ADMIN') then
    raise exception 'Solo un SUPERVISOR o un ADMIN puede aprobar o rechazar partes' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('Aprobado', 'Rechazado') then
    raise exception 'La revisión debe ser Aprobado o Rechazado';
  end if;

  select estado into v_estado from public.partes_cab where id_parte = p_id_parte for update;
  if not found then
    raise exception 'Parte no encontrado' using errcode = '42501';
  end if;
  if v_estado <> 'Cerrado' then
    raise exception 'Solo se puede aprobar o rechazar un parte Cerrado (este está %)', v_estado;
  end if;
  if p_estado = 'Rechazado' and v_comentario is null then
    raise exception 'Para rechazar un parte hay que indicar el motivo en el comentario';
  end if;

  -- El disparador 008 impide que el supervisor revise sus propios partes.
  update public.partes_cab
  set estado = p_estado::public.estado_parte,
      comentario_supervisor = v_comentario
  where id_parte = p_id_parte;
end $$;

create function public.borrar_parte(p_id_parte uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_cab public.partes_cab;
begin
  if public.app_rol() is distinct from 'ADMIN' then
    raise exception 'Solo un ADMIN puede borrar partes' using errcode = '42501';
  end if;

  select * into v_cab from public.partes_cab where id_parte = p_id_parte for update;
  if not found then
    raise exception 'Parte no encontrado';
  end if;

  -- Copia completa (cabecera + líneas) en auditoria antes de borrar.
  insert into public.auditoria (tabla, registro, accion, cambios, usuario_email, cod_ope)
  values (
    'partes_cab',
    v_cab.num_parte::text,
    'BORRADO',
    to_jsonb(v_cab) || jsonb_build_object('lineas',
      (select coalesce(jsonb_agg(to_jsonb(d) order by d.h_ini), '[]'::jsonb)
       from public.partes_det d where d.id_parte = p_id_parte)),
    coalesce(lower(auth.jwt() ->> 'email'), 'sistema'),
    public.app_cod_ope()
  );

  delete from public.partes_cab where id_parte = p_id_parte;  -- las líneas se borran en cascada
end $$;

-- 6) panel_resumen(): pendientes de revisión = Cerrados; nueva clave sin_cerrar --------------
-- Cambios respecto a la 009: 'pendientes_revision' cuenta estado = 'Cerrado' y se añade 'sin_cerrar'.
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
      'pendientes_revision', (select count(*) from public.partes_cab where estado = 'Cerrado'),
      'sin_cerrar', (select count(*) from public.partes_cab where estado = 'Pendiente'),
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

-- 7) Permisos de ejecución -----------------------------------------------------------------
revoke execute on function public.cerrar_parte(uuid) from public, anon;
revoke execute on function public.revisar_parte(uuid, text, text) from public, anon;
revoke execute on function public.borrar_parte(uuid) from public, anon;
grant  execute on function public.cerrar_parte(uuid) to authenticated, service_role;
grant  execute on function public.revisar_parte(uuid, text, text) to authenticated, service_role;
grant  execute on function public.borrar_parte(uuid) to authenticated, service_role;
-- Funciones de disparador: no se exponen a la API.
revoke execute on function public.tg_partes_cab_estado(), public.tg_partes_det_parte_abierto()
  from public, anon, authenticated;
