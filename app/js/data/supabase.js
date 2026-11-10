// MODO SUPABASE — usa el esquema aplicado en Supabase (migraciones de supabase/propuesta/, 001 a 015).
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
    else if (/pausas_ok/.test(m)) e.message = 'El almuerzo y la comida no pueden ser negativos ni sumar más que la jornada.';
    else e.message = 'Datos no válidos: revisa las horas o, si rechazas, el comentario.';
  } else if (c === 'PGRST202') {
    e.message = 'Falta una función de la app en Supabase (guardar_cabecera, guardar_linea, borrar_linea, cerrar_parte, revisar_parte o borrar_parte).';
    e.hint = 'Hay que aplicar las migraciones hasta la 019.';
  }
  else if (c === '42501') e.message = 'No tienes permiso para esta operación.';
  else if (c === 'PGRST116') e.message = 'Parte no encontrado o sin permiso.';
  else if (c === 'P0001') e.message = error.message; // mensajes de las reglas de la BD (ya en español)
  return e;
}
const ok = ({ data, error }) => { if (error) throw traducir(error); return data; };

// Supabase devuelve como mucho 1.000 filas por consulta: sin esto, listados y CSV se cortaban sin avisar.
// consulta() crea la consulta de nuevo en cada página; su orden debe identificar cada fila (si no, al
// pasar de página se podrían repetir o saltar filas).
const PAGINA = 1000;
async function todas(consulta) {
  const filas = [];
  for (let desde = 0; ; desde += PAGINA) {
    const pagina = ok(await consulta().range(desde, desde + PAGINA - 1));
    filas.push(...pagina);
    if (pagina.length < PAGINA) return filas;
  }
}

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

