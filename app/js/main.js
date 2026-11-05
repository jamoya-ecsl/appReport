// Boceto funcional "Partes de Trabajo". Navegación por hash:
//   #/login · #/inicio · #/partes?filtros · #/partes/nuevo · #/partes/:id · #/partes/:id/editar
//   #/archivo?filtros (vueltas, exportaciones y archivo; solo ADMIN y SUPERVISOR)
import { createApi } from './data/index.js';
import { esc, fmtFecha, fmtFechaHora, fmtHoras, badge, loadingHtml, emptyHtml, errorHtml, toast, options } from './ui.js';
import {
  ESTADOS, TIPO_DESPLAZAMIENTO, TIPO_PERSONAL, esGestor, puedeEditar, motivoNoEditable,
  puedeCerrar, puedeRevisar, puedeBorrar, errorCierre,
  calcHoras, calcTotHoras, calcHExt, calcHtTareas, validarParte, tipoTarea, etiquetaTipo, ordenarLineas,
  VALORES_INICIALES, conValoresIniciales, puedeCrearParaOtros, errorSinTareas,
  requiereFinVuelta, textoFinVuelta, errorFinVuelta, aCsv,
} from './rules.js';

const root = document.getElementById('app');
const st = { api: null, user: null, cat: null, operarios: [] };

const nombreOperario = (cod) => st.operarios.find((o) => o.cod_ope === cod)?.usuario || cod || '—';
const nombreFinca = (cod) => st.cat?.fincas.find((f) => f.cod_fin === cod)?.finca || cod || '—';
const nombreTarea = (cod) => st.cat?.tareas.find((t) => t.cod_tar === cod)?.tareas || cod || '—';
const nombreParcela = (cod) => st.cat?.parcelas.find((p) => p.cod_par === cod)?.nom_parc || cod || '—';
const nombreVehiculo = (cod) => { const v = st.cat?.vehiculos.find((x) => x.id_mat === cod); return v ? `${v.alias} · ${v.equipo}` : cod || '—'; };
const nombreApero = (cod) => { const a = st.cat?.aperos.find((x) => x.id_bas === cod); return a ? `${a.alias} · ${a.equipo}` : cod || '—'; };
const demoLink = '<a class="button secondary" href="?demo#/login">Usar modo demo</a>';

boot();

async function boot() {
  root.innerHTML = loadingHtml('Iniciando…');
  try {
    st.api = await createApi();
    st.user = await st.api.getSession();
  } catch (e) {
    return fatal(e);
  }
  window.addEventListener('hashchange', route);
  route();
}

function fatal(e) {
  root.innerHTML = `<main id="main" class="narrow">${errorHtml(e, {
    extra: `${e.signedIn ? '<button data-action="logout" class="secondary">Cerrar sesión</button>' : ''}${demoLink}`,
  })}</main>`;
  root.querySelector('[data-action=retry]')?.addEventListener('click', () => location.reload());
  root.querySelector('[data-action=logout]')?.addEventListener('click', async () => { await st.api.signOut(); location.reload(); });
}

function parseHash() {
  const [path, qs] = (location.hash.slice(1) || '/inicio').split('?');
  return { parts: path.split('/').filter(Boolean), query: Object.fromEntries(new URLSearchParams(qs || '')) };
}

async function route() {
  const { parts, query } = parseHash();
  if (!st.user && parts[0] !== 'login') { location.hash = '#/login'; return; }
  if (st.user && parts[0] === 'login') { location.hash = '#/inicio'; return; }
  if (!st.user) return viewLogin();

  if (!st.cat) {
    const main = shell(loadingHtml('Cargando catálogos…'));
    try {
      [st.cat, st.operarios] = await Promise.all([st.api.listCatalogos(), st.api.listOperarios()]);
    } catch (e) {
      return showError(main, e, route);
    }
  }
  window.scrollTo(0, 0);
  if (parts[0] === 'inicio') return viewInicio();
  if (parts[0] === 'partes' && !parts[1]) return viewLista(query);
  if (parts[0] === 'partes' && parts[1] === 'nuevo') return viewForm(null);
  if (parts[0] === 'partes' && parts[2] === 'editar') return viewForm(parts[1]);
  if (parts[0] === 'partes') return viewDetalle(parts[1]);
  if (parts[0] === 'archivo' && esGestor(st.user)) return viewArchivo(query);
  shell(emptyHtml('Esta pantalla no existe.', '<a class="button" href="#/inicio">Volver al inicio</a>'));
}

function showError(main, e, retry) {
  main.innerHTML = errorHtml(e, { extra: st.api?.mode === 'supabase' && e.hint?.includes('demo') ? demoLink : '' });
  main.querySelector('[data-action=retry]')?.addEventListener('click', retry);
}

// ---------- Marco común: aviso de modo, cabecera y navegación ----------
function shell(html) {
  const u = st.user;
  const { parts } = parseHash();
  const activo = (p) => (parts[0] === p && !parts[1]) || (p === 'nuevo' && parts[1] === 'nuevo') ? 'class="active"' : '';
  root.innerHTML = `
    ${st.api.mode === 'demo' ? `<div class="demo-banner">MODO DEMO · datos ficticios guardados solo en esta pestaña (${esc(st.api.reason)}) · <button class="link" data-action="reset">Reiniciar datos</button></div>` : ''}
    <header class="top">
      <a class="brand" href="#/inicio">Partes de Trabajo</a>
      ${u ? `<nav>
          <a href="#/inicio" ${activo('inicio')}>Inicio</a>
          <a href="#/partes" ${activo('partes')}>${esGestor(u) ? 'Todos los partes' : 'Mis partes'}</a>
          <a href="#/partes/nuevo" ${activo('nuevo')}>+ Nuevo parte</a>
          ${esGestor(u) ? `<a href="#/archivo" ${activo('archivo')}>Vueltas y archivo</a>` : ''}
        </nav>
        <div class="who">${esc(u.usuario)} <span class="rol">${esc(u.rol_app)}</span>
          <button class="link" data-action="logout">Salir</button></div>` : ''}
    </header>
    <main id="main">${html}</main>`;
  root.querySelector('[data-action=logout]')?.addEventListener('click', async () => {
    await st.api.signOut();
    Object.assign(st, { user: null, cat: null, operarios: [] });
    location.hash = '#/login';
  });
  root.querySelector('[data-action=reset]')?.addEventListener('click', () => { st.api.reset(); location.reload(); });
  return root.querySelector('#main');
}

