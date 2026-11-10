-- =====================================================================
-- 019 · Módulo 10: guardar el parte por partes — jornada y cada línea por separado
-- (docs/PLAN_MODULOS_9_Y_10.md, paso 3).
-- Solo crea funciones nuevas (sin DROP ni cambios de datos). Precondición: 018 aplicada.
--
-- Decisiones (respuestas del 10/11/2026):
--  * Cada línea se valida Y SE GUARDA al pulsar "Aceptar". El parte se crea al aceptar la jornada.
--  * Las líneas se meten en orden de hora: una línea nueva empieza cuando acaba la última o más tarde.
--  * Editar una línea: tiene que seguir cabiendo entre la anterior y la siguiente.
--  * Editar o quitar una línea, o cambiar la jornada, se rechaza si el resto del parte deja de ser válido
--    (por ejemplo, quitar el desplazamiento del que dependen otras tareas, o dejar tareas fuera de la jornada).
--  * Mismos permisos que guardar_parte(): ADMIN cualquiera; SUPERVISOR en Pendiente o Cerrado;
--    OPERARIO los suyos en Pendiente. La validación completa es validar_parte() (018), que ya se usa.
--
-- Desde la API:
--   rpc('guardar_cabecera', { p_id_parte: null | id, p_cab: {...} })      → id_parte
--   rpc('guardar_linea',    { p_id_parte: id, p_linea: {...} })            → id_linea
--   rpc('borrar_linea',     { p_id_linea: id })                            → void
-- p_cab: igual que en guardar_parte() (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, obs).
-- p_linea: id_linea (vacío = nueva), tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs, fin_vuelta.
-- guardar_parte() se mantiene sin cambios (compatibilidad).
-- =====================================================================

do $$
begin
  if to_regprocedure('public.parte_tiene_trabajo(uuid)') is null then
    raise exception 'La 019 exige la 018 aplicada';
  end if;
end $$;

-- 1) Parte que el usuario puede editar, bloqueado -------------------------------------------------
-- Mismo criterio que guardar_parte(). Uso interno de las funciones de esta migración.
create function public.parte_para_editar(p_id_parte uuid)
returns public.partes_cab
language plpgsql security definer
set search_path = public
as $$
declare
  c public.partes_cab;
  v_rol public.rol_app := public.app_rol();
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;
  select * into c from public.partes_cab where id_parte = p_id_parte for update;
  if not found
     or not (v_rol = 'ADMIN'
             or (v_rol = 'SUPERVISOR' and c.estado in ('Pendiente', 'Cerrado'))
             or (v_rol = 'OPERARIO' and c.operario = public.app_cod_ope() and c.estado = 'Pendiente')) then
    raise exception 'Parte no encontrado o sin permiso para editarlo' using errcode = '42501';
  end if;
  return c;
end $$;

-- 2) guardar_cabecera(): crea o edita la jornada -----------------------------------------------------
-- Igual que la parte de cabecera de guardar_parte() (018). Si el parte ya tiene líneas, validar_parte()
-- comprueba que siguen dentro de la jornada.
create function public.guardar_cabecera(p_id_parte uuid, p_cab jsonb)
returns uuid
language plpgsql security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_id uuid := p_id_parte;
  v_rol public.rol_app := public.app_rol();
  v_cod text := public.app_cod_ope();
  v_operario text;
  v_ini jsonb;
  v_h_ent time;
  v_h_sal time;
  v_t_alm interval;
  v_t_com interval;
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
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
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, obs)
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      v_h_ent, v_h_sal, v_t_alm, v_t_com,
      coalesce((p_cab ->> 'h_ext')::numeric, 0),
      coalesce((p_cab ->> 'h_ext_manual')::boolean, false),
      nullif(p_cab ->> 'obs', '')
    )
    returning id_parte into v_id;
  else
    perform public.parte_para_editar(v_id);
    update public.partes_cab set
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

  perform public.validar_parte(v_id);
  return v_id;
end $$;

-- 3) guardar_linea(): crea o edita una línea ---------------------------------------------------------
create function public.guardar_linea(p_id_parte uuid, p_linea jsonb)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_id_linea uuid := nullif(p_linea ->> 'id_linea', '')::uuid;
  v_h_ini time := nullif(p_linea ->> 'h_ini', '')::time;
  v_h_fin time := nullif(p_linea ->> 'h_fin', '')::time;
  v_old public.partes_det;
  v_prev_fin time;
  v_sig_ini time;
