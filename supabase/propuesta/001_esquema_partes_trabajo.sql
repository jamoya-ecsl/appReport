-- =====================================================================
-- App "Partes de Trabajo" (Escribano Cabañero) sobre Supabase/Postgres.
-- Traducción del diseño AppSheet (Diseno_App_Partes_Trabajo_AppSheet.md)
-- y de los nombres de PT_EC.xlsx, en minúsculas (convención Postgres).
--
-- Solo CREA objetos nuevos. Es ESTRICTO a propósito: no usa IF NOT EXISTS,
-- OR REPLACE ni DROP. Si cualquier objeto ya existiera, la migración falla
-- entera (es una transacción) y no se toca nada existente.
-- Aplicar UNA sola vez, como migración.
--
-- v2 (21/10/2026): creado_por / fechas de creación y campos de revisión
-- los fija siempre la BD (no se pueden falsear desde la app); políticas
-- con (select ...) para que Postgres evalúe la función una vez por consulta;
-- permisos de funciones de disparador restringidos.
-- =====================================================================

-- ---------- Tipos ----------
create type public.rol_app as enum ('ADMIN', 'SUPERVISOR', 'OPERARIO');
create type public.estado_parte as enum ('Pendiente', 'Aprobado', 'Rechazado');

-- ---------- Catálogos ----------
create table public.operarios (
  cod_ope   text primary key,                     -- T000, T001...
  usuario   text not null,
  email     text not null unique check (email = lower(email)),
  rol_app   public.rol_app not null default 'OPERARIO',
  activo    boolean not null default true
);

create table public.fincas (
  cod_fin   text primary key,
  finca     text not null
);

create table public.parcelas (
  cod_par    text primary key,
  finca      text not null references public.fincas(cod_fin),
  nom_parc   text not null,
  superficie numeric(10,4)
);
create index parcelas_finca_idx on public.parcelas(finca);

create table public.tareas (
  cod_tar   text primary key,                     -- TE... / TT...
  tareas    text not null,
  tipo      text check (tipo in ('POR SUPERFICIE (HAS)', 'POR HORAS'))
);

create table public.vehiculos (
  id_mat    text primary key,                     -- incluye provisionales SIN-MAT-<ALIAS>
  alias     text unique,
  equipo    text not null,
  tipo      text
);

create table public.aperos (
  id_bas    text primary key,
  alias     text unique,
  equipo    text not null,
  tipo      text
);

-- ---------- Partes ----------
create table public.partes_cab (
  id_parte              uuid primary key default gen_random_uuid(),
  -- Correlativo global generado por la BD: sustituye al MAX()+1 de AppSheet
  -- y elimina el riesgo de números duplicados con guardados simultáneos.
  num_parte             bigint generated always as identity (start with 1) unique,
  operario              text not null references public.operarios(cod_ope),
  fecha                 date not null default current_date,
  h_ent                 time not null,
  h_sal                 time not null,
  t_alm                 interval not null default '0',
  t_com                 interval not null default '0',
  tot_horas             numeric(5,2) generated always as
                          (round((extract(epoch from (h_sal - h_ent) - t_alm - t_com) / 3600)::numeric, 2)) stored,
  h_ext                 numeric(5,2) not null default 0,
  mat_nave              boolean not null default false,
  finca                 text not null references public.fincas(cod_fin),
  vehiculo              text references public.vehiculos(id_mat),
  tiempo                interval,                 -- PENDIENTE: confirmar significado
  obs                   text,
  estado                public.estado_parte not null default 'Pendiente',
  -- Con sesión lo fija el disparador. Sin sesión (importación con service role) hay que indicarlo.
  creado_por            text not null default lower(auth.jwt() ->> 'email'),
  fch_creacion          timestamptz not null default now(),
  fch_modificacion      timestamptz not null default now(),
  supervisor_revisa     text references public.operarios(cod_ope),
  fecha_revision        timestamptz,
  comentario_supervisor text,
  foto                  text,                     -- ruta en Supabase Storage
  ubicacion_lat         double precision,
  ubicacion_lon         double precision,
  -- PENDIENTE de confirmar: impide jornadas que pasen de medianoche.
  constraint partes_cab_horas_ok check (h_sal > h_ent),
  constraint partes_cab_un_parte_dia unique (operario, fecha),
  constraint partes_cab_rechazo_comentado
    check (estado <> 'Rechazado' or coalesce(trim(comentario_supervisor), '') <> '')
);
create index partes_cab_fecha_idx  on public.partes_cab(fecha);
create index partes_cab_estado_idx on public.partes_cab(estado);