// ---------- Login ----------
function viewLogin() {
  if (st.api.mode === 'demo') {
    const main = shell(`<section class="card narrow">
      <h1>Entrar (modo demo)</h1>
      <p class="muted">Elige un usuario ficticio para probar cada rol.</p>
      <div class="user-list">${st.api.demoUsers().map((o) => `
        <button class="user-pick" data-cod="${esc(o.cod_ope)}"><strong>${esc(o.usuario)}</strong><span class="rol">${esc(o.rol_app)}</span></button>`).join('')}
      </div></section>`);
    main.querySelectorAll('.user-pick').forEach((b) => b.addEventListener('click', async () => {
      b.disabled = true;
      st.user = await st.api.signInDemo(b.dataset.cod);
      location.hash = '#/inicio';
    }));
    return;
  }
  const main = shell(`<section class="card narrow">
    <h1>Entrar</h1>
    <p class="muted">Usa el email registrado en la tabla de operarios.</p>
    <form id="f-login" class="stack">
      <label>Email <input type="email" name="email" required autocomplete="email"></label>
      <label>Contraseña <input type="password" name="password" autocomplete="current-password"></label>
      <button type="submit" data-modo="password">Entrar</button>
      <button type="button" class="secondary" data-modo="enlace">Sin contraseña: enviarme un enlace por email</button>
      <div id="login-msg"></div>
    </form></section>`);
  const form = main.querySelector('#f-login');
  const msg = main.querySelector('#login-msg');
  const botones = form.querySelectorAll('button');

  async function ejecutar(modo) {
    if (!form.email.reportValidity()) return;
    if (modo === 'password' && !form.password.value) {
      msg.innerHTML = errorHtml(new Error('Escribe la contraseña, o usa el enlace por email.'), { retry: false });
      return;
    }
    botones.forEach((b) => { b.disabled = true; });
    msg.innerHTML = loadingHtml(modo === 'password' ? 'Entrando…' : 'Enviando enlace…');
    try {
      if (modo === 'password') {
        st.user = await st.api.signInPassword(form.email.value, form.password.value);
        location.hash = '#/inicio';
        return;
      }
      await st.api.signInEmail(form.email.value);
      msg.innerHTML = '<div class="state state-ok">Enlace enviado. Ábrelo desde este mismo navegador.</div>';
    } catch (e) {
      msg.innerHTML = errorHtml(e, { retry: false, extra: e.signedIn ? '<button class="secondary" data-action="logout2">Cerrar sesión</button>' : '' });
      msg.querySelector('[data-action=logout2]')?.addEventListener('click', async () => { await st.api.signOut(); msg.innerHTML = ''; });
    } finally { botones.forEach((b) => { b.disabled = false; }); }
  }
  form.addEventListener('submit', (ev) => { ev.preventDefault(); ejecutar('password'); });
  form.querySelector('[data-modo=enlace]').addEventListener('click', () => ejecutar('enlace'));
}

// ---------- Inicio ----------
async function viewInicio() {
  const u = st.user;
  const main = shell(loadingHtml('Cargando resumen…'));
  try {
    const partes = await st.api.listPartes({});
    const n = (e) => partes.filter((p) => p.estado === e).length;
    const hoy = new Date().toISOString().slice(0, 10);
    const tieneHoy = partes.some((p) => p.fecha === hoy && p.operario === u.cod_ope);
    main.innerHTML = `
      <div class="page-head">
        <h1>Hola, ${esc(u.usuario)}</h1>
        ${tieneHoy ? '<span class="muted">Ya tienes parte de hoy.</span>' : '<a class="button" href="#/partes/nuevo">+ Crear parte de hoy</a>'}
      </div>
      <div class="kpis">
        ${ESTADOS.map((e) => `<a class="kpi kpi-${e.toLowerCase()}" href="#/partes?estado=${e}"><span>${e}</span><strong>${n(e)}</strong></a>`).join('')}
      </div>
      ${esGestor(u) && n('Cerrado') ? `<div class="state state-info">Hay <strong>${n('Cerrado')}</strong> parte(s) cerrados pendientes de revisión. <a href="#/partes?estado=Cerrado">Revisar ahora</a></div>` : ''}
      ${!esGestor(u) && n('Pendiente') ? `<div class="state state-info">Tienes <strong>${n('Pendiente')}</strong> parte(s) sin cerrar. Ciérralos cuando estén completos para que los revisen. <a href="#/partes?estado=Pendiente">Ver</a></div>` : ''}
      ${!esGestor(u) && n('Rechazado') ? `<div class="state state-info">Tienes <strong>${n('Rechazado')}</strong> parte(s) rechazados. <a href="#/partes?estado=Rechazado">Ver motivo</a></div>` : ''}
      <h2>Últimos partes</h2>
      ${tablaPartes(partes.slice(0, 5))}`;
  } catch (e) { showError(main, e, route); }
}

