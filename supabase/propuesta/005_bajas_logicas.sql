-- =====================================================================
-- 005 · Bajas lógicas en datos maestros (aprobado 22/10/2026, mejora A)
--  * activo / fecha_baja / baja_por en fincas, parcelas, tareas, vehiculos, aperos.
--  * fecha_baja y baja_por los fija la BD (no se pueden falsear).
--  * Un parte NUEVO (o un valor CAMBIADO) no puede usar un registro dado de baja.
--    Los partes históricos conservan sus referencias.
--  * La parcela de una línea debe pertenecer a su finca (antes solo lo comprobaba la app).
-- =====================================================================

create function public.tg_baja_logica() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.activo is distinct from old.activo then
    if new.activo then
      new.fecha_baja := null;
      new.baja_por := null;
    else
      new.fecha_baja := now();
      new.baja_por := coalesce(lower(auth.jwt() ->> 'email'), 'sistema');
    end if;
  else
    new.fecha_baja := old.fecha_baja;
    new.baja_por := old.baja_por;
  end if;
  return new;
end $$;

do $$ declare t text; begin
  foreach t in array array['fincas','parcelas','tareas','vehiculos','aperos'] loop
    execute format('alter table public.%I
                      add column activo boolean not null default true,
                      add column fecha_baja timestamptz,
                      add column baja_por text', t);
    execute format('create trigger %1$s_baja_logica before insert or update on public.%1$s
                    for each row execute function public.tg_baja_logica()', t);
  end loop;
end $$;

-- Comprueba que las referencias NUEVAS o CAMBIADAS apuntan a registros activos.
-- Argumentos del disparador: 'columna:tabla:clave' (fijos, definidos aquí abajo).
create function public.tg_validar_referencias_activas() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nuevo jsonb := to_jsonb(new);
  viejo jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  col text; tabla text; clave text; v_activo boolean;
begin
  for i in 0 .. tg_nargs - 1 loop
    col   := split_part(tg_argv[i], ':', 1);
    tabla := split_part(tg_argv[i], ':', 2);
    clave := split_part(tg_argv[i], ':', 3);
    if nuevo ->> col is not null and (nuevo ->> col) is distinct from (viejo ->> col) then
      execute format('select activo from public.%I where %I = $1', tabla, clave)
        into v_activo using nuevo ->> col;
      if v_activo is false then
        raise exception 'El registro "%" de % está dado de baja y no se puede usar', nuevo ->> col, tabla;
      end if;
    end if;
  end loop;
  return new;
end $$;

create trigger partes_cab_referencias_activas before insert or update on public.partes_cab
  for each row execute function public.tg_validar_referencias_activas(
    'finca:fincas:cod_fin', 'vehiculo:vehiculos:id_mat');

create trigger partes_det_referencias_activas before insert or update on public.partes_det
  for each row execute function public.tg_validar_referencias_activas(
    'tarea:tareas:cod_tar', 'finca:fincas:cod_fin', 'parcela:parcelas:cod_par',
    'vehiculo:vehiculos:id_mat', 'apero:aperos:id_bas');

create trigger partes_mant_referencias_activas before insert or update on public.partes_mant
  for each row execute function public.tg_validar_referencias_activas(
    'vehiculo:vehiculos:id_mat', 'apero:aperos:id_bas');

-- Parcela coherente con la finca de la línea (si falta la finca, se toma de la parcela).
create function public.tg_partes_det_parcela_finca() returns trigger
language plpgsql set search_path = public as $$
declare
  v_finca text;
begin
  if new.parcela is not null then
    select finca into v_finca from public.parcelas where cod_par = new.parcela;
    if new.finca is null then
      new.finca := v_finca;
    elsif v_finca is distinct from new.finca then
      raise exception 'La parcela % no pertenece a la finca %', new.parcela, new.finca;
    end if;
  end if;
  return new;
end $$;

create trigger partes_det_parcela_finca before insert or update on public.partes_det
  for each row execute function public.tg_partes_det_parcela_finca();

revoke execute on function public.tg_baja_logica(), public.tg_validar_referencias_activas(),
  public.tg_partes_det_parcela_finca() from public, anon, authenticated;