begin
  perform public.parte_para_editar(p_id_parte);
  if nullif(p_linea ->> 'tarea', '') is null then
    raise exception 'Falta la tarea';
  end if;
  if v_h_ini is null or v_h_fin is null then
    raise exception 'Faltan la hora de inicio o la de fin';
  end if;

  if v_id_linea is null then
    -- Nueva: empieza cuando acaba la última línea o más tarde.
    select max(h_fin) into v_prev_fin from public.partes_det where id_parte = p_id_parte;
    if v_prev_fin is not null and v_h_ini < v_prev_fin then
      raise exception 'La tarea nueva debe empezar a las % o más tarde, cuando acaba la última tarea del parte',
        left(v_prev_fin::text, 5);
    end if;
    insert into public.partes_det (id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs, fin_vuelta)
    values (p_id_parte, p_linea ->> 'tarea', nullif(p_linea ->> 'finca', ''), nullif(p_linea ->> 'parcela', ''),
            nullif(p_linea ->> 'vehiculo', ''), nullif(p_linea ->> 'apero', ''), v_h_ini, v_h_fin,
            nullif(p_linea ->> 'obs', ''), nullif(p_linea ->> 'fin_vuelta', '')::boolean)
    returning id_linea into v_id_linea;
  else
    select * into v_old from public.partes_det where id_linea = v_id_linea and id_parte = p_id_parte;
    if not found then
      raise exception 'La línea no pertenece a este parte' using errcode = '42501';
    end if;
    -- Editada: sigue entre la anterior y la siguiente (en su sitio del orden).
    select max(h_fin) into v_prev_fin from public.partes_det
    where id_parte = p_id_parte and id_linea <> v_id_linea and h_ini < v_old.h_ini;
    select min(h_ini) into v_sig_ini from public.partes_det
    where id_parte = p_id_parte and id_linea <> v_id_linea and h_ini > v_old.h_ini;
    if v_prev_fin is not null and v_h_ini < v_prev_fin then
      raise exception 'La tarea debe empezar a las % o más tarde, cuando acaba la tarea anterior', left(v_prev_fin::text, 5);
    end if;
    if v_sig_ini is not null and v_h_fin > v_sig_ini then
      raise exception 'La tarea debe terminar a las % o antes, cuando empieza la tarea siguiente', left(v_sig_ini::text, 5);
    end if;
    update public.partes_det set
      tarea      = p_linea ->> 'tarea',
      finca      = nullif(p_linea ->> 'finca', ''),
      parcela    = nullif(p_linea ->> 'parcela', ''),
      vehiculo   = nullif(p_linea ->> 'vehiculo', ''),
      apero      = nullif(p_linea ->> 'apero', ''),
      h_ini      = v_h_ini,
      h_fin      = v_h_fin,
      obs        = nullif(p_linea ->> 'obs', ''),
      fin_vuelta = nullif(p_linea ->> 'fin_vuelta', '')::boolean
    where id_linea = v_id_linea;
  end if;

  -- El parte completo sigue siendo válido (jornada, cadena de desplazamientos, campos por tipo...).
  perform public.validar_parte(p_id_parte);
  return v_id_linea;
end $$;

-- 4) borrar_linea(): quita una línea si el resto sigue siendo válido ---------------------------------
create function public.borrar_linea(p_id_linea uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_id_parte uuid;
begin
  select id_parte into v_id_parte from public.partes_det where id_linea = p_id_linea;
  if not found then
    raise exception 'Línea no encontrada o sin permiso para editarla' using errcode = '42501';
  end if;
  perform public.parte_para_editar(v_id_parte);
  delete from public.partes_det where id_linea = p_id_linea;
  perform public.validar_parte(v_id_parte);
end $$;

-- 5) Permisos ---------------------------------------------------------------------------------------
revoke execute on function public.parte_para_editar(uuid) from public, anon, authenticated;
revoke execute on function public.guardar_cabecera(uuid, jsonb) from public, anon;
revoke execute on function public.guardar_linea(uuid, jsonb) from public, anon;
revoke execute on function public.borrar_linea(uuid) from public, anon;
grant  execute on function public.guardar_cabecera(uuid, jsonb) to authenticated;
grant  execute on function public.guardar_linea(uuid, jsonb) to authenticated;
grant  execute on function public.borrar_linea(uuid) to authenticated;
