// MODO DEMO — todos los datos de este archivo son FICTICIOS.
// No proceden de BBDD.xlsx ni de PT_EC.xlsx; solo imitan su estructura (códigos, campos, estados).
// Se guardan en sessionStorage del navegador: se pierden al cerrar la pestaña.
// Emula las reglas del esquema (RLS por rol, un parte por operario y día, validar_parte() de la 009...).
import {
  esGestor, puedeEditar, puedeCerrar, puedeRevisar, puedeBorrar, errorCierre,
  calcHoras, calcTotHoras, validarParte, ordenarLineas, resolverHExt, calcHtTareas,
} from '../rules.js';

const KEY = 'pt-demo-v4';  // v4: configuración th_jornada y h_ext_manual (migración 011)
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
    { cod_tar: 'TD901', tareas: 'Desplazamiento (demo)', tipo: 'DESPLAZAMIENTO' },
    { cod_tar: 'TP901', tareas: 'Motivos personales (demo)', tipo: 'MOTIVOS PERSONALES' },
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
    h_ent: '07:30', h_sal: '16:00', t_alm_min: 30, t_com_min: 0, h_ext: 0, h_ext_manual: false, mat_nave: false,
    obs: '', estado,
    creado_por: OPERARIOS.find((o) => o.cod_ope === operario).email,
    fch_creacion: new Date().toISOString(), fch_modificacion: new Date().toISOString(),
    supervisor_revisa: null, fecha_revision: null, comentario_supervisor: null,
    cerrado_por: null, fecha_cierre: null, ...extra,
  });
  const ahora = new Date().toISOString();
  const cerrado = (por) => ({ cerrado_por: por, fecha_cierre: ahora });
  const partes = [
    cab(1, 'D002', -3, 'Aprobado', { ...cerrado('D002'), supervisor_revisa: 'D001', fecha_revision: ahora }),
    cab(2, 'D002', -2, 'Rechazado', { ...cerrado('D002'), supervisor_revisa: 'D001', fecha_revision: ahora,
      comentario_supervisor: 'Falta indicar la parcela en la línea de abonado (ficticio).' }),
    cab(3, 'D002', -1, 'Cerrado', cerrado('D002')),
    cab(4, 'D003', -1, 'Pendiente', { h_ent: '08:00', h_sal: '15:00', t_alm_min: 0 }),
  ];
  const L = (id, id_parte, tarea, finca, parcela, h_ini, h_fin, apero = null, vehiculo = 'DEMO-0001') =>
    ({ id_linea: `l-${id}`, id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, obs: '' });
  const P = (id, id_parte, h_ini, h_fin) =>
    ({ id_linea: `l-${id}`, id_parte, tarea: 'TP901', finca: null, parcela: null, vehiculo: null, apero: null, h_ini, h_fin, obs: '' });
  const lineas = [
    L(1, 'demo-1', 'TD901', 'FD1', null, '07:30', '08:00'),
    L(2, 'demo-1', 'TE901', 'FD1', 'PD01', '08:00', '12:00', 'BDEMO0001'),
    L(3, 'demo-1', 'TT901', 'FD1', 'PD02', '12:30', '16:00'),
    L(4, 'demo-2', 'TD901', 'FD2', null, '07:30', '08:00'),
    L(5, 'demo-2', 'TE902', 'FD2', null, '08:00', '16:00', 'BDEMO0002'),
    L(6, 'demo-3', 'TD901', 'FD1', null, '07:30', '08:00'),
    L(7, 'demo-3', 'TT901', 'FD1', 'PD01', '08:00', '12:00'),
    P(8, 'demo-3', '12:00', '12:30'),
    L(9, 'demo-3', 'TD901', 'FD3', null, '12:30', '13:00'),
    L(10, 'demo-3', 'TT902', 'FD3', 'PD05', '13:00', '16:00'),
    L(11, 'demo-4', 'TD901', 'FD3', null, '08:00', '08:30', null, 'DEMO-0002'),
    L(12, 'demo-4', 'TT902', 'FD3', null, '08:30', '15:00', null, 'DEMO-0002'),
  ];
  return { partes, lineas, seq: 4, cod: null, config: { th_jornada: 8 } };
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
  const lineasDe = (id) => db.lineas.filter((l) => l.id_parte === id);
  const conHoras = (p) => ({
    ...p, tot_horas: calcTotHoras(p),
    ht_tareas: calcHtTareas(lineasDe(p.id_parte), CATALOGOS),
    n_lineas: lineasDe(p.id_parte).length,
    fincas: [...new Set(lineasDe(p.id_parte).map((l) => l.finca).filter(Boolean))],
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

    // Como la tabla configuracion (011): solo el ADMIN la ve.
    async getThJornada() { exigirSesion(); return yo().rol_app === 'ADMIN' ? db.config.th_jornada : null; },

    async listPartes(f = {}) {
      exigirSesion();
      await wait();
      if (FALLO) throw Object.assign(new Error('Error de red simulado (parámetro ?fallo).'), { hint: 'Quita "&fallo" de la URL para volver a la normalidad.' });
      return db.partes
        .filter(visible)
        .filter((p) => !f.estado || p.estado === f.estado)
        .filter((p) => !f.operario || p.operario === f.operario)
        .filter((p) => !f.finca || lineasDe(p.id_parte).some((l) => l.finca === f.finca))
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
      return { ...conHoras(p), lineas: ordenarLineas(lineasDe(id)).map(lineaConHoras) };
    },

    async saveParte({ id_parte, cab, lineas }) {
      exigirSesion();
      await wait(400);
      const u = yo();
      let p;
      if (id_parte) {
        p = db.partes.find((x) => x.id_parte === id_parte);
        if (!p || !visible(p) || !puedeEditar(u, p)) {
          throw new Error(u.rol_app === 'SUPERVISOR'
            ? 'Un supervisor solo puede aprobar o rechazar el parte, no modificar su contenido'
            : 'No tienes permiso para editar este parte.');
        }
      } else if (cab.operario !== u.cod_ope && u.rol_app !== 'ADMIN') {
        throw new Error('Solo un ADMIN puede crear partes de otro operario.');
      }
      const operario = id_parte ? p.operario : cab.operario;
      // Igual que validar_parte() en la BD: se rechaza el guardado entero con el primer error.
      const errores = validarParte({ ...cab, operario }, lineas, CATALOGOS);
      if (errores.length) throw new Error(errores[0]);
      if (db.partes.some((x) => x.operario === operario && x.fecha === cab.fecha && x.id_parte !== id_parte)) {
        throw new Error('Ya existe un parte de este operario para esa fecha (un parte por día).');
      }
      const ahora = new Date().toISOString();
      if (!id_parte) {
        db.seq += 1;
        p = { id_parte: `demo-${db.seq}`, num_parte: db.seq, estado: 'Pendiente', creado_por: u.email, fch_creacion: ahora,
          supervisor_revisa: null, fecha_revision: null, comentario_supervisor: null, cerrado_por: null, fecha_cierre: null };
        db.partes.push(p);
      }
      const anterior = id_parte ? { ...p } : null;
      const { operario: _ignorado, h_ext: _h, h_ext_manual: _m, ...campos } = cab;
      // Igual que tg_partes_cab_h_ext (011): la BD calcula h_ext; solo el ADMIN lo corrige a mano.
      const hExt = resolverHExt({
        anterior,
        nueva: { ...campos, h_ext: cab.h_ext ?? anterior?.h_ext, h_ext_manual: cab.h_ext_manual ?? anterior?.h_ext_manual },
        admin: u.rol_app === 'ADMIN',
        th: db.config.th_jornada,
      });
      Object.assign(p, campos, hExt, { operario, fch_modificacion: ahora });
      db.lineas = db.lineas.filter((l) => l.id_parte !== p.id_parte)
        .concat(lineas.map((l, i) => ({ ...l, id_linea: `l-${p.id_parte}-${i}-${Date.now()}`, id_parte: p.id_parte })));
      guardar();
      return p.id_parte;
    },

    // Mismas reglas que cerrar_parte(), revisar_parte() y borrar_parte() de la migración 010.
    async cerrarParte(id) {
      exigirSesion();
      await wait(300);
      const u = yo();
      const p = db.partes.find((x) => x.id_parte === id);
      if (!p || !visible(p)) throw new Error('Parte no encontrado o sin permiso para cerrarlo');
      if (p.estado !== 'Pendiente') throw new Error(`Solo se puede cerrar un parte Pendiente (este está ${p.estado})`);
      if (!puedeCerrar(u, p)) throw new Error('Parte no encontrado o sin permiso para cerrarlo');
      const errores = validarParte(p, lineasDe(id), CATALOGOS);
      if (errores.length) throw new Error(errores[0]);
      const e = errorCierre(p, lineasDe(id).length);
      if (e) throw new Error(e);
      const ahora = new Date().toISOString();
      Object.assign(p, { estado: 'Cerrado', cerrado_por: u.cod_ope, fecha_cierre: ahora, fch_modificacion: ahora });
      guardar();
    },

    async revisarParte(id, estado, comentario) {
      exigirSesion();
      await wait(300);
      const u = yo();
      const p = db.partes.find((x) => x.id_parte === id);
      if (!esGestor(u)) throw new Error('Solo un SUPERVISOR o un ADMIN puede aprobar o rechazar partes');
      if (!p) throw new Error('Parte no encontrado');
      if (p.estado !== 'Cerrado') throw new Error(`Solo se puede aprobar o rechazar un parte Cerrado (este está ${p.estado})`);
      if (!puedeRevisar(u, p)) throw new Error('Un supervisor no puede aprobar ni rechazar sus propios partes; debe revisarlos un ADMIN');
      if (estado === 'Rechazado' && !comentario?.trim()) throw new Error('Para rechazar un parte hay que indicar el motivo en el comentario');
      const ahora = new Date().toISOString();
      Object.assign(p, { estado, comentario_supervisor: comentario?.trim() || null, supervisor_revisa: u.cod_ope,
        fecha_revision: ahora, fch_modificacion: ahora });
      guardar();
    },

    async borrarParte(id) {
      exigirSesion();
      await wait(300);
      if (!puedeBorrar(yo())) throw new Error('Solo un ADMIN puede borrar partes');
      if (!db.partes.some((x) => x.id_parte === id)) throw new Error('Parte no encontrado');
      db.partes = db.partes.filter((x) => x.id_parte !== id);
      db.lineas = db.lineas.filter((l) => l.id_parte !== id);
      guardar();
    },
  };
}