// Jornada de la app → formato de guardar_parte() / guardar_cabecera(). Desde la 012, entrada, salida,
// almuerzo o comida vacíos se envían vacíos (null) y la BD pone el valor de la configuración; 0 minutos es 0.
const minutos = (v) => (v == null || v === '' ? null : `${Number(v)} minutes`);
const cabParaBd = (cab) => ({
  ...cab, h_ent: cab.h_ent || null, h_sal: cab.h_sal || null, t_alm: minutos(cab.t_alm_min), t_com: minutos(cab.t_com_min),
});

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
      // ht_tareas: horas de tareas sin MOTIVOS PERSONALES, calculadas por la BD al consultar (migración 011).
      const select = f.finca ? '*, ht_tareas, lineas:partes_det(finca), filtro:partes_det!inner(finca)' : '*, ht_tareas, lineas:partes_det(finca)';
      const consulta = () => {
        let q = sb.from('partes_cab').select(select)
          .order('fecha', { ascending: false }).order('num_parte', { ascending: false });
        if (f.estado) q = q.eq('estado', f.estado);
        if (f.operario) q = q.eq('operario', f.operario);
        if (f.finca) q = q.eq('filtro.finca', f.finca);
        if (f.desde) q = q.gte('fecha', f.desde);
        if (f.hasta) q = q.lte('fecha', f.hasta);
        return q;
      };
      return (await todas(consulta)).map(normParte);
    },

    async getParte(id) {
      const r = ok(await sb.from('partes_cab').select('*, ht_tareas, partes_det(*)').eq('id_parte', id).maybeSingle());
      if (!r) throw new Error('Parte no encontrado o sin permiso para verlo.');
      return { ...normParte(r), lineas: (r.partes_det || []).map(normLinea).sort((a, b) => a.h_ini.localeCompare(b.h_ini)) };
    },

    // th_jornada (migración 011). Solo el ADMIN ve la configuración; para el resto devuelve null.
    async getThJornada() {
      const r = ok(await sb.from('configuracion').select('valor').eq('clave', 'th_jornada').maybeSingle());
      return r ? Number(r.valor) : null;
    },

    // Valores iniciales del parte (migración 012): los puede leer cualquier rol.
    // → { h_ent: '07:30', h_sal: '18:00', t_alm_min: 30, t_com_min: 90 }
    async getValoresIniciales() {
      return ok(await sb.rpc('valores_iniciales_parte'));
    },

    // Única vía de escritura de partes y líneas: guardar_parte() (migración 009).
    // La BD valida el parte completo (jornada, solapes, desplazamientos, 15 minutos) y calcula h_ext
    // (solo respeta h_ext / h_ext_manual si los envía un ADMIN; migración 011).
    // Desde la 012, entrada, salida, almuerzo o comida vacíos se envían vacíos (null) y la BD pone el
    // valor de la configuración; 0 minutos se envía como 0.
    async saveParte({ id_parte, cab, lineas }) {
      return ok(await sb.rpc('guardar_parte', { p_id_parte: id_parte || null, p_cab: cabParaBd(cab), p_lineas: lineas }));
    },

    // ---------- Guardar por partes (migración 019): la jornada y cada línea por separado ----------
    // Crea (id vacío) o edita la jornada → id_parte. Si ya hay líneas, la BD comprueba que siguen dentro.
    async guardarCabecera(idParte, cab) {
      return ok(await sb.rpc('guardar_cabecera', { p_id_parte: idParte || null, p_cab: cabParaBd(cab) }));
    },
    // Crea (sin id_linea) o edita una línea → id_linea. La BD valida el orden y el parte completo.
    async guardarLinea(idParte, linea) {
      return ok(await sb.rpc('guardar_linea', { p_id_parte: idParte, p_linea: linea }));
    },
    // Quita una línea si el resto del parte sigue siendo válido.
    async borrarLinea(idLinea) {
      ok(await sb.rpc('borrar_linea', { p_id_linea: idLinea }));
    },

    // Cambios de estado y borrado solo mediante funciones (migración 010).
    // La BD sella quién y cuándo cierra (cerrado_por, fecha_cierre) y revisa (supervisor_revisa, fecha_revision).
    async cerrarParte(id) {
      ok(await sb.rpc('cerrar_parte', { p_id_parte: id }));
    },
    async revisarParte(id, estado, comentario) {
      ok(await sb.rpc('revisar_parte', { p_id_parte: id, p_estado: estado, p_comentario: comentario?.trim() || null }));
    },
    async borrarParte(id) {
      ok(await sb.rpc('borrar_parte', { p_id_parte: id }));
    },

    // ---------- Archivo de tareas y vueltas (migración 015). Solo ADMIN y SUPERVISOR ven filas. ----------
    // Vueltas: archivo + partes Aprobados aún sin archivar (vista vueltas).
    async listVueltas(f = {}) {
      return todas(() => {
        let q = sb.from('vueltas').select('*')
          .order('campana', { ascending: false }).order('parcela').order('tarea').order('num_vuelta');
        if (f.campana) q = q.eq('campana', f.campana);
        if (f.estado) q = q.eq('estado', f.estado);
        return q;
      });
    },
    // Tareas realizadas (vista tareas_resumen): misma fuente que las vueltas, fila a fila.
    async listTareasResumen(f = {}) {
      // Orden por todos los campos por los que se agrupa la vista: identifica cada fila.
      return todas(() => {
        let q = sb.from('tareas_resumen').select('*').order('fec_tarea').order('num_parte')
          .order('operario').order('tarea').order('finca').order('parcela').order('vehiculo').order('apero');
        if (f.desde) q = q.gte('fec_tarea', f.desde);
        if (f.hasta) q = q.lte('fec_tarea', f.hasta);
        return q;
      });
    },
    // Horas por trabajador (vista horas_trabajador): solo existen mientras no se archivan los partes.
    async listHorasTrabajador(f = {}) {
      // Un parte por operario y día: fecha + operario identifica cada fila.
      const filas = await todas(() => {
        let q = sb.from('horas_trabajador').select('*').order('fecha').order('operario');
        if (f.desde) q = q.gte('fecha', f.desde);
        if (f.hasta) q = q.lte('fecha', f.hasta);
        return q;
      });
      return filas.map((r) => ({ ...r, h_ent: hhmm(r.h_ent), h_sal: hhmm(r.h_sal) }));
    },
    // Archivados hechos, el último primero.
    async listArchivos() {
      return todas(() => sb.from('archivos_partes').select('*').order('hasta', { ascending: false }));
    },
    // Solo ADMIN. Devuelve { hasta, partes, lineas, filas, rechazados }.
    async archivarPartes(hasta) {
      return ok(await sb.rpc('archivar_partes', { p_hasta: hasta }));
    },

    // ---------- PDF del parte (migración 016) ----------
    // Versiones del PDF de un parte (las ven ADMIN, SUPERVISOR y el operario titular).
    async listPdfs(idParte) {
      return ok(await sb.from('partes_pdf')
        .select('id, version, estado, ruta, solicitado, solicitado_por, generado, error')
        .eq('id_parte', idParte).order('version', { ascending: false }));
    },
    // Botón "Generar PDF" (SUPERVISOR y ADMIN, partes Aprobados): la función del servidor generar-pdf
    // devuelve el último PDF si el parte no ha cambiado, o genera una versión nueva.
    // → { url (enlace de 5 minutos), ruta, version, nuevo }
    async generarPdf(idParte) {
      const { data, error } = await sb.functions.invoke('generar-pdf', { body: { id_parte: idParte } });
      if (error) {
        let msg = error.message;
        try { msg = (await error.context.json()).error || msg; } catch { /* respuesta sin JSON */ }
        if (/Failed to send|not found|404/i.test(msg)) {
          throw Object.assign(new Error('La función del servidor generar-pdf no responde.'), {
            hint: 'Comprueba que está desplegada en Supabase (Edge Functions).',
          });
        }
        throw new Error(msg);
      }
      return data;
    },
    // Última versión generada de cada parte, por fecha del parte (también de partes ya archivados o borrados).
    async listPdfsGenerados(f = {}) {
      const filas = await todas(() => {
        let q = sb.from('partes_pdf').select('id_parte, num_parte, fecha, operario, version, ruta, generado')
          .eq('estado', 'Generado').order('fecha', { ascending: false }).order('num_parte', { ascending: false })
          .order('version', { ascending: false });
        if (f.desde) q = q.gte('fecha', f.desde);
        if (f.hasta) q = q.lte('fecha', f.hasta);
        return q;
      });
      const vistos = new Set();
      return filas.filter((x) => !vistos.has(x.id_parte) && vistos.add(x.id_parte));
    },
    // Enlace de 5 minutos para abrir una versión ya generada.
    async urlPdf(ruta) {
      const r = ok(await sb.storage.from('partes-pdf').createSignedUrl(ruta, 300));
      return r.signedUrl;
    },
  };
}