create table public.partes_det (
  id_linea  uuid primary key default gen_random_uuid(),
  id_parte  uuid not null references public.partes_cab(id_parte) on delete cascade,
  -- El operario NO se duplica aquí: se obtiene de partes_cab (evita incoherencias).
  tarea     text not null references public.tareas(cod_tar),
  finca     text references public.fincas(cod_fin),
  parcela   text references public.parcelas(cod_par),
  vehiculo  text references public.vehiculos(id_mat),
  apero     text references public.aperos(id_bas),
  h_ini     time not null,
  h_fin     time not null,
  t_horas   numeric(5,2) generated always as
              (round((extract(epoch from (h_fin - h_ini)) / 3600)::numeric, 2)) stored,
  obs       text,
  constraint partes_det_horas_ok check (h_fin > h_ini)
);
create index partes_det_parte_idx on public.partes_det(id_parte);

create table public.partes_mant (
  id_mant        uuid primary key default gen_random_uuid(),
  id_parte       uuid references public.partes_cab(id_parte) on delete set null,
  fecha          date not null default current_date,
  tipo_equipo    text not null check (tipo_equipo in ('Vehículo', 'Apero')),
  vehiculo       text references public.vehiculos(id_mat),
  apero          text references public.aperos(id_bas),
  operario       text not null references public.operarios(cod_ope),
  tipo_mant      text not null check (tipo_mant in ('Preventivo', 'Correctivo', 'Avería')),
  descripcion    text not null,
  h_ini          time,
  h_fin          time,
  t_horas        numeric(5,2) generated always as
                   (round((extract(epoch from (h_fin - h_ini)) / 3600)::numeric, 2)) stored,
  obs            text,
  creado_por     text not null default lower(auth.jwt() ->> 'email'),
  fecha_creacion timestamptz not null default now(),
  constraint partes_mant_equipo_ok check (
    (tipo_equipo = 'Vehículo' and vehiculo is not null and apero is null) or
    (tipo_equipo = 'Apero'    and apero    is not null and vehiculo is null)),
  constraint partes_mant_horas_ok check (h_ini is null or h_fin is null or h_fin > h_ini)
);
create index partes_mant_operario_idx on public.partes_mant(operario);

-- ---------- Funciones de apoyo (rol del usuario conectado) ----------
-- Equivalen a LOOKUP(USEREMAIL(),"OPERARIOS","EMAIL",...) de AppSheet.
-- SECURITY DEFINER para poder leer operarios sin recursión de RLS.
create function public.app_cod_ope() returns text
language sql stable security definer set search_path = public as $$
  select cod_ope from public.operarios
  where email = lower(auth.jwt() ->> 'email') and activo
$$;

create function public.app_rol() returns public.rol_app
language sql stable security definer set search_path = public as $$
  select rol_app from public.operarios
  where email = lower(auth.jwt() ->> 'email') and activo
$$;

create function public.app_es_gestor() returns boolean
language sql stable set search_path = public as $$
  select coalesce(public.app_rol() in ('ADMIN', 'SUPERVISOR'), false)
$$;

revoke execute on function public.app_cod_ope(), public.app_rol(), public.app_es_gestor() from public, anon;
grant  execute on function public.app_cod_ope(), public.app_rol(), public.app_es_gestor() to authenticated, service_role;

-- ---------- Disparadores ----------
-- Fecha de modificación (equivale a NOW() con "Reset on edit").
create function public.tg_fch_modificacion() returns trigger
language plpgsql set search_path = public as $$
begin new.fch_modificacion := now(); return new; end $$;

create trigger partes_cab_fch_mod before update on public.partes_cab
  for each row execute function public.tg_fch_modificacion();

-- Guardas de partes_cab:
--  * Un OPERARIO no puede cambiar el estado ni escribir el comentario de revisión.
--  * creado_por / fch_creacion: los fija la BD al crear y no cambian nunca.
--  * supervisor_revisa / fecha_revision: solo los fija la BD al aprobar/rechazar;
--    se vacían si el parte vuelve a Pendiente.
--  * Sin sesión (service role, importación) no se aplica ninguna guarda.
create function public.tg_partes_cab_guardas() returns trigger
language plpgsql set search_path = public as $$
declare
  v_email text := lower(auth.jwt() ->> 'email');
  v_rol   public.rol_app;
