-- =====================================================================
-- Pruebas de permisos y reglas por rol (comprueba las premisas de supabase/README.md).
--
-- Cómo usarlo: Dashboard → SQL Editor → pegar todo → Run.
-- El resultado sale como un ERROR "RESULTADOS(rollback) [...]": es a propósito.
-- Ese error final deshace TODO lo que hacen las pruebas, así que no queda ningún cambio.
-- Único rastro posible: un salto en la numeración de num_parte (las secuencias no se deshacen).
--
-- Simula las cuentas reales: T003 (OPERARIO), T001 (SUPERVISOR), T000 (ADMIN).
-- Usa fechas de 2099 y una finca de prueba 'ZZTEST' para no chocar con datos reales.
-- Cada línea del resultado empieza por un código (A=anon, O=operario, S=supervisor, D=admin).
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; p1 text; p_otra text; t1 text; parte_op uuid; new_op uuid; new_sup uuid; tmp uuid;
  n int; x text; x2 text; lin jsonb;
begin
  select f.cod_fin into f1 from fincas f where f.activo and exists (select 1 from parcelas p where p.finca=f.cod_fin and p.activo) limit 1;
  select cod_par into p1 from parcelas where finca=f1 and activo limit 1;
  select cod_par into p_otra from parcelas where finca<>f1 and activo limit 1;
  select cod_tar into t1 from tareas where activo limit 1;
  select id_parte into parte_op from partes_cab where operario='T003' and estado='Pendiente' order by fecha limit 1;
  lin := jsonb_build_array(jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','08:00','h_fin','12:00'));

  -- ===== SIN SESIÓN =====
  begin
    perform set_config('request.jwt.claims','{"role":"anon"}',true); set local role anon;
    select count(*) into n from partes_cab; x := 'partes_cab='||n;
    select count(*) into n from operarios; x := x||' operarios='||n;
    select count(*) into n from fincas; x := x||' fincas='||n;
    reset role;
    res := res || to_jsonb('A01 anon lee (esperado todo 0): '||x);
  exception when others then res := res || to_jsonb('A01 anon lee: '||sqlstate||' '||sqlerrm); end;

  -- ===== OPERARIO T003 =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from operarios; x := 'operarios='||n;
    select count(*) into n from partes_cab; x := x||' partes='||n;
    select count(*) into n from partes_cab where operario<>'T003'; x := x||' ajenos='||n;
    select count(*) into n from auditoria; x := x||' auditoria='||n;
    select count(*) into n from fincas; x := x||' fincas='||n;
    select count(*) into n from operarios_nombres(); x := x||' operarios_nombres='||n;
    select count(*) into n from operarios_sin_parte(null); x := x||' sin_parte='||n;
    select string_agg(k, ',') into x2 from jsonb_object_keys(panel_resumen()) k;
    reset role;
    res := res || to_jsonb('O01 operario lecturas: '||x||' panel=['||x2||']');
  exception when others then res := res || to_jsonb('O01 operario lecturas: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into fincas(cod_fin, finca) values ('ZZOP','x');
    reset role; res := res || to_jsonb('O02 operario crea finca: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O02 operario crea finca: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into partes_cab(operario, fecha, h_ent, h_sal, finca) values ('T000','2099-01-01','08:00','16:00',f1);
    reset role; res := res || to_jsonb('O03 operario crea parte de otro: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O03 operario crea parte de otro: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into partes_cab(operario, fecha, h_ent, h_sal, finca, estado) values ('T003','2099-01-02','08:00','16:00',f1,'Aprobado');
    reset role; res := res || to_jsonb('O04 operario crea parte ya aprobado: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O04 operario crea parte ya aprobado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    new_op := guardar_parte(null, jsonb_build_object('fecha','2099-01-05','h_ent','08:00','h_sal','16:00','t_alm','30 minutes','finca',f1), lin);
    select 'creado_por='||creado_por||' estado='||estado||' tot_horas='||tot_horas||' lineas='||(select count(*) from partes_det d where d.id_parte=new_op)
      into x from partes_cab where id_parte=new_op;
    reset role; res := res || to_jsonb('O05 operario guarda su parte con guardar_parte: OK '||x);
  exception when others then res := res || to_jsonb('O05 operario guarda su parte: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    insert into partes_cab(operario, fecha, h_ent, h_sal, finca, creado_por) values ('T003','2099-01-03','08:00','16:00',f1,'falso@x.com') returning id_parte into tmp;
    select creado_por into x from partes_cab where id_parte=tmp;
    reset role; res := res || to_jsonb('O06 creado_por lo fija la BD (envío falso@x.com): guardado='||x);
  exception when others then res := res || to_jsonb('O06 creado_por: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, jsonb_build_object('fecha','2099-01-05','h_ent','08:00','h_sal','16:00','finca',f1), '[]');
    reset role; res := res || to_jsonb('O07 dos partes el mismo día: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O07 dos partes el mismo día: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, jsonb_build_object('fecha','2099-01-06','h_ent','16:00','h_sal','08:00','finca',f1), '[]');
    reset role; res := res || to_jsonb('O08 salida antes que entrada: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O08 salida antes que entrada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, jsonb_build_object('fecha','2099-01-07','h_ent','08:00','h_sal','16:00','finca',f1),
      jsonb_build_array(jsonb_build_object('tarea',t1,'finca',f1,'parcela',p_otra,'h_ini','08:00','h_fin','12:00')));
    reset role; res := res || to_jsonb('O09 parcela de otra finca: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O09 parcela de otra finca: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, jsonb_build_object('fecha','2099-01-08','h_ent','08:00','h_sal','16:00','finca',f1),
      jsonb_build_array(jsonb_build_object('tarea',t1,'h_ini','08:00','h_fin','12:00'),
                        jsonb_build_object('tarea',t1,'h_ini','13:00','h_fin','12:00')));
    reset role; res := res || to_jsonb('O10 guardado atómico con línea errónea: FALLO, se permitió'::text);
  exception when others then
    select count(*) into n from partes_cab where operario='T003' and fecha='2099-01-08';
    res := res || to_jsonb('O10 guardado atómico con línea errónea: bloqueado '||sqlstate||', cabeceras que quedaron='||n);
  end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update partes_cab set estado='Aprobado' where id_parte=new_op;
    reset role; res := res || to_jsonb('O11 operario aprueba su parte: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O11 operario aprueba su parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    delete from partes_cab where id_parte=new_op; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('O12 operario borra su parte (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('O12 operario borra su parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== SUPERVISOR T001 =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select count(*) into n from operarios; x := 'operarios='||n;
    select count(*) into n from partes_cab; x := x||' partes='||n;
    select count(*) into n from partes_det; x := x||' lineas='||n;
    select count(*) into n from auditoria where tabla='operarios'; x := x||' auditoria_operarios='||n;
    select count(*) into n from operarios_nombres(); x := x||' operarios_nombres='||n;
    select count(*) into n from operarios_sin_parte(null); x := x||' sin_parte_hoy='||n;
    select string_agg(k, ',') into x2 from jsonb_object_keys(panel_resumen()) k;
    reset role; res := res || to_jsonb('S01 supervisor lecturas: '||x||' panel=['||x2||']');
  exception when others then res := res || to_jsonb('S01 supervisor lecturas: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set h_ent='07:00' where id_parte=parte_op;
    reset role; res := res || to_jsonb('S02 supervisor cambia contenido de parte ajeno: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S02 supervisor cambia contenido de parte ajeno: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_det set obs='cambio supervisor' where id_parte=parte_op; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('S03 supervisor cambia líneas de parte ajeno (esperado 0): '||n);
  exception when others then res := res || to_jsonb('S03 supervisor cambia líneas ajenas: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set estado='Rechazado', comentario_supervisor=null where id_parte=new_op;
    reset role; res := res || to_jsonb('S04 rechazar sin comentario: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S04 rechazar sin comentario: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set estado='Aprobado' where id_parte=new_op;
    select 'revisa='||coalesce(supervisor_revisa,'null')||' fecha_revision='||coalesce(fecha_revision::text,'null') into x from partes_cab where id_parte=new_op;
    reset role; res := res || to_jsonb('S05 supervisor aprueba: OK '||x);
  exception when others then res := res || to_jsonb('S05 supervisor aprueba: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update partes_cab set obs='editado tras aprobar' where id_parte=new_op; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('O13 operario edita parte ya aprobado (esperado 0): '||n);
  exception when others then res := res || to_jsonb('O13 operario edita parte aprobado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    insert into partes_cab(operario, fecha, h_ent, h_sal, finca) values ('T003','2099-01-10','08:00','16:00',f1);
    reset role; res := res || to_jsonb('S06 supervisor crea parte de otro: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S06 supervisor crea parte de otro: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    new_sup := guardar_parte(null, jsonb_build_object('fecha','2099-01-11','h_ent','08:00','h_sal','16:00','finca',f1), lin);
    reset role; res := res || to_jsonb('S07 supervisor crea su propio parte: OK'::text);
  exception when others then res := res || to_jsonb('S07 supervisor crea su propio parte: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_det set obs='cambio en líneas propias', h_fin='13:00' where id_parte=new_sup; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('S08 supervisor cambia líneas de SU parte: FALLO, se permitió (filas='||n||')');
  exception when others then res := res || to_jsonb('S08 supervisor cambia líneas de su parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set h_sal='17:00' where id_parte=new_sup;
    reset role; res := res || to_jsonb('S09 supervisor cambia cabecera de SU parte: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('S09 supervisor cambia cabecera de su parte: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update partes_cab set estado='Aprobado' where id_parte=new_sup; get diagnostics n = row_count;
    select 'revisa='||coalesce(supervisor_revisa,'null') into x from partes_cab where id_parte=new_sup;
    reset role; res := res || to_jsonb('S10 supervisor se autoaprueba su parte: FALLO, se permitió (filas='||n||' '||x||')');
  exception when others then res := res || to_jsonb('S10 supervisor se autoaprueba: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    insert into partes_cab(operario, fecha, h_ent, h_sal, finca, estado) values ('T001','2099-01-12','08:00','16:00',f1,'Aprobado') returning id_parte into tmp;
    select 'estado='||estado||' revisa='||coalesce(supervisor_revisa,'null') into x from partes_cab where id_parte=tmp;
    reset role; res := res || to_jsonb('S11 supervisor crea su parte ya aprobado: FALLO, se permitió ('||x||')');
  exception when others then res := res || to_jsonb('S11 supervisor crea su parte ya aprobado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    insert into fincas(cod_fin, finca) values ('ZZTEST','Finca prueba');
    update fincas set activo=false where cod_fin='ZZTEST';
    select 'activo='||activo||' fecha_baja='||(fecha_baja is not null)||' baja_por='||coalesce(baja_por,'null') into x from fincas where cod_fin='ZZTEST';
    delete from fincas where cod_fin='ZZTEST'; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('S12 supervisor catálogo crear+baja: '||x||' | borrar (esperado 0)='||n);
  exception when others then res := res || to_jsonb('S12 supervisor catálogo: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, jsonb_build_object('fecha','2099-01-13','h_ent','08:00','h_sal','16:00','finca','ZZTEST'), '[]');
    reset role; res := res || to_jsonb('O14 usar finca dada de baja en parte nuevo: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('O14 usar finca dada de baja: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    update operarios set rol_app='ADMIN' where cod_ope='T001'; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('S13 supervisor se sube a ADMIN (esperado 0): '||n);
  exception when others then res := res || to_jsonb('S13 supervisor se sube a ADMIN: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== ADMIN T000 =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select count(*) into n from operarios; x := 'operarios='||n;
    select count(*) into n from partes_cab; x := x||' partes='||n;
    select count(*) into n from auditoria where registro='ZZTEST'; x := x||' auditoria_ZZTEST='||n;
    select string_agg(accion||'/'||coalesce(cod_ope,'?'), ',') into x2 from auditoria where registro='ZZTEST';
    reset role; res := res || to_jsonb('D01 admin lecturas: '||x||' ['||coalesce(x2,'')||']');
  exception when others then res := res || to_jsonb('D01 admin lecturas: ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update operarios set activo=false where rol_app='ADMIN';
    reset role; res := res || to_jsonb('D02 desactivar todos los ADMIN: FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('D02 desactivar todos los ADMIN: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update partes_cab set obs='corregido por admin' where id_parte=new_op; get diagnostics n = row_count;
    x := 'edita aprobado='||n;
    tmp := guardar_parte(null, jsonb_build_object('operario','T003','fecha','2099-01-14','h_ent','08:00','h_sal','16:00','finca',f1), lin);
    x := x||' crea parte de T003=OK';
    delete from partes_cab where id_parte=tmp; get diagnostics n = row_count;
    x := x||' borra parte='||n;
    delete from fincas where cod_fin='ZZTEST'; get diagnostics n = row_count;
    x := x||' borra finca='||n;
    select count(*) into n from auditoria where registro='ZZTEST' and accion='BORRADO'; x := x||' auditoria_borrado='||n;
    select string_agg(k, ',') into x2 from jsonb_object_keys(panel_resumen()) k;
    reset role; res := res || to_jsonb('D03 admin: '||x||' panel=['||x2||']');
  exception when others then res := res || to_jsonb('D03 admin: ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
