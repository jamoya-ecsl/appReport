-- =====================================================================
-- 004 · Roles y usuarios (aprobado 22/10/2026: D2, D3, D5, D7 + ADMIN con control total)
--  * operarios.user_id: enlace con la cuenta de login por id.
--    Mientras un operario no tenga user_id, se le reconoce por su email confirmado.
--  * Vinculación automática por email confirmado (cuenta nueva u operario nuevo/cambiado).
--  * Nunca se queda la app sin un ADMIN activo.
--  * operarios: ADMIN control total (política existente operarios_admin);
--    cada uno ve su propia ficha; el SUPERVISOR ya no ve usuarios.
--  * operarios_nombres(): código y nombre para gestores (sin email ni rol).
--  * Catálogos: ADMIN control total (política existente *_admin, incluye borrar);
--    el SUPERVISOR crea y edita (políticas nuevas).
--  * Partes: ADMIN control total (incluido borrar); el SUPERVISOR solo revisa
--    (estado y comentario); el OPERARIO edita los suyos en Pendiente.
--
-- Sin sentencias destructivas (sin DROP/DELETE/UPDATE): las políticas existentes se
-- modifican con ALTER POLICY. El enlace de las cuentas ya existentes va en
-- 004b_enlazar_cuentas_existentes.sql.
-- =====================================================================

-- ---------- Enlace con la cuenta de login ----------
alter table public.operarios
  add column user_id uuid unique references auth.users(id) on delete set null;

-- Cuenta confirmada en Auth → se vincula al operario con ese email (si no lo estaba).
-- Nunca bloquea el login/alta en Auth: cualquier error se ignora.
create function public.tg_auth_vincular_operario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email_confirmed_at is not null then
    begin
      update public.operarios set user_id = new.id
      where email = lower(new.email) and user_id is null
        and not exists (select 1 from public.operarios x where x.user_id = new.id);
    exception when others then
      raise log 'tg_auth_vincular_operario: %', sqlerrm;
    end;
  end if;
  return new;
end $$;

create trigger vincular_operario after insert or update of email, email_confirmed_at on auth.users
  for each row execute function public.tg_auth_vincular_operario();

-- Operario nuevo o con email cambiado → se vincula a la cuenta confirmada con ese email.
create function public.tg_operario_vincular_cuenta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is null then
    select u.id into new.user_id
    from auth.users u
    where lower(u.email) = new.email and u.email_confirmed_at is not null
      and not exists (select 1 from public.operarios o where o.user_id = u.id and o.cod_ope <> new.cod_ope)
    limit 1;
  end if;
  return new;
end $$;

create trigger operarios_vincular_cuenta before insert or update of email, user_id on public.operarios
  for each row execute function public.tg_operario_vincular_cuenta();

-- ---------- Identidad: por id; por email solo si aún no hay id enlazado ----------
create or replace function public.app_cod_ope() returns text
language sql stable security definer set search_path = public as $$
  select cod_ope from public.operarios
  where activo and (user_id = auth.uid()
                    or (user_id is null and email = lower(auth.jwt() ->> 'email')))
  limit 1
$$;

create or replace function public.app_rol() returns public.rol_app
language sql stable security definer set search_path = public as $$
  select rol_app from public.operarios
  where activo and (user_id = auth.uid()
                    or (user_id is null and email = lower(auth.jwt() ->> 'email')))
  limit 1
$$;

-- ---------- Siempre al menos un ADMIN activo ----------
create function public.tg_operarios_proteger_admin() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  quedan int;
begin
  if old.rol_app = 'ADMIN' and old.activo
     and (tg_op = 'DELETE' or new.rol_app <> 'ADMIN' or not new.activo) then
    select count(*) into quedan from public.operarios
    where cod_ope <> old.cod_ope and rol_app = 'ADMIN' and activo;
    if quedan = 0 then
      raise exception 'Debe quedar al menos un ADMIN activo';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger operarios_proteger_admin before update or delete on public.operarios
  for each row execute function public.tg_operarios_proteger_admin();

