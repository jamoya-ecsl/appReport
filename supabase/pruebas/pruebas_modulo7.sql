-- =====================================================================
-- Pruebas del módulo 7 (migración 015: archivo de tareas y vueltas). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo, incluido el archivado de prueba (solo puede saltar la numeración de num_parte).
-- Usa partes del año 2000 para no tocar partes reales. Código R (15 casos, R00 a R14).
--
-- Partes de prueba (parcela p1 + tarea t1, campaña desde el 1 de septiembre):
--   A  T003  30/08/2000  fin No   (campaña 1999/00) + motivos personales + tarea sin parcela
--   B  T003  01/09/2000  fin No   (campaña 2000/01)
--   C  T001  02/09/2000  fin No   (mismo día que D, otro operario)
--   D  T003  02/09/2000  fin Sí   → cierra la vuelta 1 de 2000/01 (B, C y D)
--   E  T003  03/09/2000  fin No   → empieza la vuelta 2
--   F  T003  05/09/2000  fin Sí   RECHAZADO: no cuenta en las vueltas y al archivar se borra sin pasar al archivo
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_sup text := json_build_object('sub','788e6168-2bf6-4320-9a01-701e8d942541','email','oficinas@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  f1 text; p1 text; v1 text; t1 text; n int; x text; j jsonb;
  idA uuid; idB uuid; idC uuid; idD uuid; idE uuid; idF uuid; idG uuid;
  nums text[]; numF text;
  antes text;
  cab jsonb := jsonb_build_object('h_ent','07:00','h_sal','15:00','t_alm','30 minutes','t_com','0 minutes');
  desp jsonb; mp jsonb; sinp jsonb;
begin
  select f.cod_fin into f1 from fincas f
  where f.activo and exists (select 1 from parcelas p where p.finca = f.cod_fin and p.activo) order by f.cod_fin limit 1;
  select cod_par into p1 from parcelas where finca = f1 and activo order by cod_par limit 1;
  select id_mat into v1 from vehiculos where activo order by id_mat limit 1;
  select cod_tar into t1 from tareas where activo and tipo = 'POR HORAS' order by cod_tar limit 1;
  desp := jsonb_build_object('tarea','TD001','finca',f1,'vehiculo',v1,'h_ini','07:00','h_fin','07:30');
  mp   := jsonb_build_object('tarea','TP001','h_ini','09:00','h_fin','09:30');
  sinp := jsonb_build_object('tarea',t1,'finca',f1,'h_ini','09:30','h_fin','10:00');

  -- Campaña desde el 1 de septiembre (sin sesión, como el SQL Editor)
  perform set_config('request.jwt.claims','',true);
  update configuracion set valor = '09-01' where clave = 'cfc_inicio';

  -- Preparación: partes A–E aprobados
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    idA := guardar_parte(null, cab || '{"fecha":"2000-08-30"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',false), mp, sinp));
    idB := guardar_parte(null, cab || '{"fecha":"2000-09-01"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',false)));
    idD := guardar_parte(null, cab || '{"fecha":"2000-09-02"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',true)));
    idE := guardar_parte(null, cab || '{"fecha":"2000-09-03"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',false)));
    idF := guardar_parte(null, cab || '{"fecha":"2000-09-05"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',true)));
    perform cerrar_parte(idA); perform cerrar_parte(idB); perform cerrar_parte(idD); perform cerrar_parte(idE);
    perform cerrar_parte(idF);
    perform set_config('request.jwt.claims',c_sup,true);
    idC := guardar_parte(null, cab || '{"fecha":"2000-09-02"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',false)));
    perform cerrar_parte(idC);
    perform revisar_parte(idA, 'Aprobado'); perform revisar_parte(idB, 'Aprobado');
    perform revisar_parte(idD, 'Aprobado'); perform revisar_parte(idE, 'Aprobado');
    perform revisar_parte(idF, 'Rechazado', 'Prueba: parte rechazado');
    perform set_config('request.jwt.claims',c_adm,true);
    perform revisar_parte(idC, 'Aprobado');
    select array_agg(num_parte::text) into nums from partes_cab where id_parte in (idA, idB, idC, idD, idE);
    select num_parte::text into numF from partes_cab where id_parte = idF;
    select string_agg(estado::text||'='||n_, ',' order by estado::text) into x
    from (select estado, count(*) n_ from partes_cab where id_parte in (idA, idB, idC, idD, idE, idF) group by estado) s;
    reset role; res := res || to_jsonb('R00 preparación: 5 aprobados y 1 rechazado (esperado Aprobado=5,Rechazado=1): '||x);
  exception when others then res := res || to_jsonb('R00 preparación (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    x := '31/08='||campana_de('2000-08-31')||' 01/09='||campana_de('2000-09-01')||' 15/01/2027='||campana_de('2027-01-15');
    reset role; res := res || to_jsonb('R01 campaña de una fecha (esperado 31/08=1999/00 01/09=2000/01 15/01/2027=2026/27): '||x);
  exception when others then res := res || to_jsonb('R01 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select string_agg(campana||'#'||num_vuelta||' '||estado||' fin='||coalesce(fecha_fin::text,'-')||' por='||coalesce(operario_fin,'-')
                      ||' h='||horas||' reg='||registros, ' | ' order by campana, num_vuelta)
      into antes
    from vueltas where parcela = p1 and tarea = t1 and campana in ('1999/00', '2000/01');
    reset role; res := res || to_jsonb('R02 vueltas antes de archivar (esperado 1999/00#1 Abierta fin=- por=- h=1.50 reg=1 | 2000/01#1 Cerrada fin=2000-09-02 por=T003 h=4.50 reg=3 | 2000/01#2 Abierta fin=- por=- h=1.50 reg=1): '||coalesce(antes,'(vacío)'));
  exception when others then res := res || to_jsonb('R02 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    select count(*) into n from vueltas;
    x := 'vueltas='||n;
    select count(*) into n from tareas_resumen; x := x||' tareas_resumen='||n;
    select count(*) into n from horas_trabajador; x := x||' horas_trabajador='||n;
    reset role; res := res || to_jsonb('R03 el operario no ve las vistas (esperado vueltas=0 tareas_resumen=0 horas_trabajador=0): '||x);
  exception when others then res := res || to_jsonb('R03 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    perform archivar_partes('2000-09-30');
    reset role; res := res || to_jsonb('R04 el supervisor archiva (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R04 supervisor archiva: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2000-09-04"}', jsonb_build_array(desp));
    perform set_config('request.jwt.claims',c_adm,true);
    perform archivar_partes('2000-09-30');
    reset role; res := res || to_jsonb('R05 archivar con un parte Pendiente en el rango (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R05 parte sin aprobar en el rango: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform archivar_partes(current_date);
    reset role; res := res || to_jsonb('R06 archivar hasta hoy (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R06 archivar hasta hoy: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    j := archivar_partes('2000-09-30');
    select count(*) into n from partes_cab where fecha <= '2000-09-30';
    reset role; res := res || to_jsonb('R07 admin archiva hasta el 30/09/2000 (esperado partes=5 lineas=12 filas=6 rechazados=1 quedan=0): '
      ||'partes='||(j->>'partes')||' lineas='||(j->>'lineas')||' filas='||(j->>'filas')
      ||' rechazados='||(j->>'rechazados')||' quedan='||n);
  exception when others then res := res || to_jsonb('R07 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select 'filas='||count(*)||' fin='||count(*) filter (where fin_vuelta)
         ||' sin_parcela='||count(*) filter (where parcela is null)
         ||' campañas='||string_agg(distinct campana, ',')
         ||' con_nombre='||bool_and(nom_tarea <> '')
         ||' horas='||sum(horas)
      into x
    from tareas_realizadas where fec_tarea between '2000-08-01' and '2000-09-30';
    reset role; res := res || to_jsonb('R08 contenido del archivo (esperado filas=6 fin=1 sin_parcela=1 campañas=1999/00,2000/01 con_nombre=true horas=8.00): '||x);
  exception when others then res := res || to_jsonb('R08 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_sup,true); set local role authenticated;
    select string_agg(campana||'#'||num_vuelta||' '||estado||' fin='||coalesce(fecha_fin::text,'-')||' por='||coalesce(operario_fin,'-')
                      ||' h='||horas||' reg='||registros, ' | ' order by campana, num_vuelta)
      into x
    from vueltas where parcela = p1 and tarea = t1 and campana in ('1999/00', '2000/01');
    reset role; res := res || to_jsonb('R09 las vueltas no cambian al archivar (esperado igual que R02): '||(x is not distinct from antes)||' '||coalesce(x,'(vacío)'));
  exception when others then res := res || to_jsonb('R09 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    select count(*) into n from auditoria where tabla = 'partes_cab' and accion = 'BORRADO' and registro = any (nums);
    x := 'copias_por_parte='||n;
    select count(*) into n from auditoria where tabla = 'partes_cab' and registro = 'ARCHIVO hasta 2000-09-30' and fecha = now();
    x := x||' anotacion_archivo='||n;
    select x||' copia_rechazado='||count(*)||' lineas_rechazado='||coalesce(max(jsonb_array_length(cambios->'lineas')), -1) into x
    from auditoria where tabla = 'partes_cab' and accion = 'BORRADO' and registro = numF;
    reset role; res := res || to_jsonb('R10 auditoría del archivado (esperado copias_por_parte=0 anotacion_archivo=1 copia_rechazado=1 lineas_rechazado=2): '||x);
  exception when others then res := res || to_jsonb('R10 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, cab || '{"fecha":"2000-09-15"}', jsonb_build_array(desp));
    reset role; res := res || to_jsonb('R11 crear un parte en una fecha archivada (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R11 parte en fecha archivada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    idG := guardar_parte(null, cab || '{"fecha":"2000-10-01"}', jsonb_build_array(desp,
      jsonb_build_object('tarea',t1,'finca',f1,'parcela',p1,'h_ini','07:30','h_fin','09:00','fin_vuelta',true)));
    perform cerrar_parte(idG);
    perform set_config('request.jwt.claims',c_sup,true);
    perform revisar_parte(idG, 'Aprobado');
    select string_agg(estado||' fin='||coalesce(fecha_fin::text,'-')||' h='||horas||' reg='||registros||' sin_archivar='||incluye_sin_archivar, ' | ')
      into x
    from vueltas where parcela = p1 and tarea = t1 and campana = '2000/01' and num_vuelta = 2;
    reset role; res := res || to_jsonb('R12 la vuelta 2 se cierra con un parte nuevo aún sin archivar (esperado Cerrada fin=2000-10-01 h=3.00 reg=2 sin_archivar=true): '||coalesce(x,'(vacío)'));
  exception when others then res := res || to_jsonb('R12 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform archivar_partes('2000-09-20');
    reset role; res := res || to_jsonb('R13 archivar otra vez una fecha ya archivada (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R13 fecha ya archivada: bloqueado '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    insert into tareas_realizadas (id_archivo, campana, operario, fec_tarea, tarea, nom_tarea, horas, num_parte)
    select id, '2000/01', 'T003', '2000-09-10', t1, 'x', 1, 0 from archivos_partes limit 1;
    reset role; res := res || to_jsonb('R14 el admin escribe en el archivo directamente (esperado bloqueado): FALLO, se permitió'::text);
  exception when others then res := res || to_jsonb('R14 escritura directa en el archivo: bloqueado '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
