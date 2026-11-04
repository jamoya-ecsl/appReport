// Reglas de negocio compartidas por los dos modos (demo y Supabase).
// En Supabase las mismas reglas las impone la BD (constraints, triggers, RLS, validar_parte()
// de la 009 y cerrar_parte()/revisar_parte()/borrar_parte() de la 010); aquí solo sirven para
// avisar antes de enviar y para mostrar u ocultar botones.

// Ciclo de vida (010): Pendiente → Cerrado → Aprobado | Rechazado. Sin vuelta atrás.
export const ESTADOS = ['Pendiente', 'Cerrado', 'Aprobado', 'Rechazado'];

export const TIPO_DESPLAZAMIENTO = 'DESPLAZAMIENTO';
export const TIPO_PERSONAL = 'MOTIVOS PERSONALES';

export const esGestor = (u) => !!u && (u.rol_app === 'ADMIN' || u.rol_app === 'SUPERVISOR');

// ADMIN: cualquier parte, en cualquier estado (sigue en su estado). SUPERVISOR (migración 013): los de
// cualquier operario en "Pendiente" o "Cerrado". OPERARIO: solo los suyos y solo en "Pendiente".
// (Igual que guardar_parte() y los disparadores de la BD.)
export const puedeEditar = (u, p) =>
  u?.rol_app === 'ADMIN'
  || (u?.rol_app === 'SUPERVISOR' && ['Pendiente', 'Cerrado'].includes(p.estado))
  || (u?.rol_app === 'OPERARIO' && p.operario === u.cod_ope && p.estado === 'Pendiente');

export const motivoNoEditable = (u, p) =>
  u?.rol_app === 'SUPERVISOR'
    ? `Este parte está "${p.estado}": como supervisor solo puedes corregir partes Pendientes o Cerrados. Lo corrige un ADMIN.`
    : `Este parte está "${p.estado}" y ya no lo puedes editar.`;

// Crear partes a nombre de otro operario (migración 013): ADMIN y SUPERVISOR.
export const puedeCrearParaOtros = (u) => u?.rol_app === 'ADMIN' || u?.rol_app === 'SUPERVISOR';

// Cerrar (Pendiente → Cerrado): el OPERARIO los suyos; SUPERVISOR y ADMIN cualquiera.
export const puedeCerrar = (u, p) =>
  p.estado === 'Pendiente' && (esGestor(u) || (u?.rol_app === 'OPERARIO' && p.operario === u.cod_ope));

// Revisar (Cerrado → Aprobado | Rechazado): gestores, pero un SUPERVISOR no revisa los suyos.
export const puedeRevisar = (u, p) =>
  esGestor(u) && p.estado === 'Cerrado' && !(u.rol_app === 'SUPERVISOR' && p.operario === u.cod_ope);

// Borrar: solo ADMIN, en cualquier estado.
export const puedeBorrar = (u) => u?.rol_app === 'ADMIN';

// Igual que el disparador tg_partes_cab_estado al cerrar.
export const errorCierre = (p, nLineas) =>
  !p.mat_nave && !nLineas ? 'Para cerrar un parte sin mantenimiento en nave hace falta al menos una tarea' : null;

// Igual que validar_parte() desde la 013: al corregir un parte ya cerrado no se le quitan todas las tareas.
export const errorSinTareas = (estado, matNave, nLineas) =>
  estado && estado !== 'Pendiente' && !matNave && !nLineas
    ? `El parte está ${estado}: sin mantenimiento en nave necesita al menos una tarea` : null;

const aMin = (t) => {
  if (!t) return null;
  const [h, m, s] = String(t).split(':').map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  return h * 60 + m + (Number(s) || 0) / 60;
};
const r2 = (n) => Math.round(n * 100) / 100;
const hhmm = (t) => String(t || '').slice(0, 5);

// Múltiplo de 15 minutos y sin segundos (como las restricciones *_cuartos_hora de la BD).
export const esCuartoDeHora = (t) => {
  const m = aMin(t);
  return m != null && Number.isInteger(m) && m % 15 === 0;
};

export function calcHoras(ini, fin) {
  const a = aMin(ini), b = aMin(fin);
  if (a == null || b == null || b <= a) return null;
  return r2((b - a) / 60);
}

// Valores iniciales del parte (migración 012). Los lee rpc('valores_iniciales_parte'); estos solo se
// usan si no se pueden leer (por ejemplo, antes de aplicar la 012).
export const VALORES_INICIALES = { h_ent: '07:30', h_sal: '18:00', t_alm_min: 30, t_com_min: 90 };
const vacio = (v) => v == null || String(v).trim() === '';
// Igual que guardar_parte() desde la 012: entrada, salida, almuerzo o comida vacíos → valor de la
// configuración, al crear y al editar. Un 0 escrito se respeta.
export const conValoresIniciales = (cab, ini = VALORES_INICIALES) => ({
  ...cab,
  h_ent: vacio(cab.h_ent) ? ini.h_ent : cab.h_ent,
  h_sal: vacio(cab.h_sal) ? ini.h_sal : cab.h_sal,
  t_alm_min: vacio(cab.t_alm_min) ? Number(ini.t_alm_min) : Number(cab.t_alm_min),
  t_com_min: vacio(cab.t_com_min) ? Number(ini.t_com_min) : Number(cab.t_com_min),
});