function tablaPartes(partes) {
  if (!partes.length) {
    return emptyHtml('No hay partes que mostrar.', '<a class="button" href="#/partes/nuevo">+ Nuevo parte</a>');
  }
  const gestor = esGestor(st.user);
  return `<div class="table-wrap"><table>
    <thead><tr><th>Nº</th><th>Fecha</th>${gestor ? '<th>Operario</th>' : ''}<th>Fincas</th><th>Horas</th><th>Líneas</th><th>Estado</th></tr></thead>
    <tbody>${partes.map((p) => `
      <tr class="clickable" data-href="#/partes/${esc(p.id_parte)}" tabindex="0">
        <td>${esc(p.num_parte)}</td><td>${fmtFecha(p.fecha)}</td>
        ${gestor ? `<td>${esc(nombreOperario(p.operario))}</td>` : ''}
        <td>${esc((p.fincas || []).map(nombreFinca).join(', ') || (p.mat_nave ? 'Nave' : '—'))}</td><td>${fmtHoras(p.tot_horas)}</td><td>${esc(p.n_lineas)}</td><td>${badge(p.estado)}</td>
      </tr>`).join('')}
    </tbody></table></div>`;
}

document.addEventListener('click', (ev) => {
  const tr = ev.target.closest('tr[data-href]');
  if (tr) location.hash = tr.dataset.href;
});
document.addEventListener('keydown', (ev) => {
  const tr = ev.target.closest?.('tr[data-href]');
  if (tr && ev.key === 'Enter') location.hash = tr.dataset.href;
});

// ---------- Lista con filtros ----------
async function viewLista(q) {
  const u = st.user;
  const gestor = esGestor(u);
  const main = shell(`
    <div class="page-head"><h1>${gestor ? 'Todos los partes' : 'Mis partes'}</h1>
      <a class="button" href="#/partes/nuevo">+ Nuevo parte</a></div>
    <form id="filtros" class="filters">
      <label>Estado <select name="estado"><option value="">Todos</option>${ESTADOS.map((e) => `<option ${q.estado === e ? 'selected' : ''}>${e}</option>`).join('')}</select></label>
      ${gestor ? `<label>Operario <select name="operario">${options(st.operarios, q.operario, 'cod_ope', (o) => o.usuario, 'Todos')}</select></label>` : ''}
      <label>Finca (en tareas) <select name="finca">${options(st.cat.fincas, q.finca, 'cod_fin', (f) => f.finca, 'Todas')}</select></label>
      <label>Desde <input type="date" name="desde" value="${esc(q.desde || '')}"></label>
      <label>Hasta <input type="date" name="hasta" value="${esc(q.hasta || '')}"></label>
      <a class="link" href="#/partes">Limpiar</a>
    </form>
    <div id="resultado">${loadingHtml('Cargando partes…')}</div>`);
  main.querySelector('#filtros').addEventListener('change', (ev) => {
    const data = Object.fromEntries([...new FormData(ev.currentTarget)].filter(([, v]) => v));
    location.hash = `#/partes?${new URLSearchParams(data)}`;
  });
  const res = main.querySelector('#resultado');
  try {
    const partes = await st.api.listPartes(q);
    const total = partes.reduce((s, p) => s + (Number(p.tot_horas) || 0), 0);
    res.innerHTML = `${partes.length ? `<p class="muted">${partes.length} parte(s) · ${fmtHoras(total)} en total</p>` : ''}${tablaPartes(partes)}`;
  } catch (e) { showError(res, e, () => viewLista(q)); }
}

