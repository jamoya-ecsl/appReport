-- =====================================================================
-- 006 · Auditoría de datos maestros y usuarios (aprobado 22/10/2026, mejora B / D8)
--  * Tabla auditoria: qué tabla, qué registro, qué acción, qué cambió, quién y cuándo.
--  * La rellena SOLO un disparador; nadie puede escribir ni borrar desde la API.
--  * Lectura: ADMIN todo; SUPERVISOR solo datos maestros (no operarios).
--  * Registra también los cambios hechos desde el Dashboard (usuario = 'sistema').
-- =====================================================================

create table public.auditoria (
  id            bigint generated always as identity primary key,
  fecha         timestamptz not null default now(),
  tabla         text not null,
  registro      text not null,
  accion        text not null check (accion in ('ALTA', 'MODIFICACION', 'BORRADO')),
  cambios       jsonb not null,
  usuario_email text not null,
  cod_ope       text
);
create index auditoria_registro_idx on public.auditoria (tabla, registro, fecha desc);
create index auditoria_fecha_idx on public.auditoria (fecha desc);

-- ALTA: fila completa · MODIFICACION: solo campos cambiados {campo: {antes, despues}} · BORRADO: fila completa.
-- Argumento del disparador: nombre de la columna clave.
create function public.tg_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nuevo jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  viejo jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_cambios jsonb;
begin
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, jsonb_build_object('antes', viejo -> k, 'despues', nuevo -> k))
      into v_cambios
    from jsonb_object_keys(nuevo) k
    where (nuevo -> k) is distinct from (viejo -> k);
    if v_cambios is null then return new; end if;
  else
    v_cambios := coalesce(nuevo, viejo);
  end if;

  insert into public.auditoria (tabla, registro, accion, cambios, usuario_email, cod_ope)
  values (
    tg_table_name,
    coalesce(nuevo, viejo) ->> tg_argv[0],
    case tg_op when 'INSERT' then 'ALTA' when 'UPDATE' then 'MODIFICACION' else 'BORRADO' end,
    v_cambios,
    coalesce(lower(auth.jwt() ->> 'email'), 'sistema'),
    public.app_cod_ope()
  );
  return coalesce(new, old);
end $$;

create trigger fincas_auditoria    after insert or update or delete on public.fincas    for each row execute function public.tg_auditoria('cod_fin');
create trigger parcelas_auditoria  after insert or update or delete on public.parcelas  for each row execute function public.tg_auditoria('cod_par');
create trigger tareas_auditoria    after insert or update or delete on public.tareas    for each row execute function public.tg_auditoria('cod_tar');
create trigger vehiculos_auditoria after insert or update or delete on public.vehiculos for each row execute function public.tg_auditoria('id_mat');
create trigger aperos_auditoria    after insert or update or delete on public.aperos    for each row execute function public.tg_auditoria('id_bas');
create trigger operarios_auditoria after insert or update or delete on public.operarios for each row execute function public.tg_auditoria('cod_ope');

alter table public.auditoria enable row level security;

create policy auditoria_select_admin on public.auditoria for select to authenticated
  using ((select public.app_rol()) = 'ADMIN');
create policy auditoria_select_supervisor on public.auditoria for select to authenticated
  using ((select public.app_rol()) = 'SUPERVISOR' and tabla <> 'operarios');
-- Sin políticas de escritura. Además se retiran los permisos por si alguna política se añadiera por error.
revoke insert, update, delete, truncate on public.auditoria from anon, authenticated;

revoke execute on function public.tg_auditoria() from public, anon, authenticated;