// Igual que la columna generada tot_horas: (salida - entrada) - almuerzo - comida
export function calcTotHoras(c) {
  const base = calcHoras(c.h_ent, c.h_sal);
  if (base == null) return null;
  return r2(base - (Number(c.t_alm_min) || 0) / 60 - (Number(c.t_com_min) || 0) / 60);
}

// Horas extra automáticas (migración 011): max(tot_horas − th_jornada, 0), en cuartos de hora.
export function calcHExt(c, th) {
  const tot = calcTotHoras(c);
  if (tot == null || th == null) return null;
  return Math.floor(Math.max(tot - Number(th), 0) * 4) / 4;
}

// Igual que el disparador tg_partes_cab_h_ext: decide h_ext y h_ext_manual al guardar.
//  - Otros roles: no corrigen; si no cambian horas ni pausas se conserva lo que había.
//  - ADMIN: se respeta su valor manual, salvo que cambien las horas sin tocar h_ext.
export function resolverHExt({ anterior, nueva, admin, th }) {
  const auto = calcHExt(nueva, th);
  const horasCambian = !anterior || ['h_ent', 'h_sal', 't_alm_min', 't_com_min']
    .some((k) => String(anterior[k]) !== String(nueva[k]));
  if (!admin) {
    return horasCambian ? { h_ext: auto, h_ext_manual: false }
      : { h_ext: anterior.h_ext, h_ext_manual: anterior.h_ext_manual };
  }
  let respetar = !!nueva.h_ext_manual;
  if (respetar && anterior && horasCambian && Number(nueva.h_ext) === Number(anterior.h_ext) && anterior.h_ext_manual) {
    respetar = false;
  }
  return respetar ? { h_ext: Number(nueva.h_ext) || 0, h_ext_manual: true } : { h_ext: auto, h_ext_manual: false };
}

// Horas de tareas sin MOTIVOS PERSONALES (como la función ht_tareas de la BD).
export const calcHtTareas = (lineas, cat) => r2(lineas
  .filter((l) => tipoTarea(cat, l.tarea) !== TIPO_PERSONAL)
  .reduce((s, l) => s + (calcHoras(l.h_ini, l.h_fin) || 0), 0));

export const tipoTarea = (cat, codTar) => cat.tareas.find((t) => t.cod_tar === codTar)?.tipo || null;

// fin_vuelta (migración 014): Sí (true) / No (false) / sin responder (null). Solo se pregunta en tareas con
// parcela y de tipo POR SUPERFICIE o POR HORAS (como requiere_fin_vuelta() de la BD); en el resto es No.
const TIPOS_CON_VUELTA = ['POR SUPERFICIE (HAS)', 'POR HORAS'];
export const requiereFinVuelta = (l, cat) => !!l.parcela && TIPOS_CON_VUELTA.includes(tipoTarea(cat, l.tarea));

// Como el disparador tg_partes_det_fin_vuelta: en las tareas a las que no se aplica se guarda No.
export const normalizarFinVuelta = (l, cat) =>
  ({ ...l, fin_vuelta: requiereFinVuelta(l, cat) ? (l.fin_vuelta ?? null) : false });

export const textoFinVuelta = (l, cat) => {
  if (!requiereFinVuelta(l, cat)) return '—';
  return l.fin_vuelta === true ? 'Sí' : l.fin_vuelta === false ? 'No' : 'Sin responder';
};

// Tareas sin responder, con el mismo formato que fin_vuelta_pendientes() de la BD; null si no hay.
export function errorFinVuelta(lineas, cat, inicio = 'Para cerrar el parte indica si termina la vuelta en') {
  const pend = ordenarLineas(lineas).filter((l) => requiereFinVuelta(l, cat) && l.fin_vuelta == null);
  if (!pend.length) return null;
  const nombre = (lista, campo, cod, txt) => cat[lista].find((x) => x[campo] === cod)?.[txt] || cod;
  return `${inicio}: ${pend.map((l) => `${hhmm(l.h_ini)}–${hhmm(l.h_fin)} (${nombre('tareas', 'cod_tar', l.tarea, 'tareas')}, `
    + `parcela ${nombre('parcelas', 'cod_par', l.parcela, 'nom_parc')})`).join('; ')}`;
}

export const etiquetaTipo = (tipo) => ({
  'POR HORAS': 'h', 'POR SUPERFICIE (HAS)': 'ha', [TIPO_DESPLAZAMIENTO]: 'desplazamiento', [TIPO_PERSONAL]: 'personal',
}[tipo] || '');

