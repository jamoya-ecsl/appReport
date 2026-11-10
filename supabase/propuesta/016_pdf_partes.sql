-- =====================================================================
-- 016 · Módulo 8: PDF del parte, a petición.
-- PROPUESTA pendiente de revisión: no aplicar hasta que se autorice.
-- Ejecutar en Dashboard → SQL Editor (contiene DROP CONSTRAINT, que el conector bloquea).
-- Precondición: 015 aplicada.
--
-- Decisiones (docs/DECISIONES_MODULOS_4_A_8.md, cambio del 05/11):
--  * El PDF NO se genera solo: el SUPERVISOR o el ADMIN pulsan "Generar PDF" en un parte Aprobado.
--  * Solo partes Aprobados. Lo generan SUPERVISOR y ADMIN; lo ven ADMIN, SUPERVISOR y el operario titular.
--  * Si el parte no ha cambiado desde el último PDF, el botón devuelve ese mismo PDF. Si ha cambiado
--    (el ADMIN lo corrigió), se genera una versión nueva y se conserva la anterior.
--  * Se guarda en Storage, bucket PRIVADO 'partes-pdf', en la carpeta configuracion.cfp_carpeta
--    (por defecto 'partes'): <carpeta>/<año>/<nº parte>_v<versión>.pdf. Cambiarla solo afecta a los nuevos.
--  * Archivar NO exige el PDF. Los PDF y su registro (partes_pdf) se conservan al archivar o borrar el parte.
--
-- Cómo funciona:
--  1. La app llama a la función del servidor generar-pdf con la sesión del usuario:
--     supabase.functions.invoke('generar-pdf', { body: { id_parte } }).
--  2. La función llama a pdf_pedir(id_parte) CON LA SESIÓN DEL USUARIO: la BD comprueba el rol y el
--     estado, guarda una "foto" del parte (columna datos) y decide si hace falta un PDF nuevo.
--  3. Si hace falta, la función dibuja el PDF, lo sube a Storage y lo marca con pdf_marcar().
--  4. Devuelve un enlace temporal (5 minutos) para abrirlo o imprimirlo.
-- =====================================================================

-- 0) Precondición ------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.archivos_partes') is null then
    raise exception 'La 016 exige la 015 aplicada';
  end if;
end $$;

-- 1) Configuración: carpeta de los PDF ------------------------------------------------------------
-- Se añade cfp_carpeta a la validación por clave (resto igual que en la 015).
-- Minúsculas, números, guion y guion bajo, con hasta 3 subcarpetas separadas por '/'.
alter table public.configuracion drop constraint configuracion_valor_ok;
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
    when 'cfc_inicio' then valor ~ '^(0[1-9]|1[0-2])-(0[1-9]|1[0-9]|2[0-8])$'
    when 'cfp_carpeta' then valor ~ '^[a-z0-9_-]{1,40}(/[a-z0-9_-]{1,40}){0,3}$'
    else true
  end);

insert into public.configuracion (clave, valor, descripcion, modificado_por)
values ('cfp_carpeta', 'partes', 'Carpeta de los PDF de partes dentro del almacenamiento (bucket partes-pdf)', 'sistema');

-- 2) Bucket privado de Storage ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partes-pdf', 'partes-pdf', false, 5242880, array['application/pdf'])
on conflict (id) do nothing;

-- 3) Registro de PDF -------------------------------------------------------------------------------
-- Una fila por versión. Sin clave ajena a partes_cab: el PDF se conserva al archivar o borrar el parte.
create table public.partes_pdf (
  id             bigint generated always as identity primary key,
  id_parte       uuid not null,
  num_parte      bigint not null,
  operario       text not null,
  fecha          date not null,
  version        int not null,
  estado         text not null default 'Generando' check (estado in ('Generando', 'Generado', 'Error')),
  datos          jsonb not null,              -- foto del parte con la que se dibuja el PDF
  ruta           text not null unique,        -- ruta dentro del bucket partes-pdf
  solicitado     timestamptz not null default now(),
  solicitado_por text not null,               -- quién pulsó el botón (cod_ope)
  generado       timestamptz,
  intentos       int not null default 1,
  error          text,
  unique (id_parte, version)
);
create index partes_pdf_operario_idx on public.partes_pdf (operario, fecha);

alter table public.partes_pdf enable row level security;
-- ADMIN y SUPERVISOR ven todos; el operario, los de sus partes.
create policy partes_pdf_select on public.partes_pdf
  for select to authenticated
  using ((select public.app_es_gestor()) or operario = (select public.app_cod_ope()));
-- Sin políticas de escritura: solo escriben pdf_pedir() y pdf_marcar().
revoke all on public.partes_pdf from anon;
revoke insert, update, delete, truncate on public.partes_pdf from authenticated;
grant select on public.partes_pdf to authenticated;