begin
  if v_email is null then return new; end if;
  v_rol := public.app_rol();

  if v_rol = 'OPERARIO' and (
       new.estado <> 'Pendiente'
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

create trigger partes_cab_guardas before insert or update on public.partes_cab
  for each row execute function public.tg_partes_cab_guardas();

-- Autoría de partes_mant (mismo criterio que partes_cab).
create function public.tg_partes_mant_autor() returns trigger
language plpgsql set search_path = public as $$
declare v_email text := lower(auth.jwt() ->> 'email');
begin
  if v_email is null then return new; end if;
  if tg_op = 'INSERT' then
    new.creado_por := v_email;
    new.fecha_creacion := now();
  else
    new.creado_por := old.creado_por;
    new.fecha_creacion := old.fecha_creacion;
  end if;
  return new;
end $$;

create trigger partes_mant_autor before insert or update on public.partes_mant
  for each row execute function public.tg_partes_mant_autor();

-- Las funciones de disparador no se llaman directamente: nadie necesita EXECUTE.
-- (Postgres solo comprueba ese permiso al CREAR el disparador, no al dispararse.)
revoke execute on function public.tg_fch_modificacion(), public.tg_partes_cab_guardas(),
  public.tg_partes_mant_autor() from public, anon, authenticated;

-- ---------- RLS ----------
alter table public.operarios   enable row level security;
alter table public.fincas      enable row level security;
alter table public.parcelas    enable row level security;
alter table public.tareas      enable row level security;
alter table public.vehiculos   enable row level security;
alter table public.aperos      enable row level security;
alter table public.partes_cab  enable row level security;
alter table public.partes_det  enable row level security;
alter table public.partes_mant enable row level security;

-- OPERARIOS: cada uno ve su ficha; ADMIN y SUPERVISOR ven todas. Solo ADMIN escribe.
create policy operarios_select on public.operarios for select to authenticated
  using (email = lower((select auth.jwt()) ->> 'email') or (select public.app_es_gestor()));
create policy operarios_admin on public.operarios for all to authenticated
  using ((select public.app_rol()) = 'ADMIN') with check ((select public.app_rol()) = 'ADMIN');

-- CATÁLOGOS: lectura para cualquier usuario activo; escritura solo ADMIN.
do $$ declare t text; begin
  foreach t in array array['fincas','parcelas','tareas','vehiculos','aperos'] loop
    execute format('create policy %1$s_select on public.%1$s for select to authenticated
                    using ((select public.app_rol()) is not null)', t);
    execute format('create policy %1$s_admin on public.%1$s for all to authenticated
                    using ((select public.app_rol()) = ''ADMIN'') with check ((select public.app_rol()) = ''ADMIN'')', t);
  end loop;
end $$;

-- PARTES_CAB
create policy partes_cab_select on public.partes_cab for select to authenticated
  using (operario = (select public.app_cod_ope()) or (select public.app_es_gestor()));
create policy partes_cab_insert on public.partes_cab for insert to authenticated
  with check (operario = (select public.app_cod_ope()) or (select public.app_rol()) = 'ADMIN');
create policy partes_cab_update on public.partes_cab for update to authenticated
  using ((select public.app_es_gestor()) or (operario = (select public.app_cod_ope()) and estado = 'Pendiente'))
  with check ((select public.app_es_gestor()) or (operario = (select public.app_cod_ope()) and estado = 'Pendiente'));
create policy partes_cab_delete on public.partes_cab for delete to authenticated
  using ((select public.app_rol()) = 'ADMIN');

-- PARTES_DET: hereda el acceso de su cabecera.
create policy partes_det_select on public.partes_det for select to authenticated
  using (exists (select 1 from public.partes_cab c where c.id_parte = partes_det.id_parte
                 and (c.operario = (select public.app_cod_ope()) or (select public.app_es_gestor()))));
create policy partes_det_write on public.partes_det for all to authenticated
  using (exists (select 1 from public.partes_cab c where c.id_parte = partes_det.id_parte
                 and ((select public.app_es_gestor()) or (c.operario = (select public.app_cod_ope()) and c.estado = 'Pendiente'))))
  with check (exists (select 1 from public.partes_cab c where c.id_parte = partes_det.id_parte
                 and ((select public.app_es_gestor()) or (c.operario = (select public.app_cod_ope()) and c.estado = 'Pendiente'))));

-- PARTES_MANT: el operario ve/crea/edita los suyos; gestores todo; borrar solo ADMIN.
create policy partes_mant_select on public.partes_mant for select to authenticated
  using (operario = (select public.app_cod_ope()) or (select public.app_es_gestor()));
create policy partes_mant_insert on public.partes_mant for insert to authenticated
  with check (operario = (select public.app_cod_ope()) or (select public.app_es_gestor()));
create policy partes_mant_update on public.partes_mant for update to authenticated
  using (operario = (select public.app_cod_ope()) or (select public.app_es_gestor()))
  with check (operario = (select public.app_cod_ope()) or (select public.app_es_gestor()));
create policy partes_mant_delete on public.partes_mant for delete to authenticated
  using ((select public.app_rol()) = 'ADMIN');

-- El rol anónimo (sin iniciar sesión) no tiene ninguna política: no ve nada.
