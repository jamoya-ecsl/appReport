-- =====================================================================
-- 017 · Correcciones del análisis del 10/11/2026 (docs/PLAN_MODULOS_9_Y_10.md, paso 1).
-- PROPUESTA pendiente de revisión: no aplicar hasta que se autorice.
-- Se puede aplicar con el conector o desde el SQL Editor (solo ADD CONSTRAINT).
-- Precondición: 016 aplicada.
--
-- Fallo corregido: almuerzo y comida solo se comprobaban en múltiplos de 15 minutos
-- (partes_cab_cuartos_hora, 009). Un valor negativo (−60 min) es múltiplo de 15 y se aceptaba:
-- el total de la jornada subía y con él las horas extra automáticas.
-- Ahora:
--  * almuerzo y comida son 0 o más;
--  * almuerzo + comida no superan la duración de la jornada (tot_horas no queda negativo).
-- Comprobado el 10/11/2026: ningún parte existente incumple estas reglas.
-- =====================================================================

do $$
begin
  if to_regclass('public.partes_pdf') is null then
    raise exception 'La 017 exige la 016 aplicada';
  end if;
end $$;

alter table public.partes_cab
  add constraint partes_cab_pausas_ok check (
        t_alm >= interval '0'
    and t_com >= interval '0'
    and t_alm + t_com <= h_sal - h_ent);
