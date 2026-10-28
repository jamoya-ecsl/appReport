// MODO SUPABASE — usa el esquema aplicado en Supabase (migraciones de supabase/propuesta/, 001 a 009).
// Solo usa la clave PÚBLICA: los permisos reales los aplican las políticas RLS y los disparadores.
// Login: email + contraseña o enlace mágico (Supabase Auth). El email debe existir en public.operarios y estar activo.

const intervalAMin = (v) => {
  if (!v) return 0;
  const [h, m] = String(v).split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
};
const hhmm = (t) => (t ? String(t).slice(0, 5) : '');

function traducir(error) {
  const c = error?.code;
  const e = new Error(error?.message || 'Error desconocido de Supabase');
  if (c === 'PGRST205' || c === '42P01') {
    e.message = 'No se encuentran las tablas de la app en este proyecto de Supabase.';
    e.hint = 'Comprueba que SUPABASE_URL apunta al proyecto correcto (baluwelboftnibtyjrer), donde el esquema ya está aplicado. Mientras tanto, usa el modo demo.';
  } else if (c === '23505') e.message = 'Ya existe un parte de este operario para esa fecha (un parte por día).';
  else if (c === '23514') {
    const m = String(error?.message || '');
    if (/cuartos_hora/.test(m)) e.message = 'Las horas y duraciones deben ir en intervalos de 15 minutos (:00, :15, :30, :45).';
    else if (/h_ext_ok/.test(m)) e.message = 'Las horas extra deben ser 0 o más, en múltiplos de 0,25 h.';
    else if (/rechazo_comentado/.test(m)) e.message = 'Para rechazar hay que escribir un comentario.';
    else if (/horas_ok/.test(m)) e.message = 'La hora de fin debe ser posterior a la de inicio.';
    else e.message = 'Datos no válidos: revisa las horas o, si rechazas, el comentario.';
  } else if (c === 'PGRST202') {
    e.message = 'Falta la función guardar_parte() en Supabase.';
    e.hint = 'Hay que aplicar las migraciones 007b y 009.';
  }
  else if (c === '42501') e.message = 'No tienes permiso para esta operación.';
  else if (c === 'PGRST116') e.message = 'Parte no encontrado o sin permiso.';
  else if (c === 'P0001') e.message = error.message; // mensajes de las reglas de la BD (ya en español)
  return e;
}
const ok = ({ data, error }) => { if (error) throw traducir(error); return data; };

function traducirAuth(error) {
  const m = String(error?.message || '');
  const e = new Error(m || 'No se pudo iniciar sesión.');
  if (/invalid login credentials/i.test(m)) e.message = 'Email o contraseña incorrectos.';
  else if (/email not confirmed/i.test(m)) {
    e.message = 'Este email aún no está confirmado.';
    e.hint = 'Al crear el usuario en Supabase marca "Auto Confirm User", o confírmalo desde Authentication → Users.';
  } else if (/rate limit|security purposes/i.test(m)) {
    e.message = 'Demasiados intentos o correos enviados. Espera unos minutos.';
    e.hint = 'El correo por defecto de Supabase tiene un límite por hora. Usa email + contraseña para las pruebas.';
  } else if (/not authorized|address not authorized/i.test(m)) {
    e.message = 'Supabase no puede enviar correo a esta dirección.';
    e.hint = 'Sin SMTP propio, Supabase solo envía a miembros del equipo del proyecto. Usa email + contraseña.';
  }
  return e;
}

// La cabecera ya no tiene finca (migración 009): las fincas del parte son las de sus líneas.
const normParte = (r) => {
  const lineas = Array.isArray(r.lineas) ? r.lineas : Array.isArray(r.partes_det) ? r.partes_det : [];
  return {
    ...r,
    h_ent: hhmm(r.h_ent), h_sal: hhmm(r.h_sal),
    t_alm_min: intervalAMin(r.t_alm), t_com_min: intervalAMin(r.t_com),
    n_lineas: lineas.length,
    fincas: [...new Set(lineas.map((l) => l.finca).filter(Boolean))],
  };
};
const normLinea = (l) => ({ ...l, h_ini: hhmm(l.h_ini), h_fin: hhmm(l.h_fin) });