// ---------- Detalle + revisión ----------
async function viewDetalle(id) {
  const u = st.user;
  const main = shell(loadingHtml('Cargando parte…'));
  let p;
  try { p = await st.api.getParte(id); } catch (e) { return showError(main, e, () => viewDetalle(id)); }

  const campo = (k, v) => `<div><dt>${k}</dt><dd>${v}</dd></div>`;
  main.innerHTML = `
    <a class="link" href="#/partes">← Volver a la lista</a>
    <div class="page-head">
      <h1>Parte nº ${esc(p.num_parte)} ${badge(p.estado)}</h1>
      <div class="row">
        ${puedeEditar(u, p) ? `<a class="button secondary" href="#/partes/${esc(p.id_parte)}/editar">Editar</a>` : ''}
        ${puedeCerrar(u, p) ? '<button type="button" id="b-cerrar">Cerrar parte</button>' : ''}
        ${puedeBorrar(u) ? '<button type="button" class="danger" id="b-borrar">Borrar</button>' : ''}
      </div>
    </div>
    <div id="acc-msg"></div>
    ${p.estado === 'Pendiente' && puedeCerrar(u, p) ? `<div class="state state-info">Cuando el parte esté completo, ciérralo para que lo revisen. <strong>Una vez cerrado ya no se puede reabrir</strong>${esGestor(u) ? '' : ' ni editar'}.</div>` : ''}
    ${p.estado === 'Rechazado' && p.comentario_supervisor ? `<div class="state state-error"><strong>Motivo del rechazo:</strong> ${esc(p.comentario_supervisor)}</div>` : ''}
    <section class="card"><h2>Jornada</h2><dl class="grid">
      ${campo('Operario', esc(nombreOperario(p.operario)))}
      ${campo('Fecha', fmtFecha(p.fecha))}
      ${campo('Entrada / salida', `${esc(p.h_ent)} – ${esc(p.h_sal)}`)}
      ${campo('Almuerzo / comida', `${esc(p.t_alm_min)} / ${esc(p.t_com_min)} min`)}
      ${campo('Total horas', `<strong>${fmtHoras(p.tot_horas)}</strong>`)}
      ${campo('Horas extra', `${fmtHoras(p.h_ext)}${p.h_ext_manual ? ' <span class="muted">(corregidas a mano)</span>' : ''}`)}
      ${campo('Horas de tareas', `${fmtHoras(p.ht_tareas ?? calcHtTareas(p.lineas, st.cat))} <span class="muted">(sin motivos personales)</span>`)}
      ${campo('Mant. nave', p.mat_nave ? 'Sí' : 'No')}
      ${campo('Observaciones', esc(p.obs || '—'))}
    </dl></section>
    <section class="card"><h2>Tareas realizadas (${p.lineas.length})</h2>
      ${p.lineas.length ? `<div class="table-wrap"><table>
        <thead><tr><th>Tarea</th><th>Finca</th><th>Parcela</th><th>Vehículo</th><th>Apero</th><th>Horario</th><th>Horas</th><th>Fin de vuelta</th><th>Obs.</th></tr></thead>
        <tbody>${ordenarLineas(p.lineas).map((l) => `<tr>
          <td>${esc(nombreTarea(l.tarea))}</td><td>${esc(nombreFinca(l.finca))}</td><td>${esc(nombreParcela(l.parcela))}</td>
          <td>${esc(nombreVehiculo(l.vehiculo))}</td><td>${esc(nombreApero(l.apero))}</td>
          <td>${esc(l.h_ini)}–${esc(l.h_fin)}</td><td>${fmtHoras(l.t_horas ?? calcHoras(l.h_ini, l.h_fin))}</td>
          <td>${requiereFinVuelta(l, st.cat) && l.fin_vuelta == null
            ? '<strong class="pendiente">Sin responder</strong>' : esc(textoFinVuelta(l, st.cat))}</td>
          <td>${esc(l.obs || '')}</td></tr>`).join('')}
        </tbody></table></div>` : emptyHtml('Este parte no tiene líneas de tarea.')}
    </section>
    <section class="card"><h2>Cierre y revisión</h2><dl class="grid">
      ${campo('Cerrado por', esc(p.cerrado_por ? nombreOperario(p.cerrado_por) : '—'))}
      ${campo('Fecha cierre', fmtFechaHora(p.fecha_cierre))}
      ${campo('Revisado por', esc(p.supervisor_revisa ? nombreOperario(p.supervisor_revisa) : '—'))}
      ${campo('Fecha revisión', fmtFechaHora(p.fecha_revision))}
      ${campo('Creado', `${fmtFechaHora(p.fch_creacion)} · ${esc(p.creado_por || '')}`)}
      ${campo('Última modificación', fmtFechaHora(p.fch_modificacion))}
    </dl>
    ${puedeRevisar(u, p) ? `
      <form id="f-revision" class="stack">
        <label>Comentario del supervisor <span class="muted">(obligatorio para rechazar)</span>
          <textarea name="comentario" rows="2"></textarea></label>
        <div class="row">
          <button type="button" data-estado="Aprobado">Aprobar</button>
          <button type="button" class="danger" data-estado="Rechazado">Rechazar</button>
        </div>
        <div id="rev-msg"></div>
      </form>` : ''}
    ${esGestor(u) && p.estado === 'Pendiente' ? '<p class="muted">Para aprobar o rechazar, el parte tiene que estar cerrado.</p>' : ''}
    ${u.rol_app === 'SUPERVISOR' && p.estado === 'Cerrado' && p.operario === u.cod_ope ? '<p class="muted">Tus propios partes los revisa un ADMIN.</p>' : ''}
    </section>`;

  const accMsg = main.querySelector('#acc-msg');
  main.querySelector('#b-cerrar')?.addEventListener('click', async (ev) => {
    const err = errorCierre(p, p.lineas.length) || errorFinVuelta(p.lineas, st.cat);
    if (err) { accMsg.innerHTML = errorHtml(new Error(err), { retry: false }); return; }
    const b = ev.currentTarget;
    if (!confirm(`¿Cerrar el parte nº ${p.num_parte}? Después no se podrá reabrir${esGestor(u) ? '' : ' ni editar'}.`)) return;
    b.disabled = true;
    try {
      await st.api.cerrarParte(p.id_parte);
      toast(`Parte nº ${p.num_parte} cerrado.`);
      viewDetalle(id);
    } catch (e) {
      accMsg.innerHTML = errorHtml(e, { retry: false });
      b.disabled = false;
    }
  });
  main.querySelector('#b-borrar')?.addEventListener('click', async (ev) => {
    const b = ev.currentTarget;
    if (!confirm(`¿Borrar definitivamente el parte nº ${p.num_parte} (${p.estado}) y sus ${p.lineas.length} tarea(s)? Quedará una copia en la auditoría.`)) return;
    b.disabled = true;
    try {
      await st.api.borrarParte(p.id_parte);
      toast(`Parte nº ${p.num_parte} borrado.`);
      location.hash = '#/partes';
    } catch (e) {
      accMsg.innerHTML = errorHtml(e, { retry: false });
      b.disabled = false;
    }
  });

  main.querySelectorAll('#f-revision [data-estado]').forEach((b) => b.addEventListener('click', async () => {
    const estado = b.dataset.estado;
    const comentario = main.querySelector('[name=comentario]').value;
    const msg = main.querySelector('#rev-msg');
    if (estado === 'Rechazado' && !comentario.trim()) {
      msg.innerHTML = errorHtml(new Error('Escribe el motivo del rechazo.'), { retry: false });
      return;
    }
    main.querySelectorAll('#f-revision button').forEach((x) => { x.disabled = true; });
    try {
      await st.api.revisarParte(p.id_parte, estado, comentario);
      toast(`Parte nº ${p.num_parte} ${estado.toLowerCase()}.`);
      viewDetalle(id);
    } catch (e) {
      msg.innerHTML = errorHtml(e, { retry: false });
      main.querySelectorAll('#f-revision button').forEach((x) => { x.disabled = false; });
    }
  }));
}

