// Genera el SQL con un mes de partes de prueba (06/11/2026 a 05/12/2026, lunes a viernes)
// para los 4 operarios. Cada parte lo crea y lo cierra su operario (guardar_parte + cerrar_parte).
import { writeFileSync } from 'node:fs';

const out = process.argv[2];

const OPS = [
  { cod: 'T002', uid: 'aaff42de-8ed8-41d6-93e2-edfbde4cfe5d', email: 'jangel@escribanosl.es',
    coche: '7404LVD', tractor: 'AB37993VE', finca: 'MOJ', otras: ['GRA', 'CAB'],
    trabajos: [
      ['TE003', 'C1TB', 'BBBXXX0055', 3], ['TE010', 'C2TB', 'BBBXXX0075', 2], ['TE003', 'C1TB', 'BBBXXX0055', 2],
      ['TE018', 'C3TB', 'BBBXXX0153', 3], ['TE021', 'CCM', 'BBBXXX0164', 4], ['TE003', 'C2TB', 'BBBXXX0056', 99]] },
  { cod: 'T004', uid: '3b1a40ff-2d8e-486f-8c1f-2f6d0dbe3e98', email: 'victor@escribanosl.es',
    coche: '4197NKY', tractor: 'E0858BCN', finca: 'VAL', otras: ['CAM', 'GRA'],
    trabajos: [
      ['TE004', 'CGVT', 'BBBXXX0074', 3], ['TE034', 'CMVT', 'BBBXXX0020', 1], ['TE004', 'CGVT', 'BBBXXX0074', 2],
      ['TE014', 'CP7VT', 'BBBXXX0176', 3], ['TE036', 'CPVT', 'BBBXXX0021', 2], ['TE010', 'CGVT', 'BBBXXX0075', 99]] },
  { cod: 'T005', uid: '0c14096e-eb1a-45b0-a43a-69aa0d1c489e', email: 'mario@escribanosl.es',
    coche: '4871LVH', tractor: 'E1122BHB', finca: 'TIE', otras: ['GIN', 'CAB'],
    trabajos: [
      ['TE021', 'C11T', 'BBBXXX0166', 2], ['TE018', 'C11T', 'BBBXXX0154', 2], ['TE005', 'C12T', 'BBBXXX0011', 3],
      ['TE040', 'C21T', 'BBBXXX0176', 2], ['TE021', 'C4T', 'BBBXXX0167', 3], ['TE005', 'C12T', 'BBBXXX0011', 99]] },
  { cod: 'T006', uid: '4b4c1c58-3f87-41ea-a62d-8aa78fbe8576', email: 'fran@escribanosl.es',
    coche: '7441LVX', tractor: 'AB41588VE', finca: 'CEP', otras: ['CAM', 'GIN'],
    trabajos: [
      ['TE033', 'C10CP', 'BBBXXX0033', 2], ['TE020', 'C10CP', 'BBBXXX0168', 3], ['TE036', 'C18CP', 'BBBXXX0022', 1],
      ['TE020', 'C20CP', 'BBBXXX0168', 3], ['TE022', 'C21CP', 'BBBXXX0160', 2], ['TE020', 'C21CP', 'BBBXXX0168', 99]] },
];

// Parcelas por finca para las tareas por horas
const PAR = {
  MOJ: ['C1TB', 'C2TB', 'C3TB', 'CCM'], VAL: ['CGVT', 'CMVT', 'CP7VT', 'CPVT'], TIE: ['C11T', 'C12T', 'C21T', 'C4T'],
  CEP: ['C10CP', 'C18CP', 'C20CP', 'C21CP'], GRA: ['A1V', 'A2V', 'A3V', 'A4V'], CAB: ['CCCB', 'CCCBS', 'CPCB', 'LVCB'],
  CAM: ['SELC', 'SGLC', 'SMLC', 'SPLC'], GIN: ['S1LG', 'S2LG'],
};

// Días laborables
const dias = [];
for (let d = new Date(Date.UTC(2026, 10, 6)); d <= new Date(Date.UTC(2026, 11, 5)); d.setUTCDate(d.getUTCDate() + 1)) {
  const w = d.getUTCDay();
  if (w !== 0 && w !== 6) dias.push(d.toISOString().slice(0, 10));
}

const L = (tarea, h_ini, h_fin, x = {}) => ({ tarea, h_ini, h_fin, ...x });

