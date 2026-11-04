-- =====================================================================
-- Pruebas del módulo 5 (migración 013: supervisor y auditoría de partes). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Códigos: P = permisos del supervisor, A = auditoría (18 casos).
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; v1 text; t1 text; n int; x text;
  id1 uuid; id2 uuid; id3 uuid; id4 uuid;
  num1 bigint; num2 bigint; num3 bigint;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  lin jsonb;
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  lin := jsonb_build_array(
    jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
    jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','10:00'));

  -- Operario dado de baja para P02/P03 (sin sesión, como el SQL Editor)
  perform set_config('request.jwt.claims','',true);
  insert into operarios (cod_ope, usuario, email, rol_app, activo)
  values ('ZZ01', 'Operario de baja (prueba)', 'zz01.prueba@example.com', 'OPERARIO', false);

  -- ===== PERMISOS DEL SUPERVISOR =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id1 := guardar_parte(null, cab || '{"fecha":"2099-07-01","operario":"T003"}', lin);
    select num_parte, 'operario='||operario||' creado_por='||creado_por||' estado='||estado
           ||' lineas='||(select count(*) from partes_det d where d.id_parte = id1)
      into num1, x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('P01 supervisor crea parte para T003 (esperado operario=T003 creado_por=oficinas@escribanosl.es estado=Pendiente lineas=2): '||x);
  exception when others then res := res || to_jsonb('P01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-07-01","operario":"ZZ01"}', lin);
    reset role; res := res || to_jsonb('P02 supervisor crea parte para un operario de baja (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P02 supervisor, operario de baja: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-07-01","operario":"ZZ01"}', lin);
    reset role; res := res || to_jsonb('P03 admin crea parte para un operario de baja (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P03 admin, operario de baja: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2099-07-01","operario":"T001"}', lin);
    reset role; res := res || to_jsonb('P04 operario crea parte de otro (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P04 operario crea parte de otro: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01","obs":"revisado"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,
         'h_fin',case when d.h_ini = '07:30' then '11:00'::time else d.h_fin end)) from partes_det d where d.id_parte = id1));
    select 'obs='||coalesce(obs,'null')||' lineas='||(select count(*) from partes_det d where d.id_parte = id1)
           ||' horas_tareas='||(select sum(t_horas) from partes_det d where d.id_parte = id1)
      into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('P05 supervisor corrige el parte en Pendiente, alarga una tarea (esperado obs=revisado lineas=2 horas_tareas=4.00): '||x);
  exception when others then res := res || to_jsonb('P05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform cerrar_parte(id1);
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01","obs":"corregido cerrado"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id1));
    select 'estado='||estado||' obs='||coalesce(obs,'null')||' cerrado_por='||coalesce(cerrado_por,'null') into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('P06 supervisor cierra y corrige el parte Cerrado (esperado estado=Cerrado obs=corregido cerrado cerrado_por=T001): '||x);
  exception when others then res := res || to_jsonb('P06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01"}', '[]');
    reset role; res := res || to_jsonb('P07 supervisor quita todas las tareas de un parte Cerrado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P07 quitar todas las tareas de un Cerrado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform revisar_parte(id1, 'Aprobado');
    select estado||' revisa='||coalesce(supervisor_revisa,'null') into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('P08 supervisor aprueba el parte que él creó (esperado Aprobado revisa=T001): '||x);
  exception when others then res := res || to_jsonb('P08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01","obs":"tras aprobar"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id1));
    reset role; res := res || to_jsonb('P09 supervisor corrige un parte Aprobado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P09 supervisor corrige un Aprobado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id2 := guardar_parte(null, cab || '{"fecha":"2099-07-02","operario":"T003"}', lin);
    select num_parte into num2 from partes_cab where id_parte = id2;
    perform cerrar_parte(id2);
    perform revisar_parte(id2, 'Rechazado', 'Falta la parcela (prueba)');
    perform guardar_parte(id2, cab || '{"fecha":"2099-07-02","obs":"tras rechazar"}', lin);
    reset role; res := res || to_jsonb('P10 supervisor corrige un parte Rechazado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P10 supervisor corrige un Rechazado: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    -- P10 se deshizo entero: se rehace el Rechazado y lo corrige el admin.
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id2 := guardar_parte(null, cab || '{"fecha":"2099-07-02","operario":"T003"}', lin);
    select num_parte into num2 from partes_cab where id_parte = id2;
    perform cerrar_parte(id2);
    perform revisar_parte(id2, 'Rechazado', 'Falta la parcela (prueba)');
    perform set_config('request.jwt.claims',c_adm,true);
    perform guardar_parte(id2, cab || '{"fecha":"2099-07-02","obs":"corregido por admin"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id2));
    select 'estado='||estado||' obs='||coalesce(obs,'null') into x from partes_cab where id_parte = id2;
    reset role; res := res || to_jsonb('P10b admin corrige el Rechazado (esperado estado=Rechazado obs=corregido por admin): '||x);
  exception when others then res := res || to_jsonb('P10b (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id3 := guardar_parte(null, cab || '{"fecha":"2099-07-03","operario":"T003"}', lin);
    select num_parte into num3 from partes_cab where id_parte = id3;
    perform set_config('request.jwt.claims',c_op,true);
    perform guardar_parte(id3, cab || '{"fecha":"2099-07-03","obs":"lo completa el operario"}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id3));
    select 'obs='||coalesce(obs,'null') into x from partes_cab where id_parte = id3;
    reset role; res := res || to_jsonb('P11 el operario titular corrige el parte que le creó el supervisor (esperado obs=lo completa el operario): '||x);
  exception when others then res := res || to_jsonb('P11 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform guardar_parte(id3, cab || '{"fecha":"2099-07-03","h_ext":5,"h_ext_manual":true}',
      (select jsonb_agg(jsonb_build_object('id_linea',d.id_linea,'tarea',d.tarea,'finca',d.finca,'parcela',d.parcela,
         'vehiculo',d.vehiculo,'apero',d.apero,'h_ini',d.h_ini,'h_fin',d.h_fin)) from partes_det d where d.id_parte = id3));
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id3;
    reset role; res := res || to_jsonb('P12 supervisor intenta fijar horas extra a mano (esperado se ignora: h_ext=0.00 manual=false): '||x);
  exception when others then res := res || to_jsonb('P12 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    id4 := guardar_parte(null, cab || '{"fecha":"2099-07-04"}', lin);
    perform cerrar_parte(id4);
    perform revisar_parte(id4, 'Aprobado');
    reset role; res := res || to_jsonb('P13 supervisor aprueba un parte del que es titular (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('P13 supervisor titular se autoaprueba: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== AUDITORÍA =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select 'alta='||coalesce(max(cod_ope) filter (where accion = 'ALTA'), 'ninguna')
         ||' cierre='||coalesce(max(cod_ope) filter (where accion = 'MODIFICACION' and cambios->'estado'->>'despues' = 'Cerrado'), 'ninguno')
         ||' aprobacion='||coalesce(max(cod_ope) filter (where accion = 'MODIFICACION' and cambios->'estado'->>'despues' = 'Aprobado'), 'ninguna')
      into x
    from auditoria where tabla = 'partes_cab' and registro = num1::text;
    select x||' tareas: alta='||count(*) filter (where accion = 'ALTA')
            ||' modificacion='||count(*) filter (where accion = 'MODIFICACION')
            ||' borrado='||count(*) filter (where accion = 'BORRADO')
            ||' cambio_h_fin='||count(*) filter (where accion = 'MODIFICACION' and cambios ? 'h_fin' and cambios ? 'id_linea')
      into x
    from auditoria where tabla = 'partes_det' and registro = num1::text;
    reset role; res := res || to_jsonb('A01 historial del parte P01 (esperado alta=T001 cierre=T001 aprobacion=T001 tareas: alta=2 modificacion=1 borrado=0 cambio_h_fin=1): '||x);
  exception when others then res := res || to_jsonb('A01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from auditoria where registro = num1::text;
    x := 'operario='||n;
    perform set_config('request.jwt.claims',c_sup,true);
    select count(*) into n from auditoria where registro = num1::text;
    x := x||' supervisor_ve_filas='||(n > 0);
    reset role; res := res || to_jsonb('A02 quién lee la auditoría de partes (esperado operario=0 supervisor_ve_filas=true): '||x);
  exception when others then res := res || to_jsonb('A02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform borrar_parte(id3);
    select 'borrado_parte='||count(*)||' lineas_en_copia='||coalesce(max(jsonb_array_length(cambios->'lineas')), -1)
           ||' por='||coalesce(max(cod_ope), 'null')
      into x
    from auditoria where tabla = 'partes_cab' and registro = num3::text and accion = 'BORRADO';
    select x||' borrado_tareas_aparte='||count(*) into x
    from auditoria where tabla = 'partes_det' and registro = num3::text and accion = 'BORRADO';
    reset role; res := res || to_jsonb('A03 admin borra un parte (esperado borrado_parte=1 lineas_en_copia=2 por=T000 borrado_tareas_aparte=0): '||x);
  exception when others then res := res || to_jsonb('A03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims','',true); reset role;
    delete from partes_cab where id_parte = id2;
    select 'borrado_parte='||count(*)||' usuario='||coalesce(max(usuario_email), 'null')
      into x
    from auditoria where tabla = 'partes_cab' and registro = num2::text and accion = 'BORRADO';
    res := res || to_jsonb('A04 borrado desde el SQL Editor también queda anotado (esperado borrado_parte=1 usuario=sistema): '||x);
  exception when others then res := res || to_jsonb('A04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
