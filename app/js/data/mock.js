// MODO DEMO — todos los datos de este archivo son FICTICIOS.
// No proceden de BBDD.xlsx ni de PT_EC.xlsx; solo imitan su estructura (códigos, campos, estados).
// Se guardan en sessionStorage del navegador: se pierden al cerrar la pestaña.
// Emula las reglas del esquema propuesto (RLS por rol, un parte por operario y día, etc.).
import { esGestor, puedeEditar, puedeRevisar, calcHoras, calcTotHoras } from '../rules.js';

const KEY = 'pt-demo-v1';
const params = new URLSearchParams(location.search);
const FALLO = params.has('fallo');           // ?demo&fallo → simula un error de red al cargar partes
const wait = (ms = 300) => new Promise((r) => setTimeout(r, ms));

const OPERARIOS = [
  { cod_ope: 'D000', usuario: 'Admin Demo (ficticio)', email: 'admin.demo@example.com', rol_app: 'ADMIN', activo: true },
  { cod_ope: 'D001', usuario: 'Supervisora Demo (ficticio)', email: 'supervisora.demo@example.com', rol_app: 'SUPERVISOR', activo: true },
  { cod_ope: 'D002', usuario: 'Operario Uno (ficticio)', email: 'operario1.demo@example.com', rol_app: 'OPERARIO', activo: true },
  { cod_ope: 'D003', usuario: 'Operario Dos (ficticio)', email: 'operario2.demo@example.com', rol_app: 'OPERARIO', activo: true },
];

const CATALOGOS = {
  fincas: [
    { cod_fin: 'FD1', finca: 'Finca Demo Norte' },
    { cod_fin: 'FD2', finca: 'Finca Demo Sur' },
    { cod_fin: 'FD3', finca: 'Finca Demo Vega' },
  ],
  parcelas: [
    { cod_par: 'PD01', finca: 'FD1', nom_parc: 'Norte 1', superficie: 4.5 },
    { cod_par: 'PD02', finca: 'FD1', nom_parc: 'Norte 2', superficie: 3.2 },
    { cod_par: 'PD03', finca: 'FD2', nom_parc: 'Sur Alta', superficie: 6.0 },
    { cod_par: 'PD04', finca: 'FD2', nom_parc: 'Sur Baja', superficie: 2.75 },
    { cod_par: 'PD05', finca: 'FD3', nom_parc: 'Vega Río', superficie: 5.1 },
  ],
  tareas: [
    { cod_tar: 'TE901', tareas: 'Siembra (demo)', tipo: 'POR SUPERFICIE (HAS)' },
    { cod_tar: 'TE902', tareas: 'Abonado (demo)', tipo: 'POR SUPERFICIE (HAS)' },
    { cod_tar: 'TT901', tareas: 'Riego (demo)', tipo: 'POR HORAS' },
    { cod_tar: 'TT902', tareas: 'Taller (demo)', tipo: 'POR HORAS' },
  ],
  vehiculos: [
    { id_mat: 'DEMO-0001', alias: 'TD1', equipo: 'Tractor demo A', tipo: 'TRACTOR' },
    { id_mat: 'DEMO-0002', alias: 'TD2', equipo: 'Tractor demo B', tipo: 'TRACTOR' },
    { id_mat: 'DEMO-0003', alias: 'VD1', equipo: 'Furgoneta demo', tipo: 'VEHICULO' },
  ],
  aperos: [
    { id_bas: 'BDEMO0001', alias: 'AD1', equipo: 'Sembradora demo', tipo: 'SEMBRADORAS' },
    { id_bas: 'BDEMO0002', alias: 'AD2', equipo: 'Abonadora demo', tipo: 'ABONADORAS' },
  ],
};

const dia = (offset) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10);
};

function semilla() {
  const cab = (n, operario, offset, estado, extra = {}) => ({
    id_parte: `demo-${n}`, num_parte: n, operario, fecha: dia(offset),
    h_ent: '07:30', h_sal: '16:00', t_alm_min: 30, t_com_min: 0, h_ext: 0, mat_nave: false,
    finca: 'FD1', vehiculo: 'DEMO-0001', obs: '', estado,
    creado_por: OPERARIOS.find((o) => o.cod_ope === operario).email,
    fch_creacion: new Date().toISOString(), fch_modificacion: new Date().toISOString(),
    supervisor_revisa: null, fecha_revision: null, comentario_supervisor: null, ...extra,
  });
  const partes = [
    cab(1, 'D002', -3, 'Aprobado', { supervisor_revisa: 'D001', fecha_revision: new Date().toISOString() }),
    cab(2, 'D002', -2, 'Rechazado', { finca: 'FD2', supervisor_revisa: 'D001', fecha_revision: new Date().toISOString(),
      comentario_supervisor: 'Falta indicar la parcela en la línea de abonado (ficticio).' }),
    cab(3, 'D002', -1, 'Pendiente'),
    cab(4, 'D003', -1, 'Pendiente', { finca: 'FD3', vehiculo: 'DEMO-0002', h_ent: '08:00', h_sal: '15:00', t_alm_min: 0 }),
  ];
  const L = (id, id_parte, tarea, finca, parcela, h_ini, h_fin, apero = null) =>
    ({ id_linea: `l-${id}`, id_parte, tarea, finca, parcela, vehiculo: 'DEMO-0001', apero, h_ini, h_fin, obs: '' });
  const lineas = [
    L(1, 'demo-1', 'TE901', 'FD1', 'PD01', '07:30', '12:00', 'BDEMO0001'),
    L(2, 'demo-1', 'TT901', 'FD1', 'PD02', '12:30', '16:00'),
    L(3, 'demo-2', 'TE902', 'FD2', null, '07:30', '16:00', 'BDEMO0002'),
    L(4, 'demo-3', 'TT901', 'FD1', 'PD01', '07:30', '16:00'),
    L(5, 'demo-4', 'TT902', 'FD3', null, '08:00', '15:00'),
  ];
  return { partes, lineas, seq: 4, cod: null };
}

