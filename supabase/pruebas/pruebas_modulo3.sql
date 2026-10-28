-- =====================================================================
-- Pruebas del módulo 3 (migración 011). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (incluido el cambio de th_jornada; solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Códigos: C = configuración, H = horas extra, T = ht_tareas.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; v1 text; t1 text; n int; x text;
  id1 uuid; id2 uuid; id3 uuid; id4 uuid; id5 uuid;
  -- Jornadas: 07:00–15:00 con 30 min de almuerzo = 7,5 h; 07:00–17:00 = 9,5 h
  c75 jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes');
  c95 jsonb := jsonb_build_object('h_ent','07:00','h_sal','17:00','t_alm','30 minutes');
begin
  select cod_fin into f1 from fincas where activo order by cod_fin limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;

  -- ===== CONFIGURACIÓN =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from configuracion;
    reset role; res := res || to_jsonb('C01 operario lee la configuración (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('C01 operario lee: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select count(*) into n from configuracion;
    reset role; res := res || to_jsonb('C02 supervisor lee la configuración (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('C02 supervisor lee: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update configuracion set valor = '6' where clave = 'th_jornada'; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('C03 operario cambia th_jornada (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('C03 operario cambia th_jornada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select valor into x from configuracion where clave = 'th_jornada';
    reset role; res := res || to_jsonb('C04 admin lee th_jornada (esperado 8): '||coalesce(x,'(sin fila)'));
  exception when others then res := res || to_jsonb('C04 (esperado 8): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '7.3' where clave = 'th_jornada';
    reset role; res := res || to_jsonb('C05 th_jornada = 7.3 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C05 th_jornada = 7.3: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = 'ocho' where clave = 'th_jornada';
    reset role; res := res || to_jsonb('C06 th_jornada no numérico (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C06 th_jornada no numérico: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    insert into configuracion (clave, valor) values ('otra', '1');
    reset role; res := res || to_jsonb('C07 admin crea una clave nueva (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C07 crear clave: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    delete from configuracion where clave = 'th_jornada'; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('C08 admin borra th_jornada (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('C08 borrar clave: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== HORAS EXTRA =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, c95 || '{"fecha":"2099-05-01","h_ext":5,"h_ext_manual":true}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H01 operario, 9,5 h, envía h_ext=5 a mano (esperado 1.5 manual=false): '||x);
  exception when others then res := res || to_jsonb('H01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id2 := guardar_parte(null, c75 || '{"fecha":"2099-05-02"}', '[]');
    select 'h_ext='||h_ext into x from partes_cab where id_parte = id2;
    reset role; res := res || to_jsonb('H02 operario, 7,5 h (esperado 0): '||x);
  exception when others then res := res || to_jsonb('H02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01","h_sal":"18:00"}', '[]');
    select 'h_ext='||h_ext into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H03 operario alarga la salida a 18:00 (esperado 2.5): '||x);
  exception when others then res := res || to_jsonb('H03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01","h_sal":"18:00","h_ext":2,"h_ext_manual":true}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H04 admin corrige h_ext a 2 (esperado 2 manual=true): '||x);
  exception when others then res := res || to_jsonb('H04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01","h_sal":"18:00","h_ext":0,"obs":"solo cambio obs"}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H05 operario cambia solo observaciones (esperado se mantiene 2 manual=true): '||x);
  exception when others then res := res || to_jsonb('H05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01"}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H06 operario cambia la salida a 17:00 (esperado recalcula 1.5 manual=false): '||x);
  exception when others then res := res || to_jsonb('H06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01","h_sal":"18:00","h_ext":3,"h_ext_manual":true}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H07 admin cambia salida y fija h_ext=3 a la vez (esperado 3 manual=true): '||x);
  exception when others then res := res || to_jsonb('H07 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id1, c95 || '{"fecha":"2099-05-01","h_sal":"17:30","h_ext":3,"h_ext_manual":true}', '[]');
    select 'h_ext='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('H08 admin cambia la salida sin tocar h_ext (esperado recalcula 2 manual=false): '||x);
  exception when others then res := res || to_jsonb('H08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id2, c75 || '{"fecha":"2099-05-02","h_ext":0.3,"h_ext_manual":true}', '[]');
    reset role; res := res || to_jsonb('H09 admin pone h_ext = 0,3 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('H09 h_ext = 0,3: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- Partes de partida para H10: id3 cerrado (9,5 h → 1,5) e id4 con corrección manual
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id3 := guardar_parte(null, c95 || '{"fecha":"2099-05-03","mat_nave":true}', '[]');
    id4 := guardar_parte(null, c95 || '{"fecha":"2099-05-04"}', '[]');
    perform set_config('request.jwt.claims',c_sup,true);
    perform cerrar_parte(id3);
    perform set_config('request.jwt.claims',c_adm,true);
    perform guardar_parte(id4, c95 || '{"fecha":"2099-05-04","h_ext":1,"h_ext_manual":true}', '[]');
    select 'id3='||estado||'/'||h_ext into x from partes_cab where id_parte = id3;
    select x||' id4='||h_ext||' manual='||h_ext_manual into x from partes_cab where id_parte = id4;
    reset role; res := res || to_jsonb('H09b supervisor cierra id3 sin cambiar h_ext; admin corrige id4 (esperado id3=Cerrado/1.5 id4=1 manual=true): '||x);
  exception when others then res := res || to_jsonb('H09b (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '7' where clave = 'th_jornada'; get diagnostics n = row_count;
    select 'filas='||n
        ||' id2(7,5h)='||(select h_ext from partes_cab where id_parte = id2)
        ||' id1(10h)='||(select h_ext from partes_cab where id_parte = id1)
        ||' id3(cerrado)='||(select h_ext from partes_cab where id_parte = id3)
        ||' id4(manual)='||(select h_ext from partes_cab where id_parte = id4)
        ||' modificado_por='||(select modificado_por from configuracion where clave = 'th_jornada')
      into x;
    reset role; res := res || to_jsonb('H10 admin cambia th_jornada a 7 (esperado filas=1 id2=0.5 id1=3 id3=1.5 id4=1 modificado_por=T000): '||x);
  exception when others then res := res || to_jsonb('H10 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select count(*) into n from auditoria where tabla = 'configuracion' and accion = 'MODIFICACION';
    x := 'admin='||n;
    perform set_config('request.jwt.claims',c_sup,true);
    select count(*) into n from auditoria where tabla = 'configuracion';
    x := x||' supervisor='||n;
    reset role; res := res || to_jsonb('H11 auditoría de configuración (esperado admin=1 supervisor=0): '||x);
  exception when others then res := res || to_jsonb('H11 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== ht_tareas =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id5 := guardar_parte(null, c75 || '{"fecha":"2099-05-05"}', jsonb_build_array(
      jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','07:30','h_fin','10:00'),
      jsonb_build_object('tarea','TP001','h_ini','10:00','h_fin','10:30'),
      jsonb_build_object('tarea',t1,'finca',f1,'h_ini','10:30','h_fin','12:00')));
    select 'operario='||c.ht_tareas into x from partes_cab c where c.id_parte = id5;
    perform set_config('request.jwt.claims',c_sup,true);
    select x||' supervisor='||c.ht_tareas into x from partes_cab c where c.id_parte = id5;
    reset role; res := res || to_jsonb('T01 ht_tareas sin MOTIVOS PERSONALES (esperado 4.5 para ambos): '||x);
  exception when others then res := res || to_jsonb('T01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