// Orden de las líneas: por hora de inicio (y fin), como validar_parte() en la BD.
export const ordenarLineas = (lineas) =>
  [...lineas].sort((a, b) => (aMin(a.h_ini) ?? 1e9) - (aMin(b.h_ini) ?? 1e9) || (aMin(a.h_fin) ?? 1e9) - (aMin(b.h_fin) ?? 1e9));

export function validarParte(cab, lineas, cat) {
  const e = [];
  if (!cab.operario) e.push('Falta el operario.');
  if (!cab.fecha) e.push('Falta la fecha.');
  if (!cab.h_ent || !cab.h_sal) e.push('Faltan la hora de entrada o de salida.');
  else if (calcHoras(cab.h_ent, cab.h_sal) == null) e.push('La hora de salida debe ser posterior a la de entrada.');
  else if (calcTotHoras(cab) < 0) e.push('Almuerzo + comida superan la duración de la jornada.');
  if (cab.h_ent && !esCuartoDeHora(cab.h_ent)) e.push('La hora de entrada debe ir en intervalos de 15 minutos (:00, :15, :30, :45).');
  if (cab.h_sal && !esCuartoDeHora(cab.h_sal)) e.push('La hora de salida debe ir en intervalos de 15 minutos (:00, :15, :30, :45).');
  if ((Number(cab.t_alm_min) || 0) % 15 !== 0) e.push('El almuerzo debe ir en múltiplos de 15 minutos.');
  if ((Number(cab.t_com_min) || 0) % 15 !== 0) e.push('La comida debe ir en múltiplos de 15 minutos.');
  const hExt = Number(cab.h_ext) || 0;
  if (hExt < 0 || !Number.isInteger(hExt * 4)) e.push('Las horas extra deben ser 0 o más, en múltiplos de 0,25 h.');

  // Comprobaciones de cada línea por separado
  const completas = [];
  lineas.forEach((l, i) => {
    const n = `Línea ${i + 1}:`;
    let ok = true;
    if (!l.tarea) { e.push(`${n} falta la tarea.`); ok = false; }
    if (!l.h_ini || !l.h_fin) { e.push(`${n} faltan hora de inicio o fin.`); ok = false; }
    else if (calcHoras(l.h_ini, l.h_fin) == null) { e.push(`${n} la hora de fin debe ser posterior a la de inicio.`); ok = false; }
    else if (!esCuartoDeHora(l.h_ini) || !esCuartoDeHora(l.h_fin)) { e.push(`${n} las horas deben ir en intervalos de 15 minutos.`); ok = false; }
    if (l.parcela) {
      const p = cat.parcelas.find((x) => x.cod_par === l.parcela);
      if (p && l.finca && p.finca !== l.finca) e.push(`${n} la parcela no pertenece a la finca elegida.`);
    }
    if (ok) completas.push(l);
  });
  if (completas.length !== lineas.length) return e;  // primero corregir lo básico

  // Comprobaciones del parte completo, en orden de hora de inicio (igual que validar_parte()).
  const nombreFinca = (cod) => cat.fincas.find((f) => f.cod_fin === cod)?.finca || cod;
  let prevFin = null;
  let fincaActual = null;
  for (const l of ordenarLineas(completas)) {
    const tipo = tipoTarea(cat, l.tarea);
    const n = `Tarea ${hhmm(l.h_ini)}–${hhmm(l.h_fin)}:`;
    if (cab.h_ent && cab.h_sal && (aMin(l.h_ini) < aMin(cab.h_ent) || aMin(l.h_fin) > aMin(cab.h_sal))) {
      e.push(`${n} debe estar dentro de la jornada (${hhmm(cab.h_ent)} – ${hhmm(cab.h_sal)}).`);
    }
    if (prevFin != null && aMin(l.h_ini) < aMin(prevFin)) {
      e.push(`${n} se solapa con la tarea anterior, que termina a las ${hhmm(prevFin)}.`);
    }
    prevFin = l.h_fin;

    if (tipo === TIPO_PERSONAL) {
      if (l.finca || l.parcela || l.vehiculo || l.apero) e.push(`${n} en MOTIVOS PERSONALES solo se indican las horas.`);
      continue;
    }
    if (!l.finca) { e.push(`${n} falta la finca.`); continue; }
    if (tipo === TIPO_DESPLAZAMIENTO) {
      if (!l.vehiculo) e.push(`${n} un DESPLAZAMIENTO necesita vehículo.`);
      fincaActual = l.finca;
    } else if (fincaActual == null) {
      e.push(`${n} la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un DESPLAZAMIENTO.`);
      fincaActual = l.finca;  // evita repetir el mismo aviso en cada línea
    } else if (l.finca !== fincaActual) {
      e.push(`${n} para pasar de ${nombreFinca(fincaActual)} a ${nombreFinca(l.finca)} hace falta antes un DESPLAZAMIENTO.`);
      fincaActual = l.finca;
    }
  }
  return e;
}
