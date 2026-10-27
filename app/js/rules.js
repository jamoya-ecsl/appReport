// Reglas de negocio compartidas por los dos modos (demo y Supabase).
// En Supabase las mismas reglas las impone la BD (constraints, triggers y RLS);
// aquí solo sirven para avisar antes de enviar.

export const ESTADOS = ['Pendiente', 'Aprobado', 'Rechazado'];

export const esGestor = (u) => !!u && (u.rol_app === 'ADMIN' || u.rol_app === 'SUPERVISOR');

// OPERARIO: solo sus partes y solo en "Pendiente". ADMIN/SUPERVISOR: cualquiera.
export const puedeEditar = (u, p) =>
  esGestor(u) || (p.operario === u.cod_ope && p.estado === 'Pendiente');

export const puedeRevisar = (u, p) => esGestor(u) && p.estado === 'Pendiente';

const aMin = (t) => {
  if (!t) return null;
  const [h, m] = t.split(':').map(Number);
  return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null;
};
const r2 = (n) => Math.round(n * 100) / 100;

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

export function validarParte(cab, lineas, cat) {
  const e = [];
  if (!cab.operario) e.push('Falta el operario.');
  if (!cab.fecha) e.push('Falta la fecha.');
  if (!cab.h_ent || !cab.h_sal) e.push('Faltan la hora de entrada o de salida.');
  else if (calcHoras(cab.h_ent, cab.h_sal) == null) e.push('La hora de salida debe ser posterior a la de entrada.');
  else if (calcTotHoras(cab) < 0) e.push('Almuerzo + comida superan la duración de la jornada.');
  if (!cab.finca) e.push('Falta la finca.');
  lineas.forEach((l, i) => {
    const n = `Línea ${i + 1}:`;
    if (!l.tarea) e.push(`${n} falta la tarea.`);
    if (!l.h_ini || !l.h_fin) e.push(`${n} faltan hora de inicio o fin.`);
    else if (calcHoras(l.h_ini, l.h_fin) == null) e.push(`${n} la hora de fin debe ser posterior a la de inicio.`);
    if (l.parcela) {
      const p = cat.parcelas.find((x) => x.cod_par === l.parcela);
      if (p && l.finca && p.finca !== l.finca) e.push(`${n} la parcela no pertenece a la finca elegida.`);
    }
  });
  return e;
}
