-- =====================================================================
-- 015 · Módulo 7: archivo de tareas, vista de vueltas y horas por trabajador.
-- PROPUESTA pendiente de revisión: no aplicar hasta que se autorice.
-- Ejecutar en Dashboard → SQL Editor (contiene DROP CONSTRAINT y DELETE, que el conector bloquea).
-- Precondición: 014 aplicada.
--
-- Decisiones aplicadas (docs/DECISIONES_MODULOS_4_A_8.md):
--  * La app sirve para controlar el gasto por parcela. Solo cuentan los partes Aprobados.
--  * Archivo (tabla tareas_realizadas): resumen de las tareas, SIN hora de inicio ni de fin:
--      campaña, operario, fecha, código y nombre de la tarea, finca, parcela, vehículo, apero,
--      fin_vuelta, horas (duración) y nº de parte de origen.
--    Se archivan todas las tareas menos MOTIVOS PERSONALES y DESPLAZAMIENTO, agrupadas por
--    operario, día, tarea, finca, parcela, vehículo y apero (sumando horas; fin_vuelta = Sí si
--    alguna de las agrupadas lo tiene).
--  * Campaña = año agrícola. Fecha de inicio en configuracion.cfc_inicio ('MM-DD', por defecto
--    '09-01'). campana_de(fecha) → '2026/27'. Las vueltas empiezan de cero en cada campaña.
--  * archivar_partes(hasta): solo ADMIN. Exige que no quede ningún parte Pendiente ni Cerrado con
--    fecha <= hasta. Copia al archivo las tareas de los Aprobados y BORRA esos partes. Los Rechazados
--    del rango se borran sin pasar al archivo (respuesta del 04/11), cada uno con su copia completa
--    en la auditoría, como borrar_parte(). Después nadie puede crear ni modificar partes con
--    fecha <= hasta. De los Aprobados archivados queda una sola anotación en la auditoría (sin copia
--    completa de cada parte).
--    (La comprobación de que cada parte tiene su PDF se añadirá con la 016.)
--  * Vista vueltas (lo que se llamó Parc_Tareas): una fila por vuelta = campaña + parcela + tarea +
--    nº de vuelta, con fecha de inicio, fecha de fin, operario que marcó el fin, horas, registros
--    y estado (Abierta / Cerrada). Incluye el archivo y los Aprobados aún sin archivar.
--    Varios operarios el mismo día: el registro que marca el fin cierra la vuelta y los del mismo
--    día que no lo marcan cuentan en esa misma vuelta.
--  * Vistas para exportar a CSV desde la app: vueltas, tareas_resumen y horas_trabajador
--    (parte, operario, fecha, entrada, salida, almuerzo, comida). El CSV de horas se descarga
--    ANTES de archivar: al borrar los partes esos datos dejan de estar en la BD.
--  * Lectura: ADMIN y SUPERVISOR. El OPERARIO no ve el archivo ni las vistas.
-- =====================================================================

-- 0) Precondición ------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.requiere_fin_vuelta(public.partes_det)') is null then
    raise exception 'La 015 exige la 014 aplicada';
  end if;
end $$;

-- 1) Configuración: inicio de campaña ---------------------------------------------------------
-- Se añade cfc_inicio a la validación por clave (resto igual que en la 012).
-- Día 01–28 para que exista en todos los años.
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
    else true
  end);

insert into public.configuracion (clave, valor, descripcion, modificado_por)
values ('cfc_inicio', '09-01', 'Inicio de la campaña agrícola (MM-DD, día 01 a 28)', 'sistema');

-- Campaña de una fecha: '2026/27' si la campaña empieza en 2026.
create function public.campana_de(p_fecha date)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  v text;
  a int;
begin
  select valor into v from public.configuracion where clave = 'cfc_inicio';
  if v is null then
    raise exception 'Falta el parámetro cfc_inicio en la tabla configuracion';
  end if;
  a := extract(year from p_fecha)::int;
  if p_fecha < make_date(a, split_part(v, '-', 1)::int, split_part(v, '-', 2)::int) then
    a := a - 1;
  end if;
  return a || '/' || lpad(((a + 1) % 100)::text, 2, '0');
