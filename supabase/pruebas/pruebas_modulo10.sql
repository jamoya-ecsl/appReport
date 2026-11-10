-- =====================================================================
-- Pruebas del módulo 10 (migración 019: jornada y líneas por separado). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Código L (14 casos). Jornada de prueba 07:00–15:00.
-- Parte de prueba (operario), por orden: l1 DESPLAZAMIENTO 07:00–07:30 · l2 tarea 07:30–09:00 · l3 tarea 09:00–10:00
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; f2 text; v1 text; t1 text; x text; n int;
  id1 uuid; id2 uuid; l1 uuid; l2 uuid; l3 uuid; lx uuid;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  tarea jsonb;
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select cod_fin into f2 from fincas where activo and cod_fin <> f1 order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  tarea := jsonb_build_object('tarea', t1, 'finca', f1);

  -- ===== JORNADA Y LÍNEAS NUEVAS =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_cabecera(null, cab || '{"fecha":"2099-09-01"}');
    select estado||' lineas='||(select count(*) from partes_det where id_parte = id1) into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb(text 'L01 aceptar la jornada crea el parte (esperado Pendiente lineas=0): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'L01 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    l1 := guardar_linea(id1, jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'));
    reset role; res := res || to_jsonb(text 'L02 primera línea, DESPLAZAMIENTO (esperado OK): '||(l1 is not null)::text);
  exception when others then reset role; res := res || to_jsonb(text 'L02 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_linea(id1, tarea || '{"h_ini":"07:15","h_fin":"08:00"}');
    reset role; res := res || to_jsonb(text 'L03 línea nueva que empieza antes del fin de la última (esperado bloqueado "07:30 o más tarde"): GUARDADA');
  exception when others then reset role; res := res || to_jsonb(text 'L03 línea nueva fuera de orden (esperado bloqueado "07:30 o más tarde"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    l2 := guardar_linea(id1, tarea || '{"h_ini":"07:30","h_fin":"09:00"}');
    l3 := guardar_linea(id1, tarea || '{"h_ini":"09:00","h_fin":"10:00"}');
    select count(*) into n from partes_det where id_parte = id1;
    reset role; res := res || to_jsonb(text 'L04 dos líneas más en orden (esperado 3): '||n);
  exception when others then reset role; res := res || to_jsonb(text 'L04 (esperado 3): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_linea(id1, jsonb_build_object('tarea',t1,'finca',f2,'h_ini','10:00','h_fin','11:00'));
    reset role; res := res || to_jsonb(text 'L05 tarea en otra finca sin desplazamiento (esperado bloqueado "hace falta antes un DESPLAZAMIENTO"): GUARDADA');
  exception when others then
    reset role;
    select count(*) into n from partes_det where id_parte = id1;
    res := res || to_jsonb(text 'L05 tarea en otra finca sin desplazamiento (esperado bloqueado y siguen 3): bloqueado, siguen '||n||': '||sqlerrm);
  end;

  -- ===== EDITAR Y QUITAR =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_linea(id1, tarea || jsonb_build_object('id_linea',l2,'h_ini','07:30','h_fin','09:30'));
    reset role; res := res || to_jsonb(text 'L06 alargar una línea intermedia sobre la siguiente (esperado bloqueado "09:00 o antes"): GUARDADA');
  exception when others then reset role; res := res || to_jsonb(text 'L06 alargar una línea intermedia (esperado bloqueado "09:00 o antes"): bloqueado: '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_linea(id1, tarea || jsonb_build_object('id_linea',l2,'h_ini','07:30','h_fin','08:30'));
    select t_horas::text into x from partes_det where id_linea = l2;
    reset role; res := res || to_jsonb(text 'L07 acortar una línea intermedia dentro de su hueco (esperado OK 1.00): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'L07 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform borrar_linea(l1);
    reset role; res := res || to_jsonb(text 'L08 quitar el DESPLAZAMIENTO del que dependen las tareas (esperado bloqueado "la primera tarea"): BORRADA');
  exception when others then
    reset role;
    select count(*) into n from partes_det where id_parte = id1;
    res := res || to_jsonb(text 'L08 quitar el DESPLAZAMIENTO (esperado bloqueado y siguen 3): bloqueado, siguen '||n||': '||sqlerrm);
  end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform borrar_linea(l3);
    select count(*) into n from partes_det where id_parte = id1;
    reset role; res := res || to_jsonb(text 'L09 quitar la última línea (esperado OK 2): '||n);
  exception when others then reset role; res := res || to_jsonb(text 'L09 (esperado OK): ERROR '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_cabecera(id1, cab || '{"fecha":"2099-09-01","h_sal":"08:00"}');
    reset role; res := res || to_jsonb(text 'L10 acortar la jornada dejando una tarea fuera (esperado bloqueado "dentro de la jornada"): GUARDADA');
  exception when others then reset role; res := res || to_jsonb(text 'L10 acortar la jornada (esperado bloqueado "dentro de la jornada"): bloqueado: '||sqlerrm); end;

  -- ===== PERMISOS =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id2 := guardar_cabecera(null, cab || '{"fecha":"2099-09-02","operario":"T002"}');
    lx := guardar_linea(id2, jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'));
    perform set_config('request.jwt.claims',c_op,true);
    perform guardar_linea(id2, tarea || '{"h_ini":"07:30","h_fin":"08:00"}');
    reset role; res := res || to_jsonb(text 'L11 operario añade una línea a un parte de otro (esperado bloqueado 42501): GUARDADA');
  exception when others then reset role; res := res || to_jsonb(text 'L11 operario en parte de otro (esperado bloqueado 42501): bloqueado '||sqlstate); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id1);
    begin
      perform guardar_linea(id1, tarea || '{"h_ini":"08:30","h_fin":"09:00"}');
      x := 'operario GUARDÓ';
    exception when others then x := 'operario bloqueado '||sqlstate; end;
    perform set_config('request.jwt.claims',c_sup,true);
    perform guardar_linea(id1, tarea || '{"h_ini":"08:30","h_fin":"09:00"}');
    select x||', supervisor OK, lineas='||count(*) into x from partes_det where id_parte = id1;
    reset role; res := res || to_jsonb(text 'L12 parte Cerrado (esperado operario bloqueado 42501, supervisor OK, lineas=3): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'L12 (esperado OK): ERROR '||coalesce(x,'')||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_linea(id1, tarea || jsonb_build_object('id_linea',lx,'h_ini','09:00','h_fin','09:30'));
    reset role; res := res || to_jsonb(text 'L13 editar con el id de una línea de otro parte (esperado bloqueado 42501): GUARDADA');
  exception when others then reset role; res := res || to_jsonb(text 'L13 línea de otro parte (esperado bloqueado 42501): bloqueado '||sqlstate); end;

  begin
    x := 'anon=' || has_function_privilege('anon', 'public.guardar_linea(uuid, jsonb)', 'execute')
       || ' authenticated=' || has_function_privilege('authenticated', 'public.guardar_linea(uuid, jsonb)', 'execute')
       || ' interna=' || has_function_privilege('authenticated', 'public.parte_para_editar(uuid)', 'execute');
    res := res || to_jsonb(text 'L14 permisos (esperado anon=false authenticated=true interna=false): '||x);
  exception when others then res := res || to_jsonb(text 'L14 ERROR '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
