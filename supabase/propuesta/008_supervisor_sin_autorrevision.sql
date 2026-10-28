-- =====================================================================
-- 008 · El supervisor no modifica partes ni revisa los suyos.
-- Cierra tres huecos detectados con supabase/pruebas/pruebas_por_rol.sql (28/10/2026):
--   S08  el supervisor podía cambiar o borrar las LÍNEAS de su propio parte en Pendiente;
--   S10  el supervisor podía aprobar o rechazar su propio parte;
--   S11  el supervisor podía crear su propio parte directamente como Aprobado.
--
-- Qué sigue pudiendo hacer el supervisor:
--   - crear su propio parte (siempre en Pendiente) con sus líneas, en una sola llamada a guardar_parte();
--   - aprobar o rechazar los partes de OTROS.
-- Sus partes los revisa un ADMIN.
--
-- No cambia nada para OPERARIO ni para ADMIN. Sin sesión (SQL Editor, service role) no aplica,
-- igual que los demás disparadores de reglas: app_rol() es null.
-- Solo crea funciones y disparadores; no modifica ni borra datos.
-- =====================================================================

-- 1) Partes: un supervisor no revisa sus propios partes (S10, S11).
create function public.tg_partes_cab_no_autorrevision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.app_rol() = 'SUPERVISOR' and new.operario = public.app_cod_ope() and (
       (tg_op = 'INSERT' and new.estado <> 'Pendiente')
    or (tg_op = 'UPDATE' and new.estado is distinct from old.estado)) then
    raise exception 'Un supervisor no puede aprobar ni rechazar sus propios partes; debe revisarlos un ADMIN';
  end if;
  return new;
end $$;

create trigger partes_cab_no_autorrevision
  before insert or update on public.partes_cab
  for each row execute function public.tg_partes_cab_no_autorrevision();

-- 2) Líneas: un supervisor no modifica el contenido de ningún parte (S08).
-- Única excepción: añadir líneas al parte que él mismo acaba de crear en la MISMA transacción
-- (es lo que hace guardar_parte al crear). Se reconoce porque tg_partes_cab_guardas pone
-- fch_creacion := now(), y now() es constante dentro de una transacción.
create function public.tg_partes_det_supervisor_solo_revision()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_creado timestamptz;
begin
  if public.app_rol() = 'SUPERVISOR' then
    if tg_op = 'INSERT' then
      select fch_creacion into v_creado from public.partes_cab where id_parte = new.id_parte;
      if v_creado = now() then
        return new;
      end if;
    end if;
    raise exception 'Un supervisor solo puede aprobar o rechazar el parte, no modificar su contenido';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger partes_det_supervisor_solo_revision
  before insert or update or delete on public.partes_det
  for each row execute function public.tg_partes_det_supervisor_solo_revision();
