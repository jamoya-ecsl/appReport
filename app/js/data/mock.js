// MODO DEMO — todos los datos de este archivo son FICTICIOS.
// No proceden de BBDD.xlsx ni de PT_EC.xlsx; solo imitan su estructura (códigos, campos, estados).
// Se guardan en sessionStorage del navegador: se pierden al cerrar la pestaña.
// Emula las reglas del esquema (RLS por rol, un parte por operario y día, validar_parte() de la 009...).
import {
  esGestor, puedeEditar, puedeCerrar, puedeRevisar, puedeBorrar, errorCierre, puedeCrearParaOtros, errorSinTareas,
  normalizarFinVuelta, errorFinVuelta, errorFechaArchivada, filasResumen, calcVueltas,
  calcHoras, calcTotHoras, validarParte, ordenarLineas, resolverHExt, calcHtTareas, conValoresIniciales,
} from '../rules.js';

const KEY = 'pt-demo-v7';  // v7: archivo de tareas y vueltas (migración 015)
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
    L(12, 'demo-4', 'TT902', 'FD3', 'PD05', '08:30', '15:00', null, 'DEMO-0002'),
  ];
  // fin_vuelta (014): respuestas de las tareas con parcela; la del parte Pendiente (l-12) queda sin responder.
  const respuestas = { 'l-2': true, 'l-3': false, 'l-7': false, 'l-10': true };
  lineas.forEach((l, i) => { lineas[i] = normalizarFinVuelta({ ...l, fin_vuelta: respuestas[l.id_linea] ?? null }, CATALOGOS); });
  // Como la tabla configuracion (011 y 012).
  const config = { th_jornada: 8.5, cfh_ent: '07:30', cfh_sal: '18:00', cft_alm: 30, cft_com: 90, cfc_inicio: '09-01' };
  // Como archivos_partes y tareas_realizadas (015): vacías al empezar.
  return { partes, lineas, seq: 4, cod: null, config, archivos: [], archivo: [] };
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
  const ultimoArchivo = () => db.archivos.reduce((m, a) => (a.hasta > m ? a.hasta : m), '') || null;
  const esGestorActual = () => { exigirSesion(); return esGestor(yo()); };
  const filtrarFechas = (lista, campo, f) => lista
    .filter((x) => !f.desde || x[campo] >= f.desde).filter((x) => !f.hasta || x[campo] <= f.hasta);
  const dma = (d) => d.split('-').reverse().join('/');
  // Como la vista tareas_resumen: archivo + partes Aprobados sin archivar.
  const tareasResumen = () => db.archivo.concat(filasResumen(db.partes, db.lineas, CATALOGOS, db.config.cfc_inicio));
  const valoresIniciales = () => ({ h_ent: db.config.cfh_ent, h_sal: db.config.cfh_sal,
    t_alm_min: db.config.cft_alm, t_com_min: db.config.cft_com });

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
    // Como valores_iniciales_parte() (012): cualquier rol lee estos 4 valores.
    async getValoresIniciales() { exigirSesion(); return valoresIniciales(); },

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

    async saveParte({ id_parte, cab: cabEnviada, lineas: lineasEnviadas }) {
      // Como tg_partes_det_fin_vuelta (014): en las tareas a las que no se aplica, No.
      const lineas = lineasEnviadas.map((l) => normalizarFinVuelta(l, CATALOGOS));
      exigirSesion();
      await wait(400);
      const u = yo();
      // Igual que guardar_parte() desde la 012: campos vacíos → valores de la configuración.
      const cab = conValoresIniciales(cabEnviada, valoresIniciales());
      let p;
      if (id_parte) {
        p = db.partes.find((x) => x.id_parte === id_parte);
        // Como guardar_parte() desde la 013: el SUPERVISOR corrige Pendientes y Cerrados.
        if (!p || !visible(p) || !puedeEditar(u, p)) throw new Error('Parte no encontrado o sin permiso para editarlo');
        const e = errorSinTareas(p.estado, cab.mat_nave, lineas.length)
          || (p.estado !== 'Pendiente' ? errorFinVuelta(lineas, CATALOGOS, `El parte está ${p.estado}: indica si termina la vuelta en`) : null);
        if (e) throw new Error(e);
      } else {
        if (cab.operario !== u.cod_ope && !puedeCrearParaOtros(u)) {
          throw new Error('Solo un ADMIN o un SUPERVISOR pueden crear partes de otro operario');
        }
        if (!OPERARIOS.some((o) => o.cod_ope === cab.operario && o.activo)) {
          throw new Error(`El operario ${cab.operario} no existe o está dado de baja`);
        }
      }
      const operario = id_parte ? p.operario : cab.operario;
      // Como partes_cab_fecha_archivada (015).
      const eArch = errorFechaArchivada(cab.fecha, ultimoArchivo());
      if (eArch) throw new Error(eArch);
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
      const e = errorCierre(p, lineasDe(id).length) || errorFinVuelta(lineasDe(id), CATALOGOS);
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

    // ---------- Archivo de tareas y vueltas: como las vistas y archivar_partes() de la 015 ----------
    // Las vistas solo devuelven filas a ADMIN y SUPERVISOR; al operario, ninguna.
    async listVueltas(f = {}) {
      await wait();
      if (!esGestorActual()) return [];
      return calcVueltas(tareasResumen(), CATALOGOS)
        .filter((v) => !f.campana || v.campana === f.campana)
        .filter((v) => !f.estado || v.estado === f.estado)
        .sort((a, b) => b.campana.localeCompare(a.campana) || a.parcela.localeCompare(b.parcela)
          || a.tarea.localeCompare(b.tarea) || a.num_vuelta - b.num_vuelta);
    },
    async listTareasResumen(f = {}) {
      await wait();
      if (!esGestorActual()) return [];
      return filtrarFechas(tareasResumen(), 'fec_tarea', f)
        .sort((a, b) => a.fec_tarea.localeCompare(b.fec_tarea) || a.num_parte - b.num_parte);
    },
    async listHorasTrabajador(f = {}) {
      await wait();
      if (!esGestorActual()) return [];
      return filtrarFechas(db.partes, 'fecha', f)
        .map((p) => ({ parte: p.num_parte, operario: p.operario, fecha: p.fecha, h_ent: p.h_ent, h_sal: p.h_sal,
          t_alm_min: p.t_alm_min, t_com_min: p.t_com_min, estado: p.estado }))
        .sort((a, b) => a.fecha.localeCompare(b.fecha) || a.operario.localeCompare(b.operario));
    },
    async listArchivos() {
      await wait(100);
      if (!esGestorActual()) return [];
      return [...db.archivos].sort((a, b) => b.hasta.localeCompare(a.hasta));
    },
    async archivarPartes(hasta) {
      exigirSesion();
      await wait(500);
      const u = yo();
      if (u.rol_app !== 'ADMIN') throw new Error('Solo un ADMIN puede archivar partes');
      const hoy = new Date().toISOString().slice(0, 10);
      if (!hasta || hasta >= hoy) throw new Error('Solo se puede archivar hasta ayer como mucho');
      const ult = ultimoArchivo();
      if (ult && hasta <= ult) throw new Error(`Ya está archivado hasta el ${dma(ult)}`);
      const enRango = db.partes.filter((p) => p.fecha <= hasta);
      const bloq = enRango.filter((p) => p.estado === 'Pendiente' || p.estado === 'Cerrado')
        .sort((a, b) => a.fecha.localeCompare(b.fecha) || a.num_parte - b.num_parte);
      if (bloq.length) {
        const txt = bloq.slice(0, 10).map((p) => `nº ${p.num_parte} (${p.estado}, ${dma(p.fecha)})`).join(', ');
        throw new Error(`No se puede archivar: hay ${bloq.length} parte(s) hasta el ${dma(hasta)} sin aprobar: ${txt}${bloq.length > 10 ? ', …' : ''}`);
      }
      const aprobados = enRango.filter((p) => p.estado === 'Aprobado');
      const idsAprobados = new Set(aprobados.map((p) => p.id_parte));
      const ids = new Set(enRango.map((p) => p.id_parte));
      const lineas = db.lineas.filter((l) => idsAprobados.has(l.id_parte));
      const id = db.archivos.length + 1;
      const filas = filasResumen(aprobados, lineas, CATALOGOS, db.config.cfc_inicio, 'archivo')
        .map((f) => ({ ...f, id_archivo: id }));
      const r = { hasta, partes: aprobados.length, lineas: lineas.length, filas: filas.length,
        rechazados: enRango.length - aprobados.length };
      db.archivo.push(...filas);
      db.archivos.push({ id, hasta, fecha: new Date().toISOString(), archivado_por: u.cod_ope,
        partes: r.partes, lineas: r.lineas, filas: r.filas, rechazados: r.rechazados });
      db.partes = db.partes.filter((p) => !ids.has(p.id_parte));
      db.lineas = db.lineas.filter((l) => !ids.has(l.id_parte));
      guardar();
      return r;
    },
  };
}