// Plantillas de día. `M(h_ini, h_fin)` = tramo del trabajo principal (tarea por superficie con tractor y apero).
// Pausas habituales: almuerzo 10:00–10:30, comida 13:30–15:00.
const PLANTILLAS = [
  // 0 Jornada normal en la finca habitual
  (o, M, k) => ({ nombre: 'normal', cab: {}, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.finca, vehiculo: o.coche }),
    M('08:00', '10:00'), M('10:30', '13:30'), M('15:00', '18:00')] }),
  // 1 Cambio de finca: por horas en otra finca y DESPLAZAMIENTO a la habitual
  (o, M, k) => ({ nombre: 'cambio de finca', cab: {}, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.otras[0], vehiculo: o.coche }),
    L('TT032', '08:00', '10:00', { finca: o.otras[0], parcela: PAR[o.otras[0]][k % PAR[o.otras[0]].length], fin_vuelta: true,
      obs: 'Revisión de goteros' }),
    L('TT006', '10:30', '12:00', { finca: o.otras[0], obs: 'Camino de acceso' }),
    L('TD001', '12:00', '12:30', { finca: o.finca, vehiculo: o.coche }),
    M('12:30', '13:30'), M('15:00', '18:00')] }),
  // 2 Día de nave y taller: la primera vez acaba en el campo; la segunda, todo el día en la nave
  (o, M, k) => Math.floor(k / 10) % 2 === 1 ? ({ nombre: 'todo el día en la nave', cab: { obs: 'Día de taller' }, lineas: [
    L('TN001', '07:30', '10:00', { obs: 'Limpieza y orden de la nave' }),
    L('TV001', '10:30', '13:30', { vehiculo: o.tractor, obs: 'Revisión de frenos' }),
    L('TV001', '15:00', '18:00', { apero: 'BBBXXX0074', obs: 'Cambio de platos de la grada' })] }) :
  ({ nombre: 'nave y taller', cab: { obs: 'Mañana en la nave' }, lineas: [
    L('TN001', '07:30', '10:00', { obs: 'Limpieza y orden de la nave' }),
    L('TV001', '10:30', '13:30', { vehiculo: o.tractor, obs: 'Cambio de aceite y filtros' }),
    L('TV001', '15:00', '16:30', { apero: 'BBBXXX0055', obs: 'Engrase de discos' }),
    L('TD001', '16:30', '17:00', { finca: o.finca, vehiculo: o.coche }),
    L('TT023', '17:00', '18:00', { finca: o.finca, parcela: PAR[o.finca][k % 4], fin_vuelta: k % 2 === 0 })] }),
  // 3 Motivos personales al empezar
  (o, M, k) => ({ nombre: 'motivos personales al inicio', cab: { obs: 'Entra tarde: médico' }, lineas: [
    L('TP001', '07:30', '09:00', { obs: 'Cita médica' }),
    L('TD001', '09:00', '09:30', { finca: o.finca, vehiculo: o.coche }),
    M('09:30', '10:00'), M('10:30', '13:30'), M('15:00', '18:00')] }),
  // 4 Motivos personales a media jornada
  (o, M, k) => ({ nombre: 'motivos personales en medio', cab: {}, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.finca, vehiculo: o.coche }),
    M('08:00', '10:00'), M('10:30', '11:30'),
    L('TP001', '11:30', '13:30', { obs: 'Gestión personal' }),
    M('15:00', '18:00')] }),
  // 5 Horas extra (sale a las 19:30)
  (o, M, k) => ({ nombre: 'horas extra', cab: { h_sal: '19:30', obs: 'Se alarga para terminar la parcela' }, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.finca, vehiculo: o.coche }),
    M('08:00', '10:00'), M('10:30', '13:30'), M('15:00', '19:30')] }),
  // 6 Jornada intensiva 07:00–15:00, sin comida
  (o, M, k) => ({ nombre: 'intensiva sin comida', cab: { h_ent: '07:00', h_sal: '15:00', t_com: '0 minutes' }, lineas: [
    L('TD001', '07:00', '07:30', { finca: o.finca, vehiculo: o.coche }),
    M('07:30', '10:00'), M('10:30', '15:00')] }),
  // 7 Nave primero y luego campo
  (o, M, k) => ({ nombre: 'nave y luego campo', cab: {}, lineas: [
    L('TN001', '07:30', '09:00', { obs: 'Preparar semilla y abono' }),
    L('TD001', '09:00', '09:30', { finca: o.finca, vehiculo: o.coche }),
    M('09:30', '10:00'), M('10:30', '13:30'), M('15:00', '18:00')] }),
  // 8 Tres fincas en el día, sin almuerzo
  (o, M, k) => ({ nombre: 'tres fincas', cab: { t_alm: '0 minutes', t_com: '60 minutes' }, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.otras[0], vehiculo: o.coche }),
    L('TT026', '08:00', '10:00', { finca: o.otras[0], parcela: PAR[o.otras[0]][(k + 1) % PAR[o.otras[0]].length], fin_vuelta: k === 19 }),
    L('TD001', '10:00', '10:45', { finca: o.otras[1], vehiculo: o.coche }),
    L('TT004', '10:45', '13:30', { finca: o.otras[1], parcela: PAR[o.otras[1]][k % PAR[o.otras[1]].length], vehiculo: o.tractor,
      apero: 'BBBXXX0059', fin_vuelta: true }),
    L('TD001', '14:30', '15:00', { finca: o.finca, vehiculo: o.coche }),
    M('15:00', '18:00')] }),
  // 9 Todo el día cargando (por horas sin parcela) y taller al final
  (o, M, k) => ({ nombre: 'carga sin parcela', cab: {}, lineas: [
    L('TD001', '07:30', '08:00', { finca: o.finca, vehiculo: o.coche }),
    L('TT007', '08:00', '10:00', { finca: o.finca, vehiculo: o.tractor, apero: 'BBBXXX0138', obs: 'Carga de cebolla' }),
    L('TT007', '10:30', '13:30', { finca: o.finca, vehiculo: o.tractor, apero: 'BBBXXX0138' }),
    L('TT046', '15:00', '17:00', { finca: o.finca }),
    L('TV001', '17:00', '18:00', { vehiculo: o.coche, obs: 'Revisión de ruedas' })] }),
];

