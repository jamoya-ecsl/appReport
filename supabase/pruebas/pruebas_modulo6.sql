-- =====================================================================
-- Pruebas del módulo 6 (migración 014: fin_vuelta). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Código F (10 casos).
-- Tareas del parte de prueba, por orden de hora:
--   desp  DESPLAZAMIENTO                     07:00–07:30  (no se aplica)
--   a     tarea POR HORAS con parcela         07:30–09:00  (SE APLICA)
--   b     tarea POR HORAS sin parcela         09:00–10:00  (no se aplica)
--   c     MOTIVOS PERSONALES                  10:00–10:30  (no se aplica)
--   d     tarea SIN TIPO con parcela          10:30–11:00  (no se aplica)
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; p1 text; v1 text; t1 text; n int; x text;
  id1 uuid; id2 uuid; num1 bigint;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  lin jsonb;
begin
  select f.cod_fin into f1 from fincas f
  where f.activo and exists (select 1 from parcelas p where p.finca = f.cod_fin and p.activo) order by f.cod_fin limit 1;
  select cod_par into p1 from parcelas where finca = f1 and activo order by cod_par limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;

  -- Tarea sin tipo para la línea d (sin sesión, como el SQL Editor)
  perform set_config('request.jwt.claims','',true);
  insert into tareas (cod_tar, tareas, tipo) values ('ZZT1', 'TAREA SIN TIPO (PRUEBA)', null);

  -- Se envía fin_vuelta = true en las que no se aplica: la BD debe guardar No.
  lin := jsonb_build_array(
    jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30','fin_vuelta',true),
    jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00'),
    jsonb_build_object('tarea',t1,'finca',f1,'h_ini','09:00','h_fin','10:00','fin_vuelta',true),
    jsonb_build_object('tarea','TP001','h_ini','10:00','h_fin','10:30','fin_vuelta',true),
    jsonb_build_object('tarea','ZZT1','finca',f1,'parcela',p1,'h_ini','10:30','h_fin','11:00','fin_vuelta',true));

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, cab || '{"fecha":"2099-08-01"}', lin);
    select num_parte into num1 from partes_cab where id_parte = id1;
    select 'fin_vuelta='||string_agg(coalesce(d.fin_vuelta::text, 'null'), ',' order by d.h_ini)
         ||' requiere='||string_agg(d.requiere_fin_vuelta::text, ',' order by d.h_ini)
      into x from partes_det d where d.id_parte = id1;
    reset role; res := res || to_jsonb('F01 operario guarda el parte sin responder (esperado fin_vuelta=false,null,false,false,false requiere=false,true,false,false,false): '||x);
  exception when others then res := res || to_jsonb('F01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id1);
    reset role; res := res || to_jsonb('F02 cerrar con una tarea sin responder (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('F02 cerrar sin responder: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-08-01"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin,
         'fin_vuelta', case when d.requiere_fin_vuelta then false else d.fin_vuelta end)) from partes_det d where d.id_parte = id1));
    perform cerrar_parte(id1);
    select estado||' fin_vuelta_a='||(select coalesce(fin_vuelta::text,'null') from partes_det where id_parte = id1 and h_ini = '07:30')
      into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('F03 operario responde No y cierra (esperado Cerrado fin_vuelta_a=false): '||x);
  exception when others then res := res || to_jsonb('F03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    -- Reenvía las tareas SIN el campo fin_vuelta: la tarea a quedaría sin responder.
    perform guardar_parte(id1, cab || '{"fecha":"2099-08-01"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id1));
    reset role; res := res || to_jsonb('F04 supervisor deja sin responder una tarea de un parte Cerrado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('F04 dejar sin responder en un Cerrado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-08-01"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin,
         'fin_vuelta', case when d.requiere_fin_vuelta then true else d.fin_vuelta end)) from partes_det d where d.id_parte = id1));
    select estado||' fin_vuelta_a='||(select coalesce(fin_vuelta::text,'null') from partes_det where id_parte = id1 and h_ini = '07:30')
      into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('F05 supervisor corrige a Sí antes de aprobar (esperado Cerrado fin_vuelta_a=true): '||x);
  exception when others then res := res || to_jsonb('F05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id1, 'Aprobado');
    select estado into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('F06 supervisor aprueba (esperado Aprobado): '||x);
  exception when others then res := res || to_jsonb('F06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select 'cambios='||count(*)||' ultimo='||coalesce((array_agg(cod_ope order by id desc))[1], 'null')
           ||' valores='||string_agg(coalesce(cambios->'fin_vuelta'->>'antes','null')||'→'||(cambios->'fin_vuelta'->>'despues'), ',' order by id)
      into x
    from auditoria where tabla = 'partes_det' and registro = num1::text and accion = 'MODIFICACION' and cambios ? 'fin_vuelta';
    reset role; res := res || to_jsonb('F07 auditoría de fin_vuelta (esperado cambios=2 ultimo=T001 valores=null→false,false→true): '||x);
  exception when others then res := res || to_jsonb('F07 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id2 := guardar_parte(null, cab || '{"fecha":"2099-08-02"}', lin);
    perform set_config('request.jwt.claims','',true); reset role;
    update partes_cab set estado = 'Cerrado' where id_parte = id2;
    res := res || to_jsonb('F08 cerrar sin responder desde el SQL Editor (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('F08 cerrar sin responder desde SQL: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id2 := guardar_parte(null, cab || '{"fecha":"2099-08-02","mat_nave":true}', lin);
    perform cerrar_parte(id2);
    reset role; res := res || to_jsonb('F09 parte de nave con una tarea sin responder (esperado bloqueado: también se exige): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('F09 parte de nave sin responder: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    x := 'anon='||has_function_privilege('anon', 'public.requiere_fin_vuelta(public.partes_det)', 'execute')
       ||' authenticated='||has_function_privilege('authenticated', 'public.requiere_fin_vuelta(public.partes_det)', 'execute')
       ||' pendientes_authenticated='||has_function_privilege('authenticated', 'public.fin_vuelta_pendientes(uuid)', 'execute');
    res := res || to_jsonb('F10 permisos (esperado anon=false authenticated=true pendientes_authenticated=false): '||x);
  exception when others then res := res || to_jsonb('F10 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