end $$;

-- 2) Tablas del archivo -----------------------------------------------------------------------
-- Cada ejecución de archivar_partes().
create table public.archivos_partes (
  id            bigint generated always as identity primary key,
  hasta         date not null unique,
  fecha         timestamptz not null default now(),
  archivado_por text,
  partes        int not null,              -- Aprobados archivados
  lineas        int not null,              -- tareas de esos partes
  filas         int not null default 0,    -- filas creadas en tareas_realizadas
  rechazados    int not null default 0     -- Rechazados borrados sin archivar
);

-- Resumen de tareas archivadas (no se modifica: solo lo escribe archivar_partes()).
create table public.tareas_realizadas (
  id         bigint generated always as identity primary key,
  id_archivo bigint not null references public.archivos_partes (id),
  campana    text not null,
  operario   text not null references public.operarios (cod_ope),
  fec_tarea  date not null,
  tarea      text not null references public.tareas (cod_tar),
  nom_tarea  text not null,
  finca      text references public.fincas (cod_fin),
  parcela    text references public.parcelas (cod_par),
  vehiculo   text references public.vehiculos (id_mat),
  apero      text references public.aperos (id_bas),
  fin_vuelta boolean not null default false,
  horas      numeric(6,2) not null,
  num_parte  bigint not null
);
create index tareas_realizadas_vuelta_idx on public.tareas_realizadas (campana, parcela, tarea, fec_tarea);
create index tareas_realizadas_fecha_idx on public.tareas_realizadas (fec_tarea);

alter table public.archivos_partes enable row level security;
alter table public.tareas_realizadas enable row level security;
create policy archivos_partes_select on public.archivos_partes
  for select to authenticated using ((select public.app_es_gestor()));
create policy tareas_realizadas_select on public.tareas_realizadas
  for select to authenticated using ((select public.app_es_gestor()));
-- Sin políticas de escritura: solo escribe archivar_partes().
revoke all on public.archivos_partes, public.tareas_realizadas from anon;
revoke insert, update, delete, truncate on public.archivos_partes, public.tareas_realizadas from authenticated;
grant select on public.archivos_partes, public.tareas_realizadas to authenticated;

-- 3) Fechas archivadas: no se crean ni modifican partes ------------------------------------------
create function public.tg_partes_cab_fecha_archivada()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_ult date;
begin
  select max(hasta) into v_ult from public.archivos_partes;
  if v_ult is not null and new.fecha <= v_ult then
    raise exception 'Los partes hasta el % están archivados: no se pueden crear ni modificar partes de esas fechas',
      to_char(v_ult, 'DD/MM/YYYY');
  end if;
  return new;
end $$;

create trigger partes_cab_fecha_archivada
  before insert or update on public.partes_cab
  for each row execute function public.tg_partes_cab_fecha_archivada();

-- 4) Auditoría: el archivado no guarda copia de cada parte ---------------------------------------
-- Único cambio respecto a la 013: si archivar_partes() está borrando, no se anota cada parte
-- (la función deja una sola anotación del archivado).
create or replace function public.tg_auditoria_parte_borrado()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('app.archivando', true), '') = 'on' then
    return old;
  end if;
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

-- 5) archivar_partes(hasta) -------------------------------------------------------------------
-- Desde la API: rpc('archivar_partes', { p_hasta: '2026-10-31' }) → {hasta, partes, lineas, filas, rechazados}
create function public.archivar_partes(p_hasta date)
returns jsonb
language plpgsql security definer
set search_path = public
set timezone to 'Europe/Madrid'
as $$
declare
  v_ult date;
  v_bloq text;
  v_n_bloq int;
  v_id bigint;
  v_partes int;
  v_lineas int;
  v_filas int;
  v_rech int;