-- ---------- Políticas de operarios ----------
-- operarios_admin (ALL, solo ADMIN) se mantiene: control total del ADMIN.
-- operarios_select: antes la veían también los SUPERVISOR; ahora solo la propia ficha (o ADMIN).
alter policy operarios_select on public.operarios
  using (user_id = (select auth.uid())
         or (user_id is null and email = lower((select auth.jwt()) ->> 'email'))
         or (select public.app_rol()) = 'ADMIN');

-- ---------- Nombres de operarios para gestores ----------
create function public.operarios_nombres()
returns table (cod_ope text, usuario text, activo boolean)
language sql stable security definer set search_path = public as $$
  select o.cod_ope, o.usuario, o.activo
  from public.operarios o
  where public.app_es_gestor() or o.cod_ope = public.app_cod_ope()
  order by o.usuario
$$;

-- ---------- Catálogos ----------
-- *_admin (ALL, solo ADMIN) se mantiene: control total, incluido borrar.
-- Nuevas: el SUPERVISOR crea y edita (no borra).
do $$ declare t text; begin
  foreach t in array array['fincas','parcelas','tareas','vehiculos','aperos'] loop
    execute format('create policy %1$s_insert_supervisor on public.%1$s for insert to authenticated
                    with check ((select public.app_rol()) = ''SUPERVISOR'')', t);
    execute format('create policy %1$s_update_supervisor on public.%1$s for update to authenticated
                    using ((select public.app_rol()) = ''SUPERVISOR'') with check ((select public.app_rol()) = ''SUPERVISOR'')', t);
  end loop;
end $$;

-- ---------- Partes ----------
-- partes_cab_delete (solo ADMIN) y partes_cab_update (gestor o propio en Pendiente) se mantienen.

-- El SUPERVISOR solo puede cambiar los campos de revisión.
create function public.tg_partes_cab_supervisor_solo_revision() returns trigger
language plpgsql set search_path = public as $$
declare
  -- tot_horas es una columna calculada: en un disparador BEFORE llega vacía, por eso se excluye.
  revision constant text[] := array['estado', 'comentario_supervisor', 'supervisor_revisa', 'fecha_revision',
                                    'fch_modificacion', 'tot_horas'];
begin
  if public.app_rol() = 'SUPERVISOR'
     and (to_jsonb(new) - revision) is distinct from (to_jsonb(old) - revision) then
    raise exception 'Un supervisor solo puede aprobar o rechazar el parte, no modificar su contenido';
  end if;
  return new;
end $$;

create trigger partes_cab_supervisor_solo_revision before update on public.partes_cab
  for each row execute function public.tg_partes_cab_supervisor_solo_revision();

-- Líneas: escribe el ADMIN, o el propio operario si el parte está Pendiente. El SUPERVISOR ya no.
alter policy partes_det_write on public.partes_det
  using (exists (select 1 from public.partes_cab c where c.id_parte = partes_det.id_parte
    and ((select public.app_rol()) = 'ADMIN' or (c.operario = (select public.app_cod_ope()) and c.estado = 'Pendiente'))))
  with check (exists (select 1 from public.partes_cab c where c.id_parte = partes_det.id_parte
    and ((select public.app_rol()) = 'ADMIN' or (c.operario = (select public.app_cod_ope()) and c.estado = 'Pendiente'))));

-- ---------- Permisos de las funciones nuevas ----------
revoke execute on function public.operarios_nombres() from public, anon;
grant  execute on function public.operarios_nombres() to authenticated, service_role;
revoke execute on function public.tg_auth_vincular_operario(), public.tg_operario_vincular_cuenta(),
  public.tg_operarios_proteger_admin(), public.tg_partes_cab_supervisor_solo_revision()
  from public, anon, authenticated;
