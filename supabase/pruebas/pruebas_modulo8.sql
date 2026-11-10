-- =====================================================================
-- Pruebas del módulo 8 (migración 016: PDF del parte, a petición). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte). Código Q (15 casos).
--
-- El PDF lo dibuja la función del servidor generar-pdf, que no se ejecuta dentro de esta prueba:
-- aquí se comprueba lo que decide la base de datos (pdf_pedir) y se imita a la función llamando a
-- pdf_marcar() como lo hace ella.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; p1 text; v1 text; t1 text; n int; x text; j jsonb;
  id1 uuid; id2 uuid; id3 uuid; id4 uuid; num1 bigint;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  lin jsonb;
begin
  select f.cod_fin into f1 from fincas f
  where f.activo and exists (select 1 from parcelas p where p.finca = f.cod_fin and p.activo) order by f.cod_fin limit 1;
  select cod_par into p1 from parcelas where finca = f1 and activo order by cod_par limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  lin := jsonb_build_array(
    jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30'),
    jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','12:00','fin_vuelta',false));

  -- Parte de partida: creado y cerrado por el operario
  perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
  id1 := guardar_parte(null, cab || '{"fecha":"2099-07-01"}', lin);
  perform cerrar_parte(id1);
  reset role;
  select num_parte into num1 from partes_cab where id_parte = id1;

  -- ===== QUIÉN Y CUÁNDO =====
  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform pdf_pedir(id1);
    reset role; res := res || to_jsonb('Q01 PDF de un parte Cerrado (esperado bloqueado: solo Aprobados): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('Q01 PDF de un Cerrado: bloqueado '||sqlstate||' '||sqlerrm); end;

  perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
  perform revisar_parte(id1, 'Aprobado');
  reset role;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform pdf_pedir(id1);
    reset role; res := res || to_jsonb('Q02 el operario genera el PDF de su parte (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('Q02 operario genera PDF: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    j := pdf_pedir(id1);
    reset role;
    select 'nuevo='||(j->>'nuevo')||' version='||(j->>'version')||' ruta='||(j->>'ruta')
         ||' estado='||estado||' por='||solicitado_por||' tareas='||jsonb_array_length(datos->'lineas')
         ||' fin_vuelta='||(datos->'lineas'->1->>'fin_vuelta')||' aprobado_por='||(datos->>'supervisor_revisa')
         ||' datos_enviados='||(j ? 'datos')
      into x from partes_pdf where id = (j->>'id')::bigint;
    res := res || to_jsonb('Q03 supervisor pulsa Generar PDF (esperado nuevo=true version=1 ruta=partes/2099/'||num1
      ||'_v1.pdf estado=Generando por=T001 tareas=2 fin_vuelta=No aprobado_por=T001 datos_enviados=true): '||x);
  exception when others then res := res || to_jsonb('Q03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform pdf_pedir(id1);
    reset role; res := res || to_jsonb('Q04 pulsar otra vez mientras se genera (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('Q04 pulsar mientras se genera: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== LA FUNCIÓN DEL SERVIDOR (imitada) =====
  begin
    perform set_config('request.jwt.claims','',true); reset role;
    perform pdf_marcar((select id from partes_pdf where id_parte = id1 and version = 1), null);
    select estado||' generado='||(generado is not null) into x from partes_pdf where id_parte = id1 and version = 1;
    res := res || to_jsonb('Q05 la función lo marca como hecho (esperado Generado generado=true): '||x);
  exception when others then res := res || to_jsonb('Q05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    j := pdf_pedir(id1);
    reset role;
    select count(*) into n from partes_pdf where id_parte = id1;
    res := res || to_jsonb('Q06 pulsar otra vez sin cambios en el parte (esperado nuevo=false version=1 versiones=1 datos_enviados=false): '
      ||'nuevo='||(j->>'nuevo')||' version='||(j->>'version')||' versiones='||n||' datos_enviados='||(j ? 'datos'));
  exception when others then res := res || to_jsonb('Q06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== CORRECCIONES Y ERRORES =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01"}', lin);   -- guarda sin cambiar nada
    j := pdf_pedir(id1);
    x := 'sin_cambios nuevo='||(j->>'nuevo');
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01","obs":"corregido"}', lin);
    j := pdf_pedir(id1);
    reset role;
    select x||' | corregido nuevo='||(j->>'nuevo')||' version='||(j->>'version')||' '
         ||string_agg('v'||version||'='||estado||'/'||solicitado_por, ' ' order by version)
         ||' obs_v2='||max(datos->>'obs') filter (where version = 2)
      into x from partes_pdf where id_parte = id1;
    res := res || to_jsonb('Q07 admin corrige el Aprobado (esperado sin_cambios nuevo=false | corregido nuevo=true version=2 v1=Generado/T001 v2=Generando/T000 obs_v2=corregido): '||x);
  exception when others then res := res || to_jsonb('Q07 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims','',true); reset role;
    perform pdf_marcar((select id from partes_pdf where id_parte = id1 and version = 2), 'Fallo simulado');
    select 'estado='||estado||' error='||error into x from partes_pdf where id_parte = id1 and version = 2;
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    j := pdf_pedir(id1);
    reset role;
    select x||' | reintento nuevo='||(j->>'nuevo')||' version='||(j->>'version')||' estado='||estado||' intentos='||intentos
         ||' por='||solicitado_por||' versiones='||(select count(*) from partes_pdf where id_parte = id1)
      into x from partes_pdf where id_parte = id1 and version = 2;
    res := res || to_jsonb('Q08 falla y se vuelve a pulsar (esperado estado=Error error=Fallo simulado | reintento nuevo=true version=2 estado=Generando intentos=2 por=T001 versiones=2): '||x);
  exception when others then res := res || to_jsonb('Q08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id2 := guardar_parte(null, cab || '{"fecha":"2099-07-02"}', lin);
    perform cerrar_parte(id2);
    perform set_config('request.jwt.claims',c_sup,true);
    perform revisar_parte(id2, 'Rechazado', 'Prueba');
    perform pdf_pedir(id2);
    reset role; res := res || to_jsonb('Q09 PDF de un parte Rechazado (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('Q09 PDF de un Rechazado: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- ===== QUIÉN LO VE =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from partes_pdf where id_parte = id1;
    x := 'operario_titular='||n;
    perform set_config('request.jwt.claims',c_sup,true);
    select count(*) into n from partes_pdf where id_parte = id1;
    x := x||' supervisor='||n;
    reset role;
    begin
      perform set_config('request.jwt.claims','',true); set local role anon;
      select count(*) into n from partes_pdf;
      x := x||' anon='||n;
    exception when others then x := x||' anon=bloqueado '||sqlstate; end;
    reset role;
    begin
      perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
      update partes_pdf set estado = 'Generado' where id_parte = id1;
      x := x||' escribir=FALLO se permitió';
    exception when others then x := x||' escribir=bloqueado '||sqlstate; end;
    reset role;
    res := res || to_jsonb('Q10 lectura y escritura (esperado operario_titular=2 supervisor=2 anon=bloqueado 42501 escribir=bloqueado 42501): '||x);
  exception when others then res := res || to_jsonb('Q10 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== CARPETA CONFIGURABLE =====
  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    begin
      update configuracion set valor = '../otra' where clave = 'cfp_carpeta';
      x := 'carpeta ../otra: FALLO, se permitió';
    exception when others then x := 'carpeta ../otra: bloqueado '||sqlstate; end;
    update configuracion set valor = 'pdf/partes' where clave = 'cfp_carpeta';
    perform guardar_parte(id1, cab || '{"fecha":"2099-07-01","obs":"corregido otra vez"}', lin);
    j := pdf_pedir(id1);
    reset role;
    select x||' | ruta_v3='||(j->>'ruta')||' ruta_v1='||ruta into x from partes_pdf where id_parte = id1 and version = 1;
    res := res || to_jsonb('Q11 carpeta configurable (esperado carpeta ../otra: bloqueado 23514 | ruta_v3=pdf/partes/2099/'||num1
      ||'_v3.pdf ruta_v1=partes/2099/'||num1||'_v1.pdf): '||x);
  exception when others then res := res || to_jsonb('Q11 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== ARCHIVAR NO EXIGE EL PDF Y LOS CONSERVA =====
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id3 := guardar_parte(null, cab || '{"fecha":"2000-07-03"}', lin);
    id4 := guardar_parte(null, cab || '{"fecha":"2000-07-04"}', lin);
    perform cerrar_parte(id3); perform cerrar_parte(id4);
    perform set_config('request.jwt.claims',c_sup,true);
    perform revisar_parte(id3, 'Aprobado'); perform revisar_parte(id4, 'Aprobado');
    j := pdf_pedir(id3);                                  -- solo id3 tiene PDF
    reset role;
    perform pdf_marcar((j->>'id')::bigint, null);
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    j := archivar_partes('2000-07-31');
    reset role;
    select 'archivados='||(j->>'partes')
         ||' partes_quedan='||(select count(*) from partes_cab where id_parte in (id3, id4))
         ||' pdf_conservados='||count(*)||'/'||max(estado)
      into x from partes_pdf where id_parte in (id3, id4);
    res := res || to_jsonb('Q12 archivar con un parte sin PDF (esperado archivados=2 partes_quedan=0 pdf_conservados=1/Generado): '||x);
  exception when others then res := res || to_jsonb('Q12 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from partes_pdf where id_parte = id3;
    reset role;
    res := res || to_jsonb('Q13 el operario sigue viendo el PDF de su parte archivado (esperado 1): '||n);
  exception when others then res := res || to_jsonb('Q13 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- ===== PERMISOS Y STORAGE =====
  begin
    x := 'pedir_authenticated='||has_function_privilege('authenticated', 'public.pdf_pedir(uuid)', 'execute')
       ||' pedir_anon='||has_function_privilege('anon', 'public.pdf_pedir(uuid)', 'execute')
       ||' marcar_authenticated='||has_function_privilege('authenticated', 'public.pdf_marcar(bigint,text)', 'execute')
       ||' marcar_servidor='||has_function_privilege('service_role', 'public.pdf_marcar(bigint,text)', 'execute')
       ||' datos_authenticated='||has_function_privilege('authenticated', 'public.pdf_datos(uuid)', 'execute');
    res := res || to_jsonb('Q14 permisos (esperado pedir_authenticated=true pedir_anon=false marcar_authenticated=false marcar_servidor=true datos_authenticated=false): '||x);
  exception when others then res := res || to_jsonb('Q14 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    select 'publico='||public||' tipos='||array_to_string(allowed_mime_types, ',')||' limite_mb='||(file_size_limit / 1048576)
      into x from storage.buckets where id = 'partes-pdf';
    select x||' politica_lectura='||count(*) into x from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'partes_pdf_leer' and cmd = 'SELECT';
    select x||' politicas_escritura='||count(*) into x from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname like 'partes_pdf%' and cmd <> 'SELECT';
    res := res || to_jsonb('Q15 almacenamiento (esperado publico=false tipos=application/pdf limite_mb=5 politica_lectura=1 politicas_escritura=0): '||x);
  exception when others then res := res || to_jsonb('Q15 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
