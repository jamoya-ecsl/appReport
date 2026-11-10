-- =====================================================================
-- Pruebas del módulo 9 (migración 018: el mantenimiento como tipo de tarea). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Código M (14 casos). Jornada de prueba 07:00–15:00.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; v1 text; a1 text; t1 text; x text; n int;
  id1 uuid; num1 bigint;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  desp jsonb;
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select id_bas into a1 from aperos where activo order by id_bas limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  desp := jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30');

  -- ===== CATÁLOGO =====
  begin
    select string_agg(cod_tar||'='||tipo, ' ' order by cod_tar) into x from tareas where cod_tar in ('TN001','TV001');
    res := res || to_jsonb(text 'M01 tareas nuevas (esperado TN001=MANTENIMIENTO NAVE TV001=MANTENIMIENTO VEHÍCULOS): '||coalesce(x,'ninguna'));
  exception when others then res := res || to_jsonb(text 'M01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    select (select count(*) from information_schema.columns where table_schema='public' and table_name='partes_cab' and column_name='mat_nave')
           ||' '||coalesce(to_regclass('public.partes_mant')::text, 'sin_tabla') into x;
    res := res || to_jsonb(text 'M02 mat_nave y partes_mant eliminados (esperado 0 sin_tabla): '||x);
  exception when others then res := res || to_jsonb(text 'M02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== REGLAS DE LAS LÍNEAS =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-01"}', jsonb_build_array(
      jsonb_build_object('tarea','TN001','h_ini','07:00','h_fin','08:00'),
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','08:00','h_fin','08:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','08:30','h_fin','10:00')));
    reset role; res := res || to_jsonb(text 'M03 MANTENIMIENTO NAVE como primera tarea, después desplazamiento y tarea (esperado OK): OK');
  exception when others then reset role; res := res || to_jsonb(text 'M03 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-02"}', jsonb_build_array(
      jsonb_build_object('tarea','TN001','finca',f1,'h_ini','07:00','h_fin','08:00')));
    reset role; res := res || to_jsonb(text 'M04 MANTENIMIENTO NAVE con finca (esperado bloqueado "solo se indican las horas"): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'M04 MANTENIMIENTO NAVE con finca (esperado bloqueado "solo se indican las horas"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-03"}', jsonb_build_array(
      jsonb_build_object('tarea','TV001','vehiculo',v1,'h_ini','07:00','h_fin','08:00')));
    reset role; res := res || to_jsonb(text 'M05 MANTENIMIENTO VEHÍCULOS como primera tarea (esperado bloqueado "la primera tarea"): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'M05 MANTENIMIENTO VEHÍCULOS como primera tarea (esperado bloqueado "la primera tarea"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-04"}', jsonb_build_array(desp,
      jsonb_build_object('tarea','TV001','h_ini','07:30','h_fin','08:30')));
    reset role; res := res || to_jsonb(text 'M06 MANTENIMIENTO VEHÍCULOS sin vehículo ni apero (esperado bloqueado "necesita vehículo o apero"): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'M06 MANTENIMIENTO VEHÍCULOS sin vehículo ni apero (esperado bloqueado "necesita vehículo o apero"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-05"}', jsonb_build_array(desp,
      jsonb_build_object('tarea','TV001','finca',f1,'vehiculo',v1,'h_ini','07:30','h_fin','08:30')));
    reset role; res := res || to_jsonb(text 'M07 MANTENIMIENTO VEHÍCULOS con finca (esperado bloqueado "no se indica finca ni parcela"): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'M07 MANTENIMIENTO VEHÍCULOS con finca (esperado bloqueado "no se indica finca ni parcela"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-06"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','09:00'),
      jsonb_build_object('tarea','TV001','vehiculo',v1,'h_ini','09:00','h_fin','10:00'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','10:00','h_fin','11:00')));
    reset role; res := res || to_jsonb(text 'M08 mantenimiento entre dos tareas de la misma finca, sin otro desplazamiento (esperado OK): OK');
  exception when others then reset role; res := res || to_jsonb(text 'M08 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-07"}', jsonb_build_array(
      jsonb_build_object('tarea','TN001','h_ini','07:00','h_fin','08:00'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','08:00','h_fin','09:00')));
    reset role; res := res || to_jsonb(text 'M09 tras MANTENIMIENTO NAVE, tarea en finca sin desplazamiento (esperado bloqueado "hace falta antes un DESPLAZAMIENTO"): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'M09 tras MANTENIMIENTO NAVE, tarea en finca sin desplazamiento (esperado bloqueado "hace falta antes un DESPLAZAMIENTO"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-08-08"}', jsonb_build_array(
      jsonb_build_object('tarea','TN001','h_ini','07:00','h_fin','08:00'),
      jsonb_build_object('tarea','TV001','apero',a1,'h_ini','08:00','h_fin','09:00')));
    reset role; res := res || to_jsonb(text 'M10 MANTENIMIENTO VEHÍCULOS solo con apero, tras MANTENIMIENTO NAVE (esperado OK): OK');
  exception when others then reset role; res := res || to_jsonb(text 'M10 (esperado OK): ERROR '||sqlerrm); end;

  -- ===== CIERRE =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, cab || '{"fecha":"2099-08-09"}', jsonb_build_array(
      jsonb_build_object('tarea','TP001','h_ini','07:00','h_fin','08:00')));
    perform cerrar_parte(id1);
    reset role; res := res || to_jsonb(text 'M11 cerrar un parte solo con MOTIVOS PERSONALES (esperado bloqueado "al menos una tarea"): CERRADO');
  exception when others then reset role; res := res || to_jsonb(text 'M11 cerrar un parte solo con MOTIVOS PERSONALES (esperado bloqueado "al menos una tarea"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, cab || '{"fecha":"2099-08-10"}', jsonb_build_array(
      jsonb_build_object('tarea','TN001','h_ini','07:00','h_fin','14:30')));
    perform cerrar_parte(id1);
    select estado::text into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb(text 'M12 cerrar un parte solo con MANTENIMIENTO NAVE (esperado OK Cerrado): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'M12 (esperado OK): ERROR '||sqlerrm); end;

  -- ===== ARCHIVO Y PDF =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, cab || '{"fecha":"2099-08-11"}', jsonb_build_array(desp,
      jsonb_build_object('tarea','TV001','vehiculo',v1,'h_ini','07:30','h_fin','09:00')));
    perform cerrar_parte(id1);
    perform set_config('request.jwt.claims',c_sup,true);
    perform revisar_parte(id1, 'Aprobado', null);
    select num_parte into num1 from partes_cab where id_parte = id1;
    select count(*) into n from tareas_resumen where num_parte = num1 and tarea = 'TV001' and horas = 1.5;
    reset role; res := res || to_jsonb(text 'M13 un mantenimiento Aprobado aparece en las tareas para archivar (esperado 1): '||n);
  exception when others then reset role; res := res || to_jsonb(text 'M13 (esperado 1): ERROR '||sqlerrm); end;

  begin
    reset role;
    x := (pdf_datos(id1) ? 'mat_nave')::text || ' lineas=' || jsonb_array_length(pdf_datos(id1) -> 'lineas');
    res := res || to_jsonb(text 'M14 foto del PDF sin mat_nave (esperado false lineas=2): '||x);
  exception when others then res := res || to_jsonb(text 'M14 (esperado OK): ERROR '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