function cargar() {
  try { const s = JSON.parse(sessionStorage.getItem(KEY)); if (s?.partes) return s; } catch { /* sin storage */ }
  return semilla();
}

export function createMockApi(reason) {
  let db = cargar();
  const guardar = () => { try { sessionStorage.setItem(KEY, JSON.stringify(db)); } catch { /* sin storage */ } };
  const yo = () => OPERARIOS.find((o) => o.cod_ope === db.cod) || null;
  const visible = (p) => esGestor(yo()) || p.operario === yo()?.cod_ope;
  const conHoras = (p) => ({
    ...p, tot_horas: calcTotHoras(p),
    n_lineas: db.lineas.filter((l) => l.id_parte === p.id_parte).length,
  });
  const lineaConHoras = (l) => ({ ...l, t_horas: calcHoras(l.h_ini, l.h_fin) });
  const exigirSesion = () => { if (!yo()) throw new Error('Sesión no iniciada.'); };

  return {
    mode: 'demo',
    reason,

    demoUsers: () => OPERARIOS,
    async getSession() { await wait(80); return yo(); },
    async signInDemo(cod) { await wait(150); db.cod = cod; guardar(); return yo(); },
    async signOut() { db.cod = null; guardar(); },
    reset() { try { sessionStorage.removeItem(KEY); } catch { /* sin storage */ } },

    async listCatalogos() { await wait(150); return structuredClone(CATALOGOS); },
    async listOperarios() { exigirSesion(); return esGestor(yo()) ? OPERARIOS : [yo()]; },

    async listPartes(f = {}) {
      exigirSesion();
      await wait();
      if (FALLO) throw Object.assign(new Error('Error de red simulado (parámetro ?fallo).'), { hint: 'Quita "&fallo" de la URL para volver a la normalidad.' });
      return db.partes
        .filter(visible)
        .filter((p) => !f.estado || p.estado === f.estado)
        .filter((p) => !f.operario || p.operario === f.operario)
        .filter((p) => !f.finca || p.finca === f.finca)
        .filter((p) => !f.desde || p.fecha >= f.desde)
        .filter((p) => !f.hasta || p.fecha <= f.hasta)
        .sort((a, b) => b.fecha.localeCompare(a.fecha) || b.num_parte - a.num_parte)
        .map(conHoras);
    },

    async getParte(id) {
      exigirSesion();
      await wait();
      const p = db.partes.find((x) => x.id_parte === id);
      if (!p || !visible(p)) throw new Error('Parte no encontrado o sin permiso para verlo.');
      return { ...conHoras(p), lineas: db.lineas.filter((l) => l.id_parte === id).map(lineaConHoras) };
    },

    async saveParte({ id_parte, cab, lineas }) {
      exigirSesion();
      await wait(400);
      const u = yo();
      let p;
      if (id_parte) {
        p = db.partes.find((x) => x.id_parte === id_parte);
        if (!p || !visible(p) || !puedeEditar(u, p)) throw new Error('No tienes permiso para editar este parte.');
      } else if (cab.operario !== u.cod_ope && u.rol_app !== 'ADMIN') {
        throw new Error('Solo un ADMIN puede crear partes de otro operario.');
      }
      const operario = id_parte ? p.operario : cab.operario;
      if (db.partes.some((x) => x.operario === operario && x.fecha === cab.fecha && x.id_parte !== id_parte)) {
        throw new Error('Ya existe un parte de este operario para esa fecha (un parte por día).');
      }
      const ahora = new Date().toISOString();
      if (!id_parte) {
        db.seq += 1;
        p = { id_parte: `demo-${db.seq}`, num_parte: db.seq, estado: 'Pendiente', creado_por: u.email, fch_creacion: ahora,
          supervisor_revisa: null, fecha_revision: null, comentario_supervisor: null };
        db.partes.push(p);
      }
      const { operario: _ignorado, ...campos } = cab;
      Object.assign(p, campos, { operario, fch_modificacion: ahora });
      db.lineas = db.lineas.filter((l) => l.id_parte !== p.id_parte)
        .concat(lineas.map((l, i) => ({ ...l, id_linea: `l-${p.id_parte}-${i}-${Date.now()}`, id_parte: p.id_parte })));
      guardar();
      return p.id_parte;
    },

    async setEstado(id, estado, comentario) {
      exigirSesion();
      await wait(300);
      const u = yo();
      const p = db.partes.find((x) => x.id_parte === id);
      if (!p || !puedeRevisar(u, p)) throw new Error('No tienes permiso para revisar este parte.');
      if (estado === 'Rechazado' && !comentario?.trim()) throw new Error('Para rechazar hay que escribir un comentario.');
      Object.assign(p, { estado, comentario_supervisor: comentario?.trim() || null, supervisor_revisa: u.cod_ope,
        fecha_revision: new Date().toISOString(), fch_modificacion: new Date().toISOString() });
      guardar();
    },
  };
}