// ---------- Nuevo / editar parte (cabecera + líneas) ----------
async function viewForm(id) {
  const u = st.user;
  const main = shell(loadingHtml('Preparando formulario…'));
  let p = null;
  if (id) {
    try { p = await st.api.getParte(id); } catch (e) { return showError(main, e, () => viewForm(id)); }
    if (!puedeEditar(u, p)) {
      main.innerHTML = errorHtml(new Error(motivoNoEditable(u, p)), {
        retry: false, extra: `<a class="button secondary" href="#/partes/${esc(id)}">Ver parte</a>`,
      });
      return;
    }
  }
  // Valores iniciales (012): se proponen al crear y se usan si un campo se deja vacío.
  let ini = VALORES_INICIALES;
  try { ini = (await st.api.getValoresIniciales()) || ini; } catch { /* se usan los de rules.js */ }
  const cab = p || {
    operario: u.cod_ope, fecha: new Date().toISOString().slice(0, 10), h_ent: ini.h_ent, h_sal: ini.h_sal,
    t_alm_min: ini.t_alm_min, t_com_min: ini.t_com_min, h_ext: 0, h_ext_manual: false, mat_nave: false, obs: '',
  };
  const { cat } = st;
  // Horas extra (011): las calcula la BD. Solo el ADMIN ve th_jornada y puede corregirlas a mano.
  const esAdmin = u.rol_app === 'ADMIN';
  let th = null;
  if (esAdmin) { try { th = await st.api.getThJornada(); } catch { th = null; } }
  // Parte nuevo: se propone una primera línea de DESPLAZAMIENTO que empieza a la hora de entrada.
  const desplazamiento = cat.tareas.find((t) => t.tipo === TIPO_DESPLAZAMIENTO && t.activo !== false);
  const lineas = p ? ordenarLineas(p.lineas) : [{ tarea: desplazamiento?.cod_tar || '', h_ini: cab.h_ent }];
  const puedeElegirOperario = !id && puedeCrearParaOtros(u);  // ADMIN y SUPERVISOR (013)

  main.innerHTML = `
    <a class="link" href="${id ? `#/partes/${esc(id)}` : '#/partes'}">← Cancelar</a>
    <h1>${id ? `Editar parte nº ${esc(p.num_parte)}` : 'Nuevo parte'}</h1>
    <form id="f-parte" novalidate>
      <section class="card"><h2>Jornada</h2><div class="form-grid">
        <label>Operario ${puedeElegirOperario
          ? `<select name="operario">${options(st.operarios.filter((o) => o.activo), cab.operario, 'cod_ope', (o) => o.usuario)}</select>`
          : `<input value="${esc(nombreOperario(cab.operario))}" disabled><input type="hidden" name="operario" value="${esc(cab.operario)}">`}</label>
        <label>Fecha <input type="date" name="fecha" value="${esc(cab.fecha)}" required></label>
        <label>Hora entrada <input type="time" step="900" name="h_ent" value="${esc(cab.h_ent)}"></label>
        <label>Hora salida <input type="time" step="900" name="h_sal" value="${esc(cab.h_sal)}"></label>
        <label>Almuerzo (min) <input type="number" min="0" step="15" name="t_alm_min" value="${esc(cab.t_alm_min)}" placeholder="${esc(ini.t_alm_min)}"></label>
        <label>Comida (min) <input type="number" min="0" step="15" name="t_com_min" value="${esc(cab.t_com_min)}" placeholder="${esc(ini.t_com_min)}"></label>
        <p class="muted wide">Si dejas vacía la entrada, la salida, el almuerzo o la comida, se usa el valor por defecto:
          ${esc(ini.h_ent)} – ${esc(ini.h_sal)}, ${esc(ini.t_alm_min)} min de almuerzo y ${esc(ini.t_com_min)} de comida.
          Si no has parado, escribe 0.</p>
        ${esAdmin ? `
        <label>Horas extra <input type="number" min="0" step="0.25" name="h_ext" value="${esc(cab.h_ext)}" ${cab.h_ext_manual ? '' : 'disabled'}>
          <span class="muted" id="hext-auto"></span></label>
        <label class="check"><input type="checkbox" name="h_ext_manual" ${cab.h_ext_manual ? 'checked' : ''}> Corregir horas extra a mano</label>`
        : `<label>Horas extra <input value="${id ? esc(fmtHoras(cab.h_ext)) : ''}" placeholder="Se calculan al guardar" disabled>
          <span class="muted">Las calcula el sistema según la jornada.</span></label>`}
        <label class="check"><input type="checkbox" name="mat_nave" ${cab.mat_nave ? 'checked' : ''}> Mantenimiento nave</label>
        <label class="wide">Observaciones <textarea name="obs" rows="2">${esc(cab.obs || '')}</textarea></label>
      </div>
      <p class="total">Total jornada: <strong id="tot">—</strong></p></section>

      <section class="card"><div class="page-head"><h2>Tareas realizadas</h2>
        <button type="button" class="secondary" id="add-linea">+ Añadir tarea</button></div>
        <p class="muted">Horas en intervalos de 15 minutos. La primera tarea (sin contar MOTIVOS PERSONALES) es un
          DESPLAZAMIENTO con finca y vehículo; para cambiar de finca, añade otro DESPLAZAMIENTO.
          Las tareas se ordenan por hora de inicio y no pueden solaparse.</p>
        <div id="lineas"></div>
        <p class="muted" id="sin-lineas">Aún no hay tareas.</p>
      </section>

      <div id="form-msg"></div>
      <div class="row sticky-actions"><button type="submit" id="guardar">${id ? 'Guardar cambios' : 'Crear parte'}</button></div>
    </form>`;

  const form = main.querySelector('#f-parte');
  const cont = main.querySelector('#lineas');

  const parcelasDe = (finca) => cat.parcelas.filter((x) => !finca || x.finca === finca);
  const etiquetaParcela = (x) => `${x.nom_parc} (${x.superficie ?? '?'} ha)`;
  function lineaHtml(l = {}) {
    const finca = l.finca || '';
    return `<fieldset class="linea">
      <label>Tarea <select name="tarea">${options(cat.tareas, l.tarea, 'cod_tar', (t) => `${t.tareas} (${etiquetaTipo(t.tipo)})`)}</select></label>
      <label data-campo>Finca <select name="l_finca">${options(cat.fincas, finca, 'cod_fin', (f) => f.finca)}</select></label>
      <label data-campo>Parcela <select name="parcela">${options(parcelasDe(finca), l.parcela, 'cod_par', etiquetaParcela, '— Sin parcela —')}</select></label>
      <label data-campo><span class="lbl-veh">Vehículo</span> <select name="l_vehiculo">${options(cat.vehiculos, l.vehiculo, 'id_mat', (v) => `${v.alias} · ${v.equipo}`, '— Ninguno —')}</select></label>
      <label data-campo>Apero <select name="apero">${options(cat.aperos, l.apero, 'id_bas', (a) => `${a.alias} · ${a.equipo}`, '— Ninguno —')}</select></label>
      <label data-vuelta>Fin de vuelta <select name="fin_vuelta">
        <option value="" ${l.fin_vuelta == null ? 'selected' : ''}>— Sin responder —</option>
        <option value="true" ${l.fin_vuelta === true ? 'selected' : ''}>Sí, termina la vuelta</option>
        <option value="false" ${l.fin_vuelta === false ? 'selected' : ''}>No</option></select></label>
      <label>Inicio <input type="time" step="900" name="h_ini" value="${esc(l.h_ini || '')}"></label>
      <label>Fin <input type="time" step="900" name="h_fin" value="${esc(l.h_fin || '')}"></label>
      <label class="wide">Obs. <input name="l_obs" value="${esc(l.obs || '')}"></label>
      <input type="hidden" name="id_linea" value="${esc(l.id_linea || '')}">
      <button type="button" class="link danger quitar">Quitar</button>
    </fieldset>`;
  }
  // Campos según el tipo de tarea: MOTIVOS PERSONALES solo lleva horas; DESPLAZAMIENTO exige vehículo.
  function aplicarTipo(fs) {
    const tipo = tipoTarea(cat, fs.querySelector('[name=tarea]').value);
    const personal = tipo === TIPO_PERSONAL;
    fs.querySelectorAll('[data-campo]').forEach((lab) => {
      lab.hidden = personal;
      if (personal) lab.querySelector('select').value = '';
    });
    fs.querySelector('.lbl-veh').textContent = tipo === TIPO_DESPLAZAMIENTO ? 'Vehículo (obligatorio)' : 'Vehículo';
    // Fin de vuelta (014): solo en tareas con parcela y de tipo POR SUPERFICIE o POR HORAS.
    fs.querySelector('[data-vuelta]').hidden = !requiereFinVuelta(
      { tarea: fs.querySelector('[name=tarea]').value, parcela: fs.querySelector('[name=parcela]').value }, cat);
  }
  const leerLineas = () => [...cont.querySelectorAll('.linea')].map((f) => {
    const v = (n) => f.querySelector(`[name=${n}]`).value;
    const personal = tipoTarea(cat, v('tarea')) === TIPO_PERSONAL;
    const opcional = (n) => (personal ? null : v(n) || null);
    const l = { id_linea: v('id_linea') || null, tarea: v('tarea'), finca: opcional('l_finca'), parcela: opcional('parcela'),
      vehiculo: opcional('l_vehiculo'), apero: opcional('apero'), h_ini: v('h_ini'), h_fin: v('h_fin'), obs: v('l_obs') };
    // Sí / No / sin responder; en las tareas a las que no se aplica, No (como la BD).
    const fv = v('fin_vuelta');
    l.fin_vuelta = requiereFinVuelta(l, cat) ? (fv === 'true' ? true : fv === 'false' ? false : null) : false;
    return l;
  });
  // Valores propuestos para una línea nueva (se pueden cambiar): empieza cuando acaba la última tarea
  // y repite finca, vehículo y apero de la última tarea que los tenga.
  function propuestaSiguiente() {
    const orden = ordenarLineas(leerLineas().filter((l) => l.h_ini));
    const ultima = orden[orden.length - 1];
    const conFinca = [...orden].reverse().find((l) => l.finca);
    return { h_ini: ultima?.h_fin || '', finca: conFinca?.finca, vehiculo: conFinca?.vehiculo, apero: conFinca?.apero };
  }
  const addLinea = (l) => {
    cont.insertAdjacentHTML('beforeend', lineaHtml(l));
    aplicarTipo(cont.lastElementChild);
    refrescar();
  };
  function refrescar() {
    const datos = conValoresIniciales(Object.fromEntries(new FormData(form)), ini);
    const tot = calcTotHoras(datos);
    main.querySelector('#tot').textContent = fmtHoras(tot);
    if (esAdmin) {
      const manual = form.h_ext_manual.checked;
      const auto = calcHExt(datos, th);
      form.h_ext.disabled = !manual;
      if (!manual && auto != null) form.h_ext.value = auto;
      main.querySelector('#hext-auto').textContent = th == null ? 'Se calculan al guardar.'
        : `Calculadas: ${fmtHoras(auto)} (jornada de ${fmtHoras(th)})`;
    }
    main.querySelector('#sin-lineas').hidden = cont.children.length > 0;
  }

  lineas.forEach(addLinea);
  refrescar();

  main.querySelector('#add-linea').addEventListener('click', () => addLinea(propuestaSiguiente()));
  cont.addEventListener('click', (ev) => {
    if (ev.target.classList.contains('quitar')) { ev.target.closest('.linea').remove(); refrescar(); }
  });
  cont.addEventListener('change', (ev) => {
    const fs = ev.target.closest('.linea');
    // Parcela dependiente de la finca de la línea
    if (ev.target.name === 'l_finca') {
      fs.querySelector('[name=parcela]').innerHTML = options(parcelasDe(ev.target.value), '', 'cod_par', etiquetaParcela, '— Sin parcela —');
    }
    if (['tarea', 'l_finca', 'parcela'].includes(ev.target.name)) aplicarTipo(fs);
  });
  form.addEventListener('input', refrescar);

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = Object.fromEntries(new FormData(form));
    const nuevaCab = {
      // Vacío se envía vacío: la BD pone el valor de la configuración (012).
      operario: fd.operario, fecha: fd.fecha, h_ent: fd.h_ent || null, h_sal: fd.h_sal || null,
      t_alm_min: fd.t_alm_min === '' ? null : Number(fd.t_alm_min),
      t_com_min: fd.t_com_min === '' ? null : Number(fd.t_com_min),
      mat_nave: form.mat_nave.checked, obs: fd.obs,
    };
    // Solo el ADMIN envía horas extra corregidas; para el resto la BD las calcula.
    if (esAdmin) {
      nuevaCab.h_ext_manual = form.h_ext_manual.checked;
      if (nuevaCab.h_ext_manual) nuevaCab.h_ext = Number(form.h_ext.value) || 0;
    }
    const nuevasLineas = leerLineas();
    const msg = main.querySelector('#form-msg');
    // Se valida con los valores que guardará la BD (los vacíos ya sustituidos).
    const errores = validarParte(conValoresIniciales(nuevaCab, ini), nuevasLineas, cat);
    const sinTareas = errorSinTareas(p?.estado, nuevaCab.mat_nave, nuevasLineas.length);
    if (sinTareas) errores.push(`${sinTareas}.`);
    // Un parte ya cerrado no puede quedar con tareas sin responder (014). En Pendiente se permite.
    const sinResponder = p && p.estado !== 'Pendiente'
      ? errorFinVuelta(nuevasLineas, cat, `El parte está ${p.estado}: indica si termina la vuelta en`) : null;
    if (sinResponder) errores.push(`${sinResponder}.`);
    if (errores.length) {
      msg.innerHTML = `<div class="state state-error" role="alert"><strong>Revisa el formulario:</strong><ul>${errores.map((e) => `<li>${esc(e)}</li>`).join('')}</ul></div>`;
      msg.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    const btn = main.querySelector('#guardar');
    btn.disabled = true; btn.textContent = 'Guardando…'; msg.innerHTML = '';
    try {
      const nuevoId = await st.api.saveParte({ id_parte: id, cab: nuevaCab, lineas: nuevasLineas });
      toast(id ? 'Cambios guardados.' : 'Parte creado. Queda pendiente de revisión.');
      location.hash = `#/partes/${nuevoId}`;
    } catch (e) {
      msg.innerHTML = errorHtml(e, { retry: false });
      btn.disabled = false; btn.textContent = id ? 'Guardar cambios' : 'Crear parte';
    }
  });
}

