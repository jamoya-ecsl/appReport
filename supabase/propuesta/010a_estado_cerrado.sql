-- =====================================================================
-- 010a · Añade el estado 'Cerrado' (entre Pendiente y Aprobado).
-- APLICADA 28/10/2026 desde el SQL Editor.
--
-- Va aparte de la 010 porque Postgres no deja usar un valor nuevo de un enum en la misma
-- transacción en que se añade. Ejecutar sola, y después la 010.
-- No cambia ningún dato: solo amplía la lista de estados posibles.
-- =====================================================================
alter type public.estado_parte add value if not exists 'Cerrado' after 'Pendiente';