begin
  if public.app_rol() is distinct from 'ADMIN' then
    raise exception 'Solo un ADMIN puede archivar partes' using errcode = '42501';
  end if;
  if p_hasta is null or p_hasta >= current_date then
    raise exception 'Solo se puede archivar hasta ayer como mucho';
  end if;

  -- Nadie guarda partes mientras se archiva.
  lock table public.partes_cab in share row exclusive mode;

  select max(hasta) into v_ult from public.archivos_partes;
  if v_ult is not null and p_hasta <= v_ult then
    raise exception 'Ya está archivado hasta el %', to_char(v_ult, 'DD/MM/YYYY');
  end if;

  -- Pendientes y Cerrados impiden archivar (aún pueden cambiar o aprobarse).
  select count(*) into v_n_bloq from public.partes_cab
  where fecha <= p_hasta and estado in ('Pendiente', 'Cerrado');
  if v_n_bloq > 0 then
    select string_agg(format('nº %s (%s, %s)', num_parte, estado, to_char(fecha, 'DD/MM/YYYY')), ', ')
      into v_bloq
    from (select num_parte, estado, fecha from public.partes_cab
          where fecha <= p_hasta and estado in ('Pendiente', 'Cerrado') order by fecha, num_parte limit 10) s;
    raise exception 'No se puede archivar: hay % parte(s) hasta el % sin aprobar: %',
      v_n_bloq, to_char(p_hasta, 'DD/MM/YYYY'),
      v_bloq || case when v_n_bloq > 10 then ', …' else '' end;
  end if;

  select count(*) into v_partes from public.partes_cab where fecha <= p_hasta and estado = 'Aprobado';
  select count(*) into v_rech   from public.partes_cab where fecha <= p_hasta and estado = 'Rechazado';
  select count(*) into v_lineas
  from public.partes_det d join public.partes_cab c on c.id_parte = d.id_parte
  where c.fecha <= p_hasta and c.estado = 'Aprobado';

  insert into public.archivos_partes (hasta, archivado_por, partes, lineas, rechazados)
  values (p_hasta, public.app_cod_ope(), v_partes, v_lineas, v_rech)
  returning id into v_id;

  insert into public.tareas_realizadas
    (id_archivo, campana, operario, fec_tarea, tarea, nom_tarea, finca, parcela, vehiculo, apero, fin_vuelta, horas, num_parte)
  select v_id, public.campana_de(c.fecha), c.operario, c.fecha, d.tarea, max(t.tareas),
         d.finca, d.parcela, d.vehiculo, d.apero,
         bool_or(coalesce(d.fin_vuelta, false)), sum(d.t_horas), c.num_parte
  from public.partes_cab c
  join public.partes_det d on d.id_parte = c.id_parte
  join public.tareas t on t.cod_tar = d.tarea
  where c.fecha <= p_hasta
    and c.estado = 'Aprobado'
    and t.tipo is distinct from 'MOTIVOS PERSONALES'
    and t.tipo is distinct from 'DESPLAZAMIENTO'
  group by c.operario, c.fecha, c.num_parte, d.tarea, d.finca, d.parcela, d.vehiculo, d.apero;
  get diagnostics v_filas = row_count;

  update public.archivos_partes set filas = v_filas where id = v_id;

  -- Rechazados: se borran sin archivar, cada uno con su copia completa en auditoría (disparador).
  delete from public.partes_cab where fecha <= p_hasta and estado = 'Rechazado';

  -- Aprobados archivados: se borran (tareas en cascada) sin copia individual en auditoría.
  perform set_config('app.archivando', 'on', true);
  delete from public.partes_cab where fecha <= p_hasta and estado = 'Aprobado';
  perform set_config('app.archivando', 'off', true);

  insert into public.auditoria (tabla, registro, accion, cambios, usuario_email, cod_ope)
  values ('partes_cab', 'ARCHIVO hasta ' || p_hasta, 'BORRADO',
          jsonb_build_object('hasta', p_hasta, 'partes', v_partes, 'lineas', v_lineas, 'filas_archivo', v_filas,
                             'rechazados_borrados', v_rech, 'id_archivo', v_id),
          coalesce(lower(auth.jwt() ->> 'email'), 'sistema'), public.app_cod_ope());

  return jsonb_build_object('hasta', p_hasta, 'partes', v_partes, 'lineas', v_lineas, 'filas', v_filas,
                            'rechazados', v_rech);
end $$;