-- Storage: se puede descargar un PDF si se ve su fila en partes_pdf (la política de arriba decide).
-- Nadie sube, cambia ni borra desde la app: solo la función del servidor (service_role).
create policy partes_pdf_leer on storage.objects
  for select to authenticated
  using (bucket_id = 'partes-pdf'
         and exists (select 1 from public.partes_pdf p where p.ruta = storage.objects.name));

-- 4) Foto del parte para el PDF ----------------------------------------------------------------------
-- Solo campos de contenido (sin fechas de modificación): si nada cambia, la foto es idéntica.
create function public.pdf_datos(p_id_parte uuid)
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
    'mat_nave', c.mat_nave,
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

-- 5) Pedir el PDF (botón "Generar PDF") ----------------------------------------------------------------
-- La llama la función del servidor con la sesión del usuario. Devuelve
--   {id, ruta, version, nuevo, datos}
-- nuevo = false → el último PDF ya refleja el parte: se reutiliza (datos no se envía).
-- nuevo = true  → la función debe dibujarlo y subirlo, y después llamar a pdf_marcar(id).
create function public.pdf_pedir(p_id_parte uuid)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c public.partes_cab;
  v_datos jsonb;
  v_ult public.partes_pdf;
  v_carpeta text;
  v_id bigint;
  v_ruta text;
  v_version int;
begin
  if public.app_rol() is null or public.app_rol() not in ('ADMIN', 'SUPERVISOR') then
    raise exception 'Solo un SUPERVISOR o un ADMIN pueden generar el PDF de un parte' using errcode = '42501';
  end if;
  -- Bloquea el parte: dos peticiones a la vez no crean dos versiones.
  select * into c from public.partes_cab where id_parte = p_id_parte for update;
  if not found then
    raise exception 'Parte no encontrado';
  end if;
  if c.estado <> 'Aprobado' then
    raise exception 'Solo se puede generar el PDF de un parte Aprobado (este está %)', c.estado;
  end if;
  v_datos := public.pdf_datos(p_id_parte);

  select * into v_ult from public.partes_pdf where id_parte = p_id_parte order by version desc limit 1;
  if found and v_ult.datos = v_datos then
    if v_ult.estado = 'Generado' then
      return jsonb_build_object('id', v_ult.id, 'ruta', v_ult.ruta, 'version', v_ult.version, 'nuevo', false);
    end if;
    if v_ult.estado = 'Generando' and v_ult.solicitado > now() - interval '2 minutes' then
      raise exception 'El PDF de este parte se está generando: espera unos segundos y vuelve a pulsar';
    end if;
    -- Falló o se quedó a medias: se repite la misma versión.
    update public.partes_pdf
    set estado = 'Generando', solicitado = now(), solicitado_por = public.app_cod_ope(),
        intentos = intentos + 1, error = null
    where id = v_ult.id;
    return jsonb_build_object('id', v_ult.id, 'ruta', v_ult.ruta, 'version', v_ult.version, 'nuevo', true, 'datos', v_datos);
  end if;

  select valor into v_carpeta from public.configuracion where clave = 'cfp_carpeta';
  v_version := coalesce(v_ult.version, 0) + 1;
  v_ruta := coalesce(v_carpeta, 'partes') || '/' || extract(year from c.fecha)::int || '/'
            || c.num_parte || '_v' || v_version || '.pdf';
  insert into public.partes_pdf (id_parte, num_parte, operario, fecha, version, datos, ruta, solicitado_por)
  values (c.id_parte, c.num_parte, c.operario, c.fecha, v_version, v_datos, v_ruta, public.app_cod_ope())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'ruta', v_ruta, 'version', v_version, 'nuevo', true, 'datos', v_datos);
end $$;

-- 6) Resultado de la generación (solo la función del servidor) -----------------------------------
-- p_error vacío = Generado; con texto = Error (se repite la próxima vez que se pulse el botón).
create function public.pdf_marcar(p_id bigint, p_error text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update public.partes_pdf
  set estado = case when p_error is null then 'Generado' else 'Error' end,
      generado = case when p_error is null then now() end,
      error = left(p_error, 500)
  where id = p_id and estado = 'Generando';
end $$;

-- 7) Permisos ---------------------------------------------------------------------------------------
revoke execute on function public.pdf_datos(uuid)          from public, anon, authenticated;
revoke execute on function public.pdf_pedir(uuid)          from public, anon;
grant  execute on function public.pdf_pedir(uuid)          to authenticated;
revoke execute on function public.pdf_marcar(bigint, text) from public, anon, authenticated;
grant  execute on function public.pdf_marcar(bigint, text) to service_role;
