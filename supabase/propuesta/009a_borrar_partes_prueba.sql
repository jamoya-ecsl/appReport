-- =====================================================================
-- 009a · Borra los 3 partes de prueba (nº 1, 2 y 4) y sus 8 líneas.
-- Decisión del 28/10/2026: son datos de prueba y no cumplen las reglas del módulo 1
-- (sin desplazamiento, solapes, horas fuera de jornada, 11:05 no es múltiplo de 15 min).
--
-- Ejecutar en Dashboard → SQL Editor ANTES de la migración 009.
-- (El conector de Claude Code no ejecuta DELETE.)
-- Si los partes no son exactamente los esperados, no borra nada.
-- No afecta a catálogos, usuarios ni auditoría. partes_mant está vacía.
-- =====================================================================
begin;

do $$
begin
  if (select count(*) from public.partes_cab) <> 3
     or exists (select 1 from public.partes_cab where num_parte not in (1, 2, 4)) then
    raise exception 'Los partes no son los 3 de prueba esperados (nº 1, 2 y 4). Revisa antes de borrar.';
  end if;
  if exists (select 1 from public.partes_mant where id_parte is not null) then
    raise exception 'Hay partes de mantenimiento enlazados a partes de trabajo. Revisa antes de borrar.';
  end if;
end $$;

delete from public.partes_det
where id_parte in (select id_parte from public.partes_cab where num_parte in (1, 2, 4));

delete from public.partes_cab
where num_parte in (1, 2, 4);

commit;

-- Comprobación (debe devolver 0 y 0):
select (select count(*) from public.partes_cab) as partes, (select count(*) from public.partes_det) as lineas;