// ---------- Vueltas, exportaciones y archivo (migración 015) ----------
const ayer = () => { const d = new Date(); d.setDate(d.getDate() - 1); return d.toISOString().slice(0, 10); };

function descargarCsv(nombre, filas, columnas) {
  const url = URL.createObjectURL(new Blob([aCsv(filas, columnas)], { type: 'text/csv;charset=utf-8' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: nombre });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const COLS_VUELTAS = [
  ['campana', 'Campaña'], ['finca', 'Finca'], ['parcela', 'Parcela'], ['nom_parcela', 'Nombre parcela'],
  ['tarea', 'Tarea'], ['nom_tarea', 'Nombre tarea'], ['num_vuelta', 'Vuelta'], ['estado', 'Estado'],
  ['fecha_inicio', 'Inicio'], ['fecha_fin', 'Fin'], ['operario_fin', 'Operario que la termina'],
  ['horas', 'Horas'], ['registros', 'Registros'], ['operarios', 'Operarios'], ['incluye_sin_archivar', 'Con partes sin archivar'],
];
const COLS_TAREAS = [
  ['campana', 'Campaña'], ['operario', 'Operario'], ['fec_tarea', 'Fecha'], ['tarea', 'Tarea'], ['nom_tarea', 'Nombre tarea'],
  ['finca', 'Finca'], ['parcela', 'Parcela'], ['vehiculo', 'Vehículo'], ['apero', 'Apero'], ['fin_vuelta', 'Fin de vuelta'],
  ['horas', 'Horas'], ['num_parte', 'Parte'], ['origen', 'Origen'],
];
const COLS_HORAS = [
  ['parte', 'Parte'], ['operario', 'Operario'], ['nombre', 'Nombre'], ['fecha', 'Fecha'], ['h_ent', 'Entrada'], ['h_sal', 'Salida'],
  ['t_alm_min', 'Almuerzo (min)'], ['t_com_min', 'Comida (min)'], ['estado', 'Estado'],
];

async function viewArchivo(q) {
  const u = st.user;
  const admin = u.rol_app === 'ADMIN';
  const main = shell(loadingHtml('Cargando vueltas…'));
  let vueltas;
  let archivos;
  try {
    [vueltas, archivos] = await Promise.all([st.api.listVueltas({}), st.api.listArchivos()]);
  } catch (e) { return showError(main, e, () => viewArchivo(q)); }

  const campanas = [...new Set(vueltas.map((v) => v.campana))].sort().reverse();
  const lista = vueltas.filter((v) => (!q.campana || v.campana === q.campana) && (!q.estado || v.estado === q.estado));
  const ult = archivos[0]?.hasta || null;

  main.innerHTML = `
    <div class="page-head"><h1>Vueltas y archivo</h1></div>

    <section class="card"><div class="page-head"><h2>Vueltas por parcela y tarea</h2>
        <button type="button" class="secondary" id="b-csv-vueltas" ${lista.length ? '' : 'disabled'}>Exportar CSV</button></div>
      <p class="muted">Solo cuentan los partes Aprobados (archivados o no). Una vuelta se cierra con la tarea marcada como fin de vuelta;
        cada campaña empieza de cero.</p>
      <form id="f-vueltas" class="filters">
        <label>Campaña <select name="campana"><option value="">Todas</option>${campanas.map((c) => `<option ${q.campana === c ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select></label>
        <label>Estado <select name="estado"><option value="">Todos</option>${['Abierta', 'Cerrada'].map((e) => `<option ${q.estado === e ? 'selected' : ''}>${e}</option>`).join('')}</select></label>
        <a class="link" href="#/archivo">Limpiar</a>
      </form>
      ${lista.length ? `<div class="table-wrap"><table>
        <thead><tr><th>Campaña</th><th>Parcela</th><th>Tarea</th><th>Vuelta</th><th>Estado</th><th>Inicio</th><th>Fin</th>
          <th>Termina</th><th>Horas</th><th>Registros</th></tr></thead>
        <tbody>${lista.map((v) => `<tr>
          <td>${esc(v.campana)}</td><td>${esc(v.nom_parcela || nombreParcela(v.parcela))}<br><span class="muted">${esc(nombreFinca(v.finca))}</span></td>
          <td>${esc(v.nom_tarea || nombreTarea(v.tarea))}</td><td>${esc(v.num_vuelta)}</td>
          <td><span class="badge badge-${v.estado === 'Cerrada' ? 'aprobado' : 'pendiente'}">${esc(v.estado)}</span>${v.incluye_sin_archivar ? '<br><span class="muted">con partes sin archivar</span>' : ''}</td>
          <td>${fmtFecha(v.fecha_inicio)}</td><td>${fmtFecha(v.fecha_fin)}</td><td>${esc(v.operario_fin ? nombreOperario(v.operario_fin) : '—')}</td>
          <td>${fmtHoras(v.horas)}</td><td>${esc(v.registros)}</td></tr>`).join('')}
        </tbody></table></div>` : emptyHtml('No hay vueltas: aún no hay partes Aprobados con tareas por parcela.')}
    </section>

    <section class="card"><h2>Exportar por fechas</h2>
      <p class="muted"><strong>Horas por trabajador</strong> (para comparar con los fichajes) solo está mientras los partes no se archivan:
        expórtalo antes de archivar. <strong>Tareas realizadas</strong> incluye el archivo y los partes Aprobados sin archivar.</p>
      <form id="f-export" class="filters">
        <label>Desde <input type="date" name="desde"></label>
        <label>Hasta <input type="date" name="hasta"></label>
        <button type="button" class="secondary" data-export="horas">Horas por trabajador (CSV)</button>
        <button type="button" class="secondary" data-export="tareas">Tareas realizadas (CSV)</button>
      </form>
    </section>

    <section class="card"><h2>Archivar partes</h2>
      ${ult ? `<p>Archivado hasta el <strong>${fmtFecha(ult)}</strong>. No se pueden crear ni modificar partes de esas fechas.</p>` : '<p>Aún no se ha archivado nada.</p>'}
      ${admin ? `<p class="muted">Pasa al archivo las tareas de los partes Aprobados hasta la fecha elegida y borra esos partes.
          Los Rechazados se borran sin archivar (queda su copia en la auditoría). No se puede archivar si queda algún parte Pendiente o Cerrado.</p>
        <form id="f-archivar" class="filters">
          <label>Archivar hasta <input type="date" name="hasta" required max="${ayer()}" ${ult ? `min="${ult}"` : ''}></label>
          <button type="submit" class="danger">Archivar</button>
        </form>
        <div id="archivar-msg"></div>` : '<p class="muted">Solo un ADMIN puede archivar.</p>'}
      ${archivos.length ? `<div class="table-wrap"><table>
        <thead><tr><th>Hasta</th><th>Fecha</th><th>Por</th><th>Partes</th><th>Tareas</th><th>Filas archivo</th><th>Rechazados borrados</th></tr></thead>
        <tbody>${archivos.map((a) => `<tr><td>${fmtFecha(a.hasta)}</td><td>${fmtFechaHora(a.fecha)}</td><td>${esc(nombreOperario(a.archivado_por))}</td>
          <td>${esc(a.partes)}</td><td>${esc(a.lineas)}</td><td>${esc(a.filas)}</td><td>${esc(a.rechazados)}</td></tr>`).join('')}
        </tbody></table></div>` : ''}
    </section>`;

  main.querySelector('#f-vueltas').addEventListener('change', (ev) => {
    const data = Object.fromEntries([...new FormData(ev.currentTarget)].filter(([, v]) => v));
    location.hash = `#/archivo?${new URLSearchParams(data)}`;
  });
  main.querySelector('#b-csv-vueltas').addEventListener('click', () => {
    descargarCsv(`vueltas${q.campana ? `_${q.campana.replace('/', '-')}` : ''}.csv`, lista, COLS_VUELTAS);
  });

  main.querySelectorAll('[data-export]').forEach((b) => b.addEventListener('click', async () => {
    const f = Object.fromEntries(new FormData(main.querySelector('#f-export')));
    const sufijo = `${f.desde || 'inicio'}_${f.hasta || 'hoy'}`;
    b.disabled = true;
    try {
      if (b.dataset.export === 'horas') {
        const filas = (await st.api.listHorasTrabajador(f)).map((r) => ({ ...r, nombre: nombreOperario(r.operario) }));
        if (!filas.length) return toast('No hay partes en esas fechas.', 'error');
        descargarCsv(`horas_trabajador_${sufijo}.csv`, filas, COLS_HORAS);
      } else {
        const filas = await st.api.listTareasResumen(f);
        if (!filas.length) return toast('No hay tareas en esas fechas.', 'error');
        descargarCsv(`tareas_realizadas_${sufijo}.csv`, filas, COLS_TAREAS);
      }
    } catch (e) { toast(e.message, 'error'); } finally { b.disabled = false; }
  }));

  main.querySelector('#f-archivar')?.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const hasta = ev.currentTarget.hasta.value;
    const msg = main.querySelector('#archivar-msg');
    if (!confirm(`¿Archivar los partes hasta el ${fmtFecha(hasta)}?\n\nSe borrarán esos partes (los Aprobados pasan al archivo). `
      + 'Exporta antes las horas por trabajador si las necesitas. No se puede deshacer.')) return;
    const boton = ev.currentTarget.querySelector('button');
    boton.disabled = true;
    msg.innerHTML = loadingHtml('Archivando…');
    try {
      const r = await st.api.archivarPartes(hasta);
      toast(`Archivado hasta el ${fmtFecha(r.hasta)}: ${r.partes} parte(s), ${r.filas} fila(s) en el archivo, ${r.rechazados} rechazado(s) borrados.`);
      viewArchivo(q);
    } catch (e) {
      msg.innerHTML = errorHtml(e, { retry: false });
      boton.disabled = false;
    }
  });
}
