-- 004b · Enlaza por id las cuentas de login que ya existían antes de la 004.
-- Solo rellena operarios.user_id donde está vacío y hay una cuenta confirmada con el mismo email.
-- No es imprescindible (mientras user_id esté vacío se identifica por email), pero deja el enlace firme.
-- Seguro de repetir: si ya está enlazado, no hace nada.
update public.operarios o set user_id = u.id
from auth.users u
where lower(u.email) = o.email
  and u.email_confirmed_at is not null
  and o.user_id is null
  and not exists (select 1 from public.operarios x where x.user_id = u.id);