export function createSupabaseApi(cfg) {
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey);

  async function getSession() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) return null;
    const email = session.user.email?.toLowerCase();
    // Ficha propia: enlazada por id de cuenta o, si aún no hay id, por email (mismo criterio que app_rol()).
    const me = ok(await sb.from('operarios').select('cod_ope, usuario, email, rol_app, activo')
      .or(`user_id.eq.${session.user.id},and(user_id.is.null,email.eq."${email}")`).maybeSingle());
    if (!me || !me.activo) {
      throw Object.assign(new Error(`El email ${email} no está dado de alta como operario activo.`), {
        hint: 'Un ADMIN debe añadirlo en la tabla operarios.', signedIn: true,
      });
    }
    return me;
  }

  return {
    mode: 'supabase',
    reason: '',
    getSession,

    async signInEmail(email) {
      const { error } = await sb.auth.signInWithOtp({ email: email.trim().toLowerCase(), options: { emailRedirectTo: location.origin } });
      if (error) throw traducirAuth(error);
    },
    async signInPassword(email, password) {
      const { error } = await sb.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
      if (error) throw traducirAuth(error);
      return getSession();
    },
    async signOut() { await sb.auth.signOut(); },

    async listCatalogos() {
      const [fincas, parcelas, tareas, vehiculos, aperos] = await Promise.all([
        sb.from('fincas').select('*').order('finca'),
        sb.from('parcelas').select('*').order('nom_parc'),
        sb.from('tareas').select('*').order('tareas'),
        sb.from('vehiculos').select('*').order('equipo'),
        sb.from('aperos').select('*').order('equipo'),
      ]);
      return { fincas: ok(fincas), parcelas: ok(parcelas), tareas: ok(tareas), vehiculos: ok(vehiculos), aperos: ok(aperos) };
    },

    // Solo código y nombre (función operarios_nombres): gestores reciben todos; el operario, el suyo.
    async listOperarios() { return ok(await sb.rpc('operarios_nombres')); },

    // RLS filtra por rol; aquí solo se aplican los filtros de pantalla.
    // Filtro por finca: partes con alguna tarea en esa finca (la cabecera ya no tiene finca).
    async listPartes(f = {}) {
      const select = f.finca ? '*, lineas:partes_det(finca), filtro:partes_det!inner(finca)' : '*, lineas:partes_det(finca)';
      let q = sb.from('partes_cab').select(select)
        .order('fecha', { ascending: false }).order('num_parte', { ascending: false });
      if (f.estado) q = q.eq('estado', f.estado);
      if (f.operario) q = q.eq('operario', f.operario);
      if (f.finca) q = q.eq('filtro.finca', f.finca);
      if (f.desde) q = q.gte('fecha', f.desde);
      if (f.hasta) q = q.lte('fecha', f.hasta);
      return ok(await q).map(normParte);
    },

    async getParte(id) {
      const r = ok(await sb.from('partes_cab').select('*, partes_det(*)').eq('id_parte', id).maybeSingle());
      if (!r) throw new Error('Parte no encontrado o sin permiso para verlo.');
      return { ...normParte(r), lineas: (r.partes_det || []).map(normLinea).sort((a, b) => a.h_ini.localeCompare(b.h_ini)) };
    },

    // Única vía de escritura de partes y líneas: guardar_parte() (migración 009).
    // La BD valida el parte completo (jornada, solapes, desplazamientos, 15 minutos).
    async saveParte({ id_parte, cab, lineas }) {
      return ok(await sb.rpc('guardar_parte', {
        p_id_parte: id_parte || null,
        p_cab: { ...cab, t_alm: `${Number(cab.t_alm_min) || 0} minutes`, t_com: `${Number(cab.t_com_min) || 0} minutes` },
        p_lineas: lineas,
      }));
    },

    // El trigger tg_partes_cab_guardas sella supervisor_revisa y fecha_revision.
    async setEstado(id, estado, comentario) {
      ok(await sb.from('partes_cab').update({ estado, comentario_supervisor: comentario?.trim() || null })
        .eq('id_parte', id).select('id_parte').single());
    },
  };
}