const resumen = [];
const partes = [];
OPS.forEach((o, oi) => {
  let j = 0, hechos = 0; // trabajo principal en curso y días que lleva
  dias.forEach((fecha, di) => {
    const t = (di + oi * 3) % PLANTILLAS.length;
    const [tar, par, ape, ndias] = o.trabajos[j];
    const M = (h_ini, h_fin) => ({ tarea: tar, finca: o.finca, parcela: par, vehiculo: o.tractor, apero: ape, h_ini, h_fin, _main: true });
    const p = PLANTILLAS[t](o, M, di);
    const main = p.lineas.filter((l) => l._main);
    let finVuelta = false;
    if (main.length) {
      hechos++;
      const ultimoDia = hechos >= ndias;
      main.forEach((l, i) => { l.fin_vuelta = ultimoDia && i === main.length - 1; });
      if (ultimoDia) { finVuelta = true; j++; hechos = 0; }
    }
    p.lineas.forEach((l) => delete l._main);
    partes.push({ o, fecha, cab: { fecha, t_alm: '30 minutes', t_com: '90 minutes', ...p.cab }, lineas: p.lineas });
    resumen.push(`${o.cod} ${fecha} ${p.nombre}${main.length ? ` · ${tar} ${par}${finVuelta ? ' FIN VUELTA' : ''}` : ''}`);
  });
});

const q = (s) => `'${s.replace(/'/g, "''")}'`;
for (const o of OPS) {
  let sql = `-- Datos de prueba: partes Cerrados de ${o.cod} (06/11/2026–05/12/2026, lunes a viernes).
-- Cada parte lo crea y lo cierra el propio operario. Si uno incumple una regla, no se guarda ninguno de este bloque.
do $$
declare v uuid;
begin
`;
  for (const p of partes.filter((x) => x.o === o)) {
    const claims = JSON.stringify({ sub: o.uid, email: o.email, role: 'authenticated' });
    sql += `  perform set_config('request.jwt.claims', ${q(claims)}, true); set local role authenticated;
  v := guardar_parte(null, ${q(JSON.stringify(p.cab))}::jsonb, ${q(JSON.stringify(p.lineas))}::jsonb);
  perform cerrar_parte(v); reset role;
`;
  }
  sql += `end $$;
`;
  writeFileSync(`${out}_${o.cod}.sql`, sql);
}
console.log(resumen.join('\n'));
console.log(`\n${partes.length} partes, ${partes.reduce((a, p) => a + p.lineas.length, 0)} líneas`);
