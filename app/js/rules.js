// Reglas de negocio compartidas por los dos modos (demo y Supabase).
// En Supabase las mismas reglas las impone la BD (constraints, triggers, RLS, validar_parte()
// de la 009 y cerrar_parte()/revisar_parte()/borrar_parte() de la 010); aquí solo sirven para
// avisar antes de enviar y para mostrar u ocultar botones.

// Ciclo de vida (010): Pendiente → Cerrado → Aprobado | Rechazado. Sin vuelta atrás.
export const ESTADOS = ['Pendiente', 'Cerrado', 'Aprobado', 'Rechazado'];

export const TIPO_DESPLAZAMIENTO = 'DESPLAZAMIENTO';
export const TIPO_PERSONAL = 'MOTIVOS PERSONALES';

export const esGestor = (u) => !!u && (u.rol_app === 'ADMIN' || u.rol_app === 'SUPERVISOR');

// ADMIN: cualquier parte, en cualquier estado (sigue en su estado). OPERARIO: solo los suyos y solo
// en "Pendiente". SUPERVISOR: ninguno, ni siquiera los suyos; solo cierra, aprueba o rechaza
// (igual que los disparadores de la BD).
export const puedeEditar = (u, p) =>
  u?.rol_app === 'ADMIN' || (u?.rol_app === 'OPERARIO' && p.operario === u.cod_ope && p.estado === 'Pendiente');

export const motivoNoEditable = (u, p) =>
  u?.rol_app === 'SUPERVISOR'
    ? 'Como supervisor solo puedes cerrar, aprobar o rechazar partes, no modificar su contenido.'
    : `Este parte está "${p.estado}" y ya no lo puedes editar.`;

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

// Igual que la columna generada tot_horas: (salida - entrada) - almuerzo - comida
export function calcTotHoras(c) {
  const base = calcHoras(c.h_ent, c.h_sal);
  if (base == null) return null;
  return r2(base - (Number(c.t_alm_min) || 0) / 60 - (Number(c.t_com_min) || 0) / 60);
}

export const tipoTarea = (cat, codTar) => cat.tareas.find((t) => t.cod_tar === codTar)?.tipo || null;

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
