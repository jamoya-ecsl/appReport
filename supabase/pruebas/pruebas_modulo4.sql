-- =====================================================================
-- Pruebas del módulo 4 (migración 012: valores iniciales del parte). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (incluidos los cambios de configuración; solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. Códigos: V = lectura de valores, G = guardar_parte, C = configuración.
-- Formato de los resultados: ent/sal como HH:MM:SS, pausas como intervalo (00:30:00), h_ext con 2 decimales.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  n int; x text; j jsonb;
  id1 uuid; id2 uuid; id3 uuid; id4 uuid;
begin
  -- ===== LECTURA DE LOS VALORES INICIALES =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    j := valores_iniciales_parte();
    x := 'operario='||j::text;
    perform set_config('request.jwt.claims',c_sup,true);
    x := x||' supervisor='||valores_iniciales_parte()::text;
    reset role; res := res || to_jsonb('V01 operario y supervisor leen los valores iniciales (esperado {"h_ent": "07:30", "h_sal": "18:00", "t_alm_min": 30, "t_com_min": 90} los dos): '||x);
  exception when others then res := res || to_jsonb('V01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from configuracion;
    reset role; res := res || to_jsonb('V02 operario lee la tabla configuracion (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('V02 operario lee la tabla: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    x := 'anon='||has_function_privilege('anon', 'public.valores_iniciales_parte()', 'execute')
       ||' authenticated='||has_function_privilege('authenticated', 'public.valores_iniciales_parte()', 'execute');
    res := res || to_jsonb('V03 permisos de la función (esperado anon=false authenticated=true): '||x);
  exception when others then res := res || to_jsonb('V03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select string_agg(clave||'='||valor, ' ' order by clave) into x from configuracion;
    reset role; res := res || to_jsonb('V04 admin lee la configuración (esperado cfh_ent=07:30 cfh_sal=18:00 cft_alm=30 cft_com=90 th_jornada=8.5): '||x);
  exception when others then res := res || to_jsonb('V04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== GUARDAR_PARTE CON CAMPOS VACÍOS =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, '{"fecha":"2099-06-01"}', '[]');
    select 'ent='||h_ent||' sal='||h_sal||' alm='||t_alm||' com='||t_com||' tot='||tot_horas||' ext='||h_ext
      into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('G01 operario crea sin horas ni pausas (esperado ent=07:30:00 sal=18:00:00 alm=00:30:00 com=01:30:00 tot=8.50 ext=0.00): '||x);
  exception when others then res := res || to_jsonb('G01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id2 := guardar_parte(null, '{"fecha":"2099-06-02","h_ent":"","h_sal":"","t_alm":"","t_com":""}', '[]');
    select 'ent='||h_ent||' sal='||h_sal||' alm='||t_alm||' com='||t_com into x from partes_cab where id_parte = id2;
    reset role; res := res || to_jsonb('G02 operario crea con los campos en blanco (esperado ent=07:30:00 sal=18:00:00 alm=00:30:00 com=01:30:00): '||x);
  exception when others then res := res || to_jsonb('G02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id3 := guardar_parte(null, '{"fecha":"2099-06-03","h_ent":"08:00","h_sal":"17:00","t_alm":"0 minutes"}', '[]');
    select 'ent='||h_ent||' sal='||h_sal||' alm='||t_alm||' com='||t_com||' ext='||h_ext into x from partes_cab where id_parte = id3;
    reset role; res := res || to_jsonb('G03 operario pone sus horas y almuerzo 0 explícito (esperado ent=08:00:00 sal=17:00:00 alm=00:00:00 com=01:30:00 ext=0.00): '||x);
  exception when others then res := res || to_jsonb('G03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id1, '{"fecha":"2099-06-01","h_sal":"19:00"}', '[]');
    select 'paso1 sal='||h_sal||' ext='||h_ext into x from partes_cab where id_parte = id1;
    perform guardar_parte(id1, '{"fecha":"2099-06-01","h_sal":""}', '[]');
    select x||' paso2 sal='||h_sal||' ext='||h_ext into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb('G04 operario edita: salida 19:00 y luego la borra (esperado paso1 sal=19:00:00 ext=1.00 paso2 sal=18:00:00 ext=0.00): '||x);
  exception when others then res := res || to_jsonb('G04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(id3, '{"fecha":"2099-06-03","h_ent":"08:00","h_sal":"17:00","t_com":"0 minutes"}', '[]');
    select 'alm='||t_alm||' com='||t_com into x from partes_cab where id_parte = id3;
    reset role; res := res || to_jsonb('G05 operario edita sin enviar almuerzo y comida 0 (esperado alm=00:30:00 com=00:00:00): '||x);
  exception when others then res := res || to_jsonb('G05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, '{"fecha":"2099-06-04","t_alm":"20 minutes"}', '[]');
    reset role; res := res || to_jsonb('G06 almuerzo de 20 min (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('G06 almuerzo de 20 min: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== CAMBIOS EN LA CONFIGURACIÓN =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    update configuracion set valor = '06:00' where clave = 'cfh_ent'; get diagnostics n = row_count;
    reset role; res := res || to_jsonb('C01 operario cambia cfh_ent (esperado 0 filas): '||n);
  exception when others then res := res || to_jsonb('C01 operario cambia cfh_ent: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '07:10' where clave = 'cfh_ent';
    reset role; res := res || to_jsonb('C02 cfh_ent = 07:10, no es cuarto de hora (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C02 cfh_ent = 07:10: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '7:30' where clave = 'cfh_ent';
    reset role; res := res || to_jsonb('C03 cfh_ent = 7:30, formato incorrecto (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C03 cfh_ent = 7:30: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '20' where clave = 'cft_alm';
    reset role; res := res || to_jsonb('C04 cft_alm = 20 (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C04 cft_alm = 20: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '07:00' where clave = 'cfh_sal';
    reset role; res := res || to_jsonb('C05 salida propuesta antes que la entrada (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C05 salida antes que entrada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    -- Una sola sentencia cambia dos claves: salida 11:00 (jornada de 3,5 h) y comida 240 min.
    update configuracion set valor = case clave when 'cfh_sal' then '11:00' else '240' end
    where clave in ('cfh_sal', 'cft_com');
    reset role; res := res || to_jsonb('C06 pausas de 4,5 h en una jornada de 3,5 h (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('C06 pausas mayores que la jornada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    update configuracion set valor = '08:00' where clave = 'cfh_ent';
    perform set_config('request.jwt.claims',c_op,true);
    id4 := guardar_parte(null, '{"fecha":"2099-06-05"}', '[]');
    select 'nuevo ent='||h_ent into x from partes_cab where id_parte = id4;
    select x||' anterior ent='||h_ent into x from partes_cab where id_parte = id2;
    reset role; res := res || to_jsonb('C07 admin pone la entrada a 08:00; parte nuevo y uno anterior (esperado nuevo ent=08:00:00 anterior ent=07:30:00): '||x);
  exception when others then res := res || to_jsonb('C07 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select count(*) into n from auditoria
    where tabla = 'configuracion' and accion = 'MODIFICACION' and fecha = now() and usuario_email = 'soporte@escribanosl.es';
    select n||' modificado_por='||modificado_por into x from configuracion where clave = 'cfh_ent';
    reset role; res := res || to_jsonb('C08 auditoría de los cambios del admin en esta prueba (esperado 1 modificado_por=T000): '||x);
  exception when others then res := res || to_jsonb('C08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
