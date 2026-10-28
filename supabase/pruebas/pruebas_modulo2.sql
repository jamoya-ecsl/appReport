-- =====================================================================
-- Pruebas del módulo 2 (migraciones 010a y 010). Ejecutar DESPUÉS de aplicarlas.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado: "OK" debe funcionar; "bloqueado" debe rechazarse.
-- Códigos: E = operario, R = supervisor, D = admin, X = SQL Editor sin sesión.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; v1 text; t1 text; n int; x text;
  cab jsonb; lin jsonb;
  id_a uuid; id_b uuid; id_c uuid; id_vacio uuid; id_nave uuid; id_s uuid; num_a bigint;
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  cab := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes');
  lin := jsonb_build_array(
    jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
    jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','12:00'));

  -- ===== OPERARIO T003: crea partes de partida =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id_a     := guardar_parte(null, cab || '{"fecha":"2099-04-01"}', lin);
    id_b     := guardar_parte(null, cab || '{"fecha":"2099-04-02"}', lin);
    id_c     := guardar_parte(null, cab || '{"fecha":"2099-04-03"}', lin);
    id_vacio := guardar_parte(null, cab || '{"fecha":"2099-04-04"}', '[]');
    id_nave  := guardar_parte(null, cab || '{"fecha":"2099-04-05","mat_nave":true}', '[]');
    select string_agg(distinct estado::text, ',') into x from partes_cab where id_parte in (id_a,id_b,id_c,id_vacio,id_nave);
    reset role; res := res || to_jsonb('E01 operario crea 5 partes (esperado OK, todos Pendiente): estados='||x);
  exception when others then res := res || to_jsonb('E01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id_vacio);
    reset role; res := res || to_jsonb('E02 cerrar parte sin tareas y sin nave (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E02 cerrar sin tareas ni nave: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id_nave);
    select estado::text into x from partes_cab where id_parte = id_nave;
    reset role; res := res || to_jsonb('E03 cerrar parte en nave sin tareas (esperado OK): '||x);
  exception when others then res := res || to_jsonb('E03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id_a);
    select estado||' cerrado_por='||coalesce(cerrado_por,'null')||' fecha_cierre='||(fecha_cierre is not null)
      into x from partes_cab where id_parte = id_a;
    reset role; res := res || to_jsonb('E04 operario cierra su parte (esperado OK): '||x);
  exception when others then res := res || to_jsonb('E04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id_a, cab || '{"fecha":"2099-04-01","obs":"cambio tras cerrar"}', '[]');
    reset role; res := res || to_jsonb('E05 operario edita su parte cerrado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E05 operario edita parte cerrado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id_a);
    reset role; res := res || to_jsonb('E06 cerrar dos veces (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E06 cerrar dos veces: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform revisar_parte(id_a, 'Aprobado');
    reset role; res := res || to_jsonb('E07 operario aprueba su parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E07 operario aprueba: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update partes_cab set estado = 'Cerrado' where id_parte = id_c; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('E08 operario cambia estado con UPDATE directo (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('E08 UPDATE directo: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into partes_cab (operario, fecha, h_ent, h_sal) values ('T003','2099-04-06','07:00','15:00');
    reset role; res := res || to_jsonb('E09 operario INSERT directo en partes_cab (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E09 INSERT directo: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform borrar_parte(id_c);
    reset role; res := res || to_jsonb('E10 operario borra su parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E10 operario borra: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== SUPERVISOR T001 =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id_s := guardar_parte(null, cab || '{"fecha":"2099-04-10"}', lin);
    perform cerrar_parte(id_s);
    select estado||' cerrado_por='||coalesce(cerrado_por,'null') into x from partes_cab where id_parte = id_s;
    reset role; res := res || to_jsonb('R01 supervisor crea y cierra su parte (esperado OK): '||x);
  exception when others then res := res || to_jsonb('R01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform cerrar_parte(id_s);
    reset role; res := res || to_jsonb('E11 operario cierra parte ajeno (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E11 operario cierra parte ajeno: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_s, 'Aprobado');
    reset role; res := res || to_jsonb('R02 supervisor aprueba su propio parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R02 supervisor se autoaprueba: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform cerrar_parte(id_b);
    select estado||' cerrado_por='||coalesce(cerrado_por,'null') into x from partes_cab where id_parte = id_b;
    reset role; res := res || to_jsonb('R03 supervisor cierra parte de un operario (esperado OK): '||x);
  exception when others then res := res || to_jsonb('R03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_c, 'Aprobado');
    reset role; res := res || to_jsonb('R04 aprobar parte Pendiente sin cerrar (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R04 aprobar sin cerrar: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_a, 'Rechazado', '   ');
    reset role; res := res || to_jsonb('R05 rechazar sin comentario (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R05 rechazar sin comentario: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_a, 'Rechazado', 'Falta la parcela');
    select estado||' revisa='||coalesce(supervisor_revisa,'null')||' comentario='||coalesce(comentario_supervisor,'null')
      into x from partes_cab where id_parte = id_a;
    reset role; res := res || to_jsonb('R06 supervisor rechaza con comentario (esperado OK): '||x);
  exception when others then res := res || to_jsonb('R06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_a, 'Aprobado');
    reset role; res := res || to_jsonb('R07 aprobar un parte ya rechazado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R07 Rechazado es final: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id_b, 'Aprobado');
    select estado||' revisa='||coalesce(supervisor_revisa,'null') into x from partes_cab where id_parte = id_b;
    reset role; res := res || to_jsonb('R08 supervisor aprueba parte cerrado ajeno (esperado OK): '||x);
  exception when others then res := res || to_jsonb('R08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform borrar_parte(id_c);
    reset role; res := res || to_jsonb('R09 supervisor borra un parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R09 supervisor borra: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set estado = 'Cerrado' where id_parte = id_c; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('R10 supervisor cambia estado con UPDATE directo (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('R10 UPDATE directo: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id_a, cab || '{"fecha":"2099-04-01","obs":"corrijo tras rechazo"}', lin);
    reset role; res := res || to_jsonb('E12 operario corrige su parte rechazado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('E12 operario edita rechazado: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== ADMIN T000 =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform revisar_parte(id_s, 'Aprobado');
    select estado||' revisa='||coalesce(supervisor_revisa,'null') into x from partes_cab where id_parte = id_s;
    reset role; res := res || to_jsonb('D01 admin aprueba el parte del supervisor (esperado OK): '||x);
  exception when others then res := res || to_jsonb('D01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id_b, cab || '{"fecha":"2099-04-02","obs":"corregido por admin"}',
      lin || jsonb_build_array(jsonb_build_object('tarea',t1,'finca',f1,'h_ini','12:00','h_fin','13:00')));
    select estado||' obs='||coalesce(obs,'null')||' lineas='||(select count(*) from partes_det d where d.id_parte = id_b)
      into x from partes_cab where id_parte = id_b;
    reset role; res := res || to_jsonb('D02 admin modifica un parte aprobado, cabecera y tareas (esperado OK, sigue Aprobado): '||x);
  exception when others then res := res || to_jsonb('D02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform revisar_parte(id_c, 'Pendiente');
    reset role; res := res || to_jsonb('D03 revisar_parte con estado no válido (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('D03 revisión no válida: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update partes_cab set obs = 'directo' where id_parte = id_c; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('D04 admin UPDATE directo en partes_cab (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('D04 UPDATE directo admin: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select count(*) into n from jsonb_object_keys(panel_resumen()) k where k in ('pendientes_revision','sin_cerrar');
    select 'claves='||n||' pendientes_revision='||(panel_resumen()->>'pendientes_revision')||' sin_cerrar='||(panel_resumen()->>'sin_cerrar') into x;
    reset role; res := res || to_jsonb('D05 panel admin (esperado claves=2, revisión = Cerrados): '||x);
  exception when others then res := res || to_jsonb('D05 panel (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select num_parte into num_a from partes_cab where id_parte = id_a;
    perform borrar_parte(id_a);
    select 'cabecera='||(select count(*) from partes_cab where id_parte = id_a)
         ||' lineas='||(select count(*) from partes_det where id_parte = id_a)
         ||' auditoria='||(select count(*) from auditoria where tabla = 'partes_cab' and registro = num_a::text and accion = 'BORRADO')
         ||' lineas_en_auditoria='||(select jsonb_array_length(cambios->'lineas') from auditoria
                                     where tabla = 'partes_cab' and registro = num_a::text and accion = 'BORRADO' limit 1)
      into x;
    reset role; res := res || to_jsonb('D06 admin borra un parte rechazado (esperado OK, 0/0 y copia en auditoría): '||x);
  exception when others then res := res || to_jsonb('D06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== SQL EDITOR (sin sesión): las transiciones también se imponen =====
  begin
    perform set_config('request.jwt.claims','',true); reset role;
    update partes_cab set estado = 'Pendiente' where id_parte = id_b;
    res := res || to_jsonb('X01 reabrir un parte aprobado desde SQL (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('X01 reabrir desde SQL: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims','',true); reset role;
    update partes_cab set estado = 'Aprobado' where id_parte = id_c;
    res := res || to_jsonb('X02 Pendiente → Aprobado desde SQL (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('X02 saltarse el cierre desde SQL: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims','',true); reset role;
    insert into partes_cab (operario, fecha, h_ent, h_sal, estado, creado_por)
    values ('T003','2099-04-07','07:00','15:00','Cerrado','sistema');
    res := res || to_jsonb('X03 crear un parte ya Cerrado desde SQL (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('X03 parte nuevo no Pendiente: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims','',true); reset role;
    update partes_cab set estado = 'Cerrado' where id_parte = id_vacio;
    res := res || to_jsonb('X04 cerrar desde SQL un parte sin tareas ni nave (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('X04 cerrar sin tareas desde SQL: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
