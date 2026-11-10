-- =====================================================================
-- Pruebas de la migración 017 (pausas no negativas y no mayores que la jornada). Ejecutar DESPUÉS de aplicarla.
-- Dashboard → SQL Editor → pegar todo → Run.
-- Termina con un error "RESULTADOS(rollback) [...]" a propósito: muestra los resultados y
-- deshace todo (solo puede saltar la numeración de num_parte).
-- Cada línea indica lo esperado. P = pausas.
-- =====================================================================
do $$
declare
  c_op  text := json_build_object('sub','70115d53-c9a8-40eb-9935-c63d57f12171','email','campo@escribanosl.es','role','authenticated')::text;
  c_adm text := json_build_object('sub','e9ca9b2d-8204-4189-a59f-1202e341f8db','email','soporte@escribanosl.es','role','authenticated')::text;
  res jsonb := '[]';
  x text;
  id1 uuid;
begin
  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, '{"fecha":"2099-07-01","h_ent":"07:30","h_sal":"18:00","t_alm":"-60 minutes","t_com":"90 minutes"}', '[]');
    reset role; res := res || to_jsonb(text 'P01 operario con almuerzo de −60 min (esperado bloqueado 23514): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'P01 operario con almuerzo de −60 min (esperado bloqueado 23514): bloqueado '||sqlstate); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    perform guardar_parte(null, '{"fecha":"2099-07-02","h_ent":"07:30","h_sal":"18:00","t_alm":"30 minutes","t_com":"-15 minutes"}', '[]');
    reset role; res := res || to_jsonb(text 'P02 operario con comida de −15 min (esperado bloqueado 23514): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'P02 operario con comida de −15 min (esperado bloqueado 23514): bloqueado '||sqlstate); end;

  begin
    perform set_config('request.jwt.claims',c_adm,true); set local role authenticated;
    perform guardar_parte(null, '{"fecha":"2099-07-03","h_ent":"08:00","h_sal":"10:00","t_alm":"90 minutes","t_com":"60 minutes"}', '[]');
    reset role; res := res || to_jsonb(text 'P03 admin con pausas (2,5 h) mayores que la jornada (2 h) (esperado bloqueado 23514): GUARDADO');
  exception when others then reset role; res := res || to_jsonb(text 'P03 admin con pausas mayores que la jornada (esperado bloqueado 23514): bloqueado '||sqlstate); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, '{"fecha":"2099-07-04","h_ent":"08:00","h_sal":"10:00","t_alm":"0 minutes","t_com":"0 minutes"}', '[]');
    select 'tot='||tot_horas into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb(text 'P04 operario sin pausas (esperado OK tot=2.00): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'P04 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, '{"fecha":"2099-07-05","h_ent":"08:00","h_sal":"10:00","t_alm":"60 minutes","t_com":"60 minutes"}', '[]');
    select 'tot='||tot_horas into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb(text 'P05 operario con pausas iguales a la jornada (esperado OK tot=0.00): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'P05 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  begin
    perform set_config('request.jwt.claims',c_op,true); set local role authenticated;
    id1 := guardar_parte(null, '{"fecha":"2099-07-06"}', '[]');
    select 'tot='||tot_horas into x from partes_cab where id_parte = id1;
    reset role; res := res || to_jsonb(text 'P06 operario con los valores iniciales (esperado OK tot=8.50): '||x);
  exception when others then reset role; res := res || to_jsonb(text 'P06 (esperado OK): ERROR '||sqlstate||' '||sqlerrm); end;

  -- Error a propósito: deshace todo lo anterior y muestra los resultados.
  raise exception 'RESULTADOS(rollback) %', res::text;
end $$;
