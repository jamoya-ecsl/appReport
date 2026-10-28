-- =====================================================================
-- Pruebas del módulo 1 (migración 009). Ejecutar DESPUÉS de aplicar 009a y 009.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado: "OK" debe guardarse; "bloqueado" debe rechazarse.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; f2 text; v1 text; t1 text; id_m01 uuid; id_sup uuid; linea_sup uuid; tmp uuid; n int; x text;
  cab jsonb;
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select cod_fin into f2 from fincas where activo and cod_fin <> f1 order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  cab := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes');

  -- Atajos para construir líneas: D = desplazamiento, T = tarea normal, P = motivos personales
  -- (se escriben inline con jsonb_build_object)

  -- ===== OPERARIO T003 =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    -- líneas enviadas desordenadas a propósito: el orden lo da h_ini
    id_m01 := guardar_parte(null, cab || '{"fecha":"2099-03-01"}', jsonb_build_array(
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','10:00','h_fin','12:00'),
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','10:00')));
    select 'tot_horas='||tot_horas into x from partes_cab where id_parte=id_m01;
    reset role; res := res || to_jsonb('M01 desplazamiento + tareas misma finca (esperado OK): OK '||x);
  exception when others then res := res || to_jsonb('M01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-02"}', jsonb_build_array(
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:00','h_fin','08:00')));
    reset role; res := res || to_jsonb('M02 primera tarea no es desplazamiento (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M02 primera tarea no es desplazamiento: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-03"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'h_ini','07:00','h_fin','07:30')));
    reset role; res := res || to_jsonb('M03 desplazamiento sin vehículo (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M03 desplazamiento sin vehículo: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-04"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'h_ini','07:30','h_fin','08:00')));
    reset role; res := res || to_jsonb('M04 tarea sin finca (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M04 tarea sin finca: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-05"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','08:00'),
      jsonb_build_object('tarea',t1,'finca',f2,'h_ini','08:00','h_fin','09:00')));
    reset role; res := res || to_jsonb('M05 cambio de finca sin desplazamiento (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M05 cambio de finca sin desplazamiento: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-06"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','09:00'),
      jsonb_build_object('tarea','TD001','finca',f2,'vehiculo',v1,'h_ini','09:00','h_fin','09:30'),
      jsonb_build_object('tarea',t1,'finca',f2,'h_ini','09:30','h_fin','11:00')));
    reset role; res := res || to_jsonb('M06 cambio de finca con desplazamiento (esperado OK): OK'::text);
  exception when others then res := res || to_jsonb('M06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-07"}', jsonb_build_array(
      jsonb_build_object('tarea','TP001','finca',f1,'h_ini','07:00','h_fin','07:30')));
    reset role; res := res || to_jsonb('M07 motivos personales con finca (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M07 motivos personales con finca: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-08"}', jsonb_build_array(
      jsonb_build_object('tarea','TP001','h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:30','h_fin','08:00'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','08:00','h_fin','09:00'),
      jsonb_build_object('tarea','TP001','h_ini','09:15','h_fin','09:45'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','10:00','h_fin','11:00')));
    reset role; res := res || to_jsonb('M08 motivos personales al inicio y en medio, con huecos (esperado OK): OK'::text);
  exception when others then res := res || to_jsonb('M08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-09"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','09:00'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','08:45','h_fin','10:00')));
    reset role; res := res || to_jsonb('M09 tareas solapadas (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M09 tareas solapadas: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-10"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','06:45','h_fin','07:30')));
    reset role; res := res || to_jsonb('M10 tarea antes de la entrada (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M10 tarea antes de la entrada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-11"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','14:30','h_fin','15:15')));
    reset role; res := res || to_jsonb('M11 tarea después de la salida (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M11 tarea después de la salida: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-12"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:35')));
    reset role; res := res || to_jsonb('M12 tarea a las 07:35 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M12 tarea a las 07:35: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-13","h_ent":"07:10"}', '[]');
    reset role; res := res || to_jsonb('M13 entrada a las 07:10 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M13 entrada a las 07:10: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-14","t_alm":"20 minutes"}', '[]');
    reset role; res := res || to_jsonb('M14 almuerzo de 20 min (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M14 almuerzo de 20 min: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-15","h_ext":0.3}', '[]');
    reset role; res := res || to_jsonb('M15 h_ext = 0,3 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M15 h_ext = 0,3: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-16","h_ext":-1}', '[]');
    reset role; res := res || to_jsonb('M16 h_ext negativo (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M16 h_ext negativo: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into partes_det (id_parte, tarea, finca, h_ini, h_fin) values (id_m01, t1, f1, '12:00', '13:00');
    reset role; res := res || to_jsonb('M17 operario escribe una línea directamente (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M17 escritura directa de línea: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    delete from partes_det where id_parte = id_m01; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('M18 operario borra líneas directamente (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('M18 borrado directo de líneas: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update partes_cab set h_sal = '09:00' where id_parte = id_m01;   -- deja tareas fuera de la jornada
    set constraints all immediate;                                     -- fuerza la comprobación diferida
    set constraints all deferred;
    reset role; res := res || to_jsonb('M19 acortar la jornada por la API dejando tareas fuera (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then
    set constraints all deferred;
    res := res || to_jsonb('M19 acortar la jornada por la API: bloqueado '||sqlstate||' '||sqlerrm);
  end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id_m01, cab || '{"fecha":"2099-03-01"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'vehiculo',d.vehiculo,
                                           'h_ini',d.h_ini,'h_fin',d.h_fin))
       from partes_det d join tareas t on t.cod_tar=d.tarea where d.id_parte=id_m01 and t.tipo <> 'DESPLAZAMIENTO'));
    reset role; res := res || to_jsonb('M20 editar quitando el desplazamiento (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M20 editar quitando el desplazamiento: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-03-17","mat_nave":true}', '[]');
    reset role; res := res || to_jsonb('M21 parte en nave sin tareas (esperado OK): OK'::text);
  exception when others then res := res || to_jsonb('M21 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform validar_parte(id_m01);
    reset role; res := res || to_jsonb('M22 operario llama a validar_parte por la API (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('M22 validar_parte no expuesta: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== SUPERVISOR T001 =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id_sup := guardar_parte(null, cab || '{"fecha":"2099-03-20"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','09:00')));
    reset role; res := res || to_jsonb('S01 supervisor crea su propio parte con líneas (esperado OK): OK'::text);
  exception when others then res := res || to_jsonb('S01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id_m01, cab || '{"fecha":"2099-03-01"}', '[]');
    reset role; res := res || to_jsonb('S02 supervisor edita parte ajeno con guardar_parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S02 supervisor edita parte ajeno: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id_sup, cab || '{"fecha":"2099-03-20"}', '[]');
    reset role; res := res || to_jsonb('S03 supervisor edita su propio parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S03 supervisor edita su propio parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select string_agg(e->>'finca'||'='||(e->>'horas'), ',') into x
    from jsonb_array_elements(panel_resumen()->'horas_semana_por_finca') e;
    reset role; res := res || to_jsonb('S04 panel: horas por finca desde las líneas (esperado OK): '||coalesce(x,'(vacío)'));
  exception when others then res := res || to_jsonb('S04 panel (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Operario: parte ajeno y línea ajena
  select id_linea into linea_sup from partes_det where id_parte = id_sup limit 1;
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id_sup, cab || '{"fecha":"2099-03-20"}', '[]');
    reset role; res := res || to_jsonb('O01 operario edita parte ajeno (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O01 operario edita parte ajeno: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id_m01, cab || '{"fecha":"2099-03-01"}', jsonb_build_array(
      jsonb_build_object('id_linea',linea_sup,'tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30')));
    reset role; res := res || to_jsonb('O02 operario usa una línea de otro parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O02 línea de otro parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== ADMIN T000 =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(null, cab || jsonb_build_object('fecha','2099-03-21','operario','T003'), jsonb_build_array(
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:00','h_fin','08:00')));
    reset role; res := res || to_jsonb('D01 admin crea parte de T003 sin desplazamiento (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('D01 las reglas obligan al admin: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    tmp := guardar_parte(null, cab || jsonb_build_object('fecha','2099-03-22','operario','T003'), jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30')));
    perform guardar_parte(id_m01, cab || '{"fecha":"2099-03-01","obs":"corregido por admin"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'vehiculo',d.vehiculo,
                                           'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte=id_m01));
    reset role; res := res || to_jsonb('D02 admin crea parte de T003 y edita uno ajeno, cumpliendo reglas (esperado OK): OK'::text);
  exception when others then res := res || to_jsonb('D02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    insert into partes_det (id_parte, tarea, finca, h_ini, h_fin) values (id_m01, t1, f1, '12:00', '13:00');
    reset role; res := res || to_jsonb('D03 admin escribe una línea directamente (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('D03 escritura directa también para admin: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