-- 6) Vistas para consultar y exportar ---------------------------------------------------------
-- security_invoker: respetan los permisos de quien consulta (solo ADMIN y SUPERVISOR ven filas).

-- Tareas realizadas: archivo + partes Aprobados aún sin archivar, con el mismo formato.
create view public.tareas_resumen with (security_invoker = true) as
select 'archivo'::text as origen, r.campana, r.operario, r.fec_tarea, r.tarea, r.nom_tarea,
       r.finca, r.parcela, r.vehiculo, r.apero, r.fin_vuelta, r.horas, r.num_parte
from public.tareas_realizadas r
union all
select 'parte', public.campana_de(c.fecha), c.operario, c.fecha, d.tarea, max(t.tareas),
       d.finca, d.parcela, d.vehiculo, d.apero, bool_or(coalesce(d.fin_vuelta, false)), sum(d.t_horas), c.num_parte
from public.partes_cab c
join public.partes_det d on d.id_parte = c.id_parte
join public.tareas t on t.cod_tar = d.tarea
where c.estado = 'Aprobado'
  and t.tipo is distinct from 'MOTIVOS PERSONALES'
  and t.tipo is distinct from 'DESPLAZAMIENTO'
  and public.app_es_gestor()
group by c.operario, c.fecha, c.num_parte, d.tarea, d.finca, d.parcela, d.vehiculo, d.apero;

-- Vueltas: una fila por campaña + parcela + tarea + nº de vuelta.
-- Orden dentro de cada parcela y tarea: fecha; el mismo día, primero los registros sin fin de
-- vuelta y después el que lo marca (así todos los de ese día cuentan en la vuelta que se cierra).
create view public.vueltas with (security_invoker = true) as
with base as (
  select r.*,
         1 + coalesce(sum(case when r.fin_vuelta then 1 else 0 end) over (
               partition by r.campana, r.parcela, r.tarea
               order by r.fec_tarea, r.fin_vuelta, r.num_parte
               rows between unbounded preceding and 1 preceding), 0) as num_vuelta
  from public.tareas_resumen r
  join public.tareas t on t.cod_tar = r.tarea
  where r.parcela is not null and t.tipo in ('POR SUPERFICIE (HAS)', 'POR HORAS')
)
select b.campana, max(b.finca) as finca, b.parcela, max(p.nom_parc) as nom_parcela,
       b.tarea, max(b.nom_tarea) as nom_tarea, b.num_vuelta,
       case when bool_or(b.fin_vuelta) then 'Cerrada' else 'Abierta' end as estado,
       min(b.fec_tarea) as fecha_inicio,
       max(b.fec_tarea) filter (where b.fin_vuelta) as fecha_fin,
       max(b.operario) filter (where b.fin_vuelta) as operario_fin,
       sum(b.horas) as horas,
       count(*) as registros,
       string_agg(distinct b.operario, ', ') as operarios,
       bool_or(b.origen = 'parte') as incluye_sin_archivar
from base b
left join public.parcelas p on p.cod_par = b.parcela
group by b.campana, b.parcela, b.tarea, b.num_vuelta;

-- Horas por trabajador (para comparar con los fichajes): exportar ANTES de archivar.
create view public.horas_trabajador with (security_invoker = true) as
select c.num_parte as parte, c.operario, c.fecha, c.h_ent, c.h_sal,
       (extract(epoch from c.t_alm) / 60)::int as t_alm_min,
       (extract(epoch from c.t_com) / 60)::int as t_com_min,
       c.estado
from public.partes_cab c
where public.app_es_gestor();

-- 7) Permisos ---------------------------------------------------------------------------------
revoke all on public.tareas_resumen, public.vueltas, public.horas_trabajador from anon;
grant select on public.tareas_resumen, public.vueltas, public.horas_trabajador to authenticated;
revoke execute on function public.campana_de(date) from public, anon;
grant  execute on function public.campana_de(date) to authenticated, service_role;
revoke execute on function public.archivar_partes(date) from public, anon;
grant  execute on function public.archivar_partes(date) to authenticated, service_role;
revoke execute on function public.tg_partes_cab_fecha_archivada() from public, anon, authenticated;
