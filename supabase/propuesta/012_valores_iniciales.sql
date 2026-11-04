-- =====================================================================
-- 012 · Módulo 4: valores iniciales del parte en la configuración; jornada de 8,5 h.
-- APLICADA 04/11/2026 desde el SQL Editor (contiene DROP CONSTRAINT y UPDATE, que el conector bloquea).
-- Verificada 18/18 (pruebas_modulo4.sql); módulos 1, 2, 3 y por rol siguen correctos.
--
-- Decisiones aplicadas (respuestas del 04/11/2026):
--  * Nuevos parámetros en 'configuracion':
--      cfh_ent = '07:30'  hora de entrada propuesta   (HH:MM, cuartos de hora)
--      cfh_sal = '18:00'  hora de salida propuesta    (HH:MM, cuartos de hora)
--      cft_alm = '30'     minutos de almuerzo         (entero, múltiplo de 15, 0–240)
--      cft_com = '90'     minutos de comida           (entero, múltiplo de 15, 0–240)
--  * Solo el ADMIN lee y modifica la tabla (sin cambios en sus políticas). Cualquier usuario con
--    acceso lee ESOS 4 valores con valores_iniciales_parte(), para proponerlos en el formulario.
--  * guardar_parte(): si entrada, salida, almuerzo o comida llegan vacíos o no llegan, se toma el
--    valor de la configuración, al crear y al editar. Para apuntar 0 minutos hay que enviar 0.
--    Cambiar estos valores en un parte no cambia la configuración, y cambiar la configuración
--    no cambia los partes ya guardados.
--  * th_jornada pasa de 8 a 8,5 h: con los valores iniciales (10,5 h − 2 h de pausas = 8,5 h)
--    un parte nuevo sale con 0 horas extra. Al cambiarla, la BD recalcula las horas extra de los
--    partes Pendientes sin corrección manual (disparador de la 011).
--  * Coherencia: salida > entrada y almuerzo + comida < jornada propuesta.
-- =====================================================================

-- 0) Precondiciones ------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.configuracion where clave = 'th_jornada') then
    raise exception 'La 012 exige la 011 aplicada (falta th_jornada en configuracion)';
  end if;
  if exists (select 1 from public.configuracion where clave in ('cfh_ent', 'cfh_sal', 'cft_alm', 'cft_com')) then
    raise exception 'La 012 ya está aplicada (existen los valores iniciales)';
  end if;
end $$;

-- 1) Validación de cada clave (sustituye a configuracion_th_jornada_ok) -----------------------
-- CASE anidado para no convertir texto no numérico.
alter table public.configuracion drop constraint configuracion_th_jornada_ok;
alter table public.configuracion add constraint configuracion_valor_ok check (
  case clave
    when 'th_jornada' then
      case when valor ~ '^[0-9]{1,2}(\.[0-9]{1,2})?$'
           then valor::numeric > 0 and valor::numeric <= 24 and valor::numeric * 4 = trunc(valor::numeric * 4)
           else false end
    when 'cfh_ent' then valor ~ '^([01][0-9]|2[0-3]):(00|15|30|45)$'
    when 'cfh_sal' then valor ~ '^([01][0-9]|2[0-3]):(00|15|30|45)$'
    when 'cft_alm' then
      case when valor ~ '^[0-9]{1,3}$' then valor::int % 15 = 0 and valor::int <= 240 else false end
    when 'cft_com' then
      case when valor ~ '^[0-9]{1,3}$' then valor::int % 15 = 0 and valor::int <= 240 else false end
    else true
  end);

-- 2) Valores iniciales -----------------------------------------------------------------------
insert into public.configuracion (clave, valor, descripcion, modificado_por) values
  ('cfh_ent', '07:30', 'Hora de entrada propuesta al crear un parte (HH:MM, en cuartos de hora)', 'sistema'),
  ('cfh_sal', '18:00', 'Hora de salida propuesta al crear un parte (HH:MM, en cuartos de hora)', 'sistema'),
  ('cft_alm', '30',    'Minutos de almuerzo propuestos al crear un parte (múltiplo de 15)', 'sistema'),
  ('cft_com', '90',    'Minutos de comida propuestos al crear un parte (múltiplo de 15)', 'sistema');

-- 3) Jornada de 8,5 h -------------------------------------------------------------------------
-- Recalcula h_ext de los partes Pendientes sin corrección manual (tg_configuracion_recalcular).
update public.configuracion set valor = '8.5' where clave = 'th_jornada';

-- 4) Coherencia entre los valores iniciales ---------------------------------------------------
-- AFTER por fila: se ejecuta al terminar la sentencia, así que un UPDATE que cambie varias
-- claves a la vez se comprueba con todas ya cambiadas.
create function public.tg_configuracion_valores_iniciales()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_ent time;
  v_sal time;
  v_alm int;
  v_com int;
begin
  if new.clave not in ('cfh_ent', 'cfh_sal', 'cft_alm', 'cft_com') then
    return null;
  end if;

  select (max(valor) filter (where clave = 'cfh_ent'))::time,
         (max(valor) filter (where clave = 'cfh_sal'))::time,
         (max(valor) filter (where clave = 'cft_alm'))::int,
         (max(valor) filter (where clave = 'cft_com'))::int
    into v_ent, v_sal, v_alm, v_com
  from public.configuracion
  where clave in ('cfh_ent', 'cfh_sal', 'cft_alm', 'cft_com');

  if v_ent is null or v_sal is null or v_alm is null or v_com is null then
    return null;  -- solo durante el alta de las claves
  end if;
  if v_sal <= v_ent then
    raise exception 'La salida propuesta (%) debe ser posterior a la entrada propuesta (%)',
      left(v_sal::text, 5), left(v_ent::text, 5);
  end if;
  if v_alm + v_com >= extract(epoch from v_sal - v_ent) / 60 then
    raise exception 'Almuerzo y comida propuestos (% min) deben ser menos que la jornada propuesta (% min)',
      v_alm + v_com, (extract(epoch from v_sal - v_ent) / 60)::int;
  end if;
  return null;
end $$;

create trigger configuracion_valores_iniciales
  after insert or update on public.configuracion
  for each row execute function public.tg_configuracion_valores_iniciales();

-- 5) Lectura de los valores iniciales para cualquier usuario con acceso ----------------------
-- SECURITY DEFINER: lee la configuración aunque el usuario no vea la tabla, y solo devuelve
-- estas 4 claves (th_jornada y el resto siguen siendo solo del ADMIN).
-- Desde la API: rpc('valores_iniciales_parte') → {h_ent, h_sal, t_alm_min, t_com_min}
create function public.valores_iniciales_parte()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  r jsonb;
begin
  if public.app_rol() is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;

  select jsonb_build_object(
           'h_ent',     max(valor) filter (where clave = 'cfh_ent'),
           'h_sal',     max(valor) filter (where clave = 'cfh_sal'),
           't_alm_min', (max(valor) filter (where clave = 'cft_alm'))::int,
           't_com_min', (max(valor) filter (where clave = 'cft_com'))::int)
    into r
  from public.configuracion
  where clave in ('cfh_ent', 'cfh_sal', 'cft_alm', 'cft_com');

  if r ->> 'h_ent' is null or r ->> 'h_sal' is null or r ->> 't_alm_min' is null or r ->> 't_com_min' is null then
    raise exception 'Faltan valores iniciales en la configuración (cfh_ent, cfh_sal, cft_alm, cft_com)';
  end if;
  return r;
end $$;

-- 6) guardar_parte(): campos vacíos → valores de la configuración ------------------------------
-- Cambios respecto a la 011 (marcados con «012»): h_ent, h_sal, t_alm y t_com vacíos o ausentes
-- toman el valor de valores_iniciales_parte(), al crear y al editar. El resto no cambia.
-- Nota para la app: guardar_parte espera siempre la cabecera completa; un campo que no se envía
-- se trata como vacío.
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
  v_ini jsonb;                                    -- «012»
  v_h_ent time;                                   -- «012»
  v_h_sal time;                                   -- «012»
  v_t_alm interval;                               -- «012»
  v_t_com interval;                               -- «012»
begin
  if v_rol is null then
    raise exception 'Usuario sin acceso a la aplicación' using errcode = '42501';
  end if;
  if jsonb_typeof(v_lineas) <> 'array' then
    raise exception 'p_lineas debe ser un array';
  end if;

  -- «012» Valores de la cabecera: lo enviado o, si llega vacío, el de la configuración.
  v_ini   := public.valores_iniciales_parte();
  v_h_ent := coalesce(nullif(trim(p_cab ->> 'h_ent'), ''), v_ini ->> 'h_ent')::time;
  v_h_sal := coalesce(nullif(trim(p_cab ->> 'h_sal'), ''), v_ini ->> 'h_sal')::time;
  v_t_alm := coalesce(nullif(trim(p_cab ->> 't_alm'), ''), (v_ini ->> 't_alm_min') || ' minutes')::interval;
  v_t_com := coalesce(nullif(trim(p_cab ->> 't_com'), ''), (v_ini ->> 't_com_min') || ' minutes')::interval;

  if v_id is null then
    v_operario := coalesce(nullif(p_cab ->> 'operario', ''), v_cod);
    if v_operario is distinct from v_cod and v_rol <> 'ADMIN' then
      raise exception 'Solo un ADMIN puede crear partes de otro operario' using errcode = '42501';
    end if;
    insert into public.partes_cab (operario, fecha, h_ent, h_sal, t_alm, t_com, h_ext, h_ext_manual, mat_nave, obs)
    values (
      v_operario,
      coalesce((p_cab ->> 'fecha')::date, current_date),
      v_h_ent,                                    -- «012»
      v_h_sal,                                    -- «012»
      v_t_alm,                                    -- «012»
      v_t_com,                                    -- «012»
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
      h_ent        = v_h_ent,                     -- «012»
      h_sal        = v_h_sal,                     -- «012»
      t_alm        = v_t_alm,                     -- «012»
      t_com        = v_t_com,                     -- «012»
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

-- 7) Permisos ---------------------------------------------------------------------------------
revoke execute on function public.valores_iniciales_parte() from public, anon;
grant  execute on function public.valores_iniciales_parte() to authenticated, service_role;
revoke execute on function public.tg_configuracion_valores_iniciales() from public, anon, authenticated;
