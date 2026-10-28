// Boceto funcional "Partes de Trabajo". Navegación por hash:
//   #/login · #/inicio · #/partes?filtros · #/partes/nuevo · #/partes/:id · #/partes/:id/editar
import { createApi } from './data/index.js';
import { esc, fmtFecha, fmtFechaHora, fmtHoras, badge, loadingHtml, emptyHtml, errorHtml, toast, options } from './ui.js';
import { ESTADOS, esGestor, puedeEditar, motivoNoEditable, puedeRevisar, calcHoras, calcTotHoras, validarParte } from './rules.js';

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
      ${esGestor(u) && n('Pendiente') ? `<div class="state state-info">Hay <strong>${n('Pendiente')}</strong> parte(s) pendientes de revisión. <a href="#/partes?estado=Pendiente">Revisar ahora</a></div>` : ''}
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
    <thead><tr><th>Nº</th><th>Fecha</th>${gestor ? '<th>Operario</th>' : ''}<th>Finca</th><th>Horas</th><th>Líneas</th><th>Estado</th></tr></thead>
    <tbody>${partes.map((p) => `
      <tr class="clickable" data-href="#/partes/${esc(p.id_parte)}" tabindex="0">
        <td>${esc(p.num_parte)}</td><td>${fmtFecha(p.fecha)}</td>
        ${gestor ? `<td>${esc(nombreOperario(p.operario))}</td>` : ''}
        <td>${esc(nombreFinca(p.finca))}</td><td>${fmtHoras(p.tot_horas)}</td><td>${esc(p.n_lineas)}</td><td>${badge(p.estado)}</td>
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
      <label>Finca <select name="finca">${options(st.cat.fincas, q.finca, 'cod_fin', (f) => f.finca, 'Todas')}</select></label>
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
      ${puedeEditar(u, p) ? `<a class="button secondary" href="#/partes/${esc(p.id_parte)}/editar">Editar</a>` : ''}
    </div>
    ${p.estado === 'Rechazado' && p.comentario_supervisor ? `<div class="state state-error"><strong>Motivo del rechazo:</strong> ${esc(p.comentario_supervisor)}</div>` : ''}
    <section class="card"><h2>Jornada</h2><dl class="grid">
      ${campo('Operario', esc(nombreOperario(p.operario)))}
      ${campo('Fecha', fmtFecha(p.fecha))}
      ${campo('Entrada / salida', `${esc(p.h_ent)} – ${esc(p.h_sal)}`)}
      ${campo('Almuerzo / comida', `${esc(p.t_alm_min)} / ${esc(p.t_com_min)} min`)}
      ${campo('Total horas', `<strong>${fmtHoras(p.tot_horas)}</strong>`)}
      ${campo('Horas extra', fmtHoras(p.h_ext))}
      ${campo('Mant. nave', p.mat_nave ? 'Sí' : 'No')}
      ${campo('Finca', esc(nombreFinca(p.finca)))}
      ${campo('Vehículo', esc(nombreVehiculo(p.vehiculo)))}
      ${campo('Observaciones', esc(p.obs || '—'))}
    </dl></section>
    <section class="card"><h2>Tareas realizadas (${p.lineas.length})</h2>
      ${p.lineas.length ? `<div class="table-wrap"><table>
        <thead><tr><th>Tarea</th><th>Finca</th><th>Parcela</th><th>Vehículo</th><th>Apero</th><th>Horario</th><th>Horas</th><th>Obs.</th></tr></thead>
        <tbody>${p.lineas.map((l) => `<tr>
          <td>${esc(nombreTarea(l.tarea))}</td><td>${esc(nombreFinca(l.finca))}</td><td>${esc(nombreParcela(l.parcela))}</td>
          <td>${esc(nombreVehiculo(l.vehiculo))}</td><td>${esc(nombreApero(l.apero))}</td>
          <td>${esc(l.h_ini)}–${esc(l.h_fin)}</td><td>${fmtHoras(l.t_horas ?? calcHoras(l.h_ini, l.h_fin))}</td><td>${esc(l.obs || '')}</td></tr>`).join('')}
        </tbody></table></div>` : emptyHtml('Este parte no tiene líneas de tarea.')}
    </section>
    <section class="card"><h2>Revisión</h2><dl class="grid">
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
    </section>`;

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
      await st.api.setEstado(p.id_parte, estado, comentario);
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
  const cab = p || {
    operario: u.cod_ope, fecha: new Date().toISOString().slice(0, 10), h_ent: '07:30', h_sal: '16:00',
    t_alm_min: 30, t_com_min: 0, h_ext: 0, mat_nave: false, finca: '', vehiculo: '', obs: '',
  };
  const lineas = p ? p.lineas : [];
  const puedeElegirOperario = !id && u.rol_app === 'ADMIN';
  const { cat } = st;

  main.innerHTML = `
    <a class="link" href="${id ? `#/partes/${esc(id)}` : '#/partes'}">← Cancelar</a>
    <h1>${id ? `Editar parte nº ${esc(p.num_parte)}` : 'Nuevo parte'}</h1>
    <form id="f-parte" novalidate>
      <section class="card"><h2>Jornada</h2><div class="form-grid">
        <label>Operario ${puedeElegirOperario
          ? `<select name="operario">${options(st.operarios.filter((o) => o.activo), cab.operario, 'cod_ope', (o) => o.usuario)}</select>`
          : `<input value="${esc(nombreOperario(cab.operario))}" disabled><input type="hidden" name="operario" value="${esc(cab.operario)}">`}</label>
        <label>Fecha <input type="date" name="fecha" value="${esc(cab.fecha)}" required></label>
        <label>Hora entrada <input type="time" name="h_ent" value="${esc(cab.h_ent)}" required></label>
        <label>Hora salida <input type="time" name="h_sal" value="${esc(cab.h_sal)}" required></label>
        <label>Almuerzo (min) <input type="number" min="0" step="5" name="t_alm_min" value="${esc(cab.t_alm_min)}"></label>
        <label>Comida (min) <input type="number" min="0" step="5" name="t_com_min" value="${esc(cab.t_com_min)}"></label>
        <label>Horas extra <input type="number" min="0" step="0.25" name="h_ext" value="${esc(cab.h_ext)}"></label>
        <label class="check"><input type="checkbox" name="mat_nave" ${cab.mat_nave ? 'checked' : ''}> Mantenimiento nave</label>
        <label>Finca <select name="finca" required>${options(cat.fincas, cab.finca, 'cod_fin', (f) => f.finca)}</select></label>
        <label>Vehículo <select name="vehiculo">${options(cat.vehiculos, cab.vehiculo, 'id_mat', (v) => `${v.alias} · ${v.equipo}`, '— Ninguno —')}</select></label>
        <label class="wide">Observaciones <textarea name="obs" rows="2">${esc(cab.obs || '')}</textarea></label>
      </div>
      <p class="total">Total jornada: <strong id="tot">—</strong></p></section>

      <section class="card"><div class="page-head"><h2>Tareas realizadas</h2>
        <button type="button" class="secondary" id="add-linea">+ Añadir tarea</button></div>
        <div id="lineas"></div>
        <p class="muted" id="sin-lineas">Aún no hay tareas. Añade al menos una para detallar la jornada.</p>
      </section>

      <div id="form-msg"></div>
      <div class="row sticky-actions"><button type="submit" id="guardar">${id ? 'Guardar cambios' : 'Crear parte'}</button></div>
    </form>`;

  const form = main.querySelector('#f-parte');
  const cont = main.querySelector('#lineas');

  const parcelasDe = (finca) => cat.parcelas.filter((x) => !finca || x.finca === finca);
  function lineaHtml(l = {}) {
    const finca = l.finca ?? form.finca.value;
    return `<fieldset class="linea">
      <label>Tarea <select name="tarea">${options(cat.tareas, l.tarea, 'cod_tar', (t) => `${t.tareas} (${t.tipo === 'POR HORAS' ? 'h' : 'ha'})`)}</select></label>
      <label>Finca <select name="l_finca">${options(cat.fincas, finca, 'cod_fin', (f) => f.finca, '— Sin finca —')}</select></label>
      <label>Parcela <select name="parcela">${options(parcelasDe(finca), l.parcela, 'cod_par', (x) => `${x.nom_parc} (${x.superficie ?? '?'} ha)`, '— Sin parcela —')}</select></label>
      <label>Vehículo <select name="l_vehiculo">${options(cat.vehiculos, l.vehiculo ?? form.vehiculo.value, 'id_mat', (v) => `${v.alias} · ${v.equipo}`, '— Ninguno —')}</select></label>
      <label>Apero <select name="apero">${options(cat.aperos, l.apero, 'id_bas', (a) => `${a.alias} · ${a.equipo}`, '— Ninguno —')}</select></label>
      <label>Inicio <input type="time" name="h_ini" value="${esc(l.h_ini || '')}"></label>
      <label>Fin <input type="time" name="h_fin" value="${esc(l.h_fin || '')}"></label>
      <label class="wide">Obs. <input name="l_obs" value="${esc(l.obs || '')}"></label>
      <input type="hidden" name="id_linea" value="${esc(l.id_linea || '')}">
      <button type="button" class="link danger quitar">Quitar</button>
    </fieldset>`;
  }
  const addLinea = (l) => { cont.insertAdjacentHTML('beforeend', lineaHtml(l)); refrescar(); };
  function refrescar() {
    const tot = calcTotHoras(Object.fromEntries(new FormData(form)));
    main.querySelector('#tot').textContent = fmtHoras(tot);
    main.querySelector('#sin-lineas').hidden = cont.children.length > 0;
  }

  lineas.forEach(addLinea);
  if (!id) addLinea({ h_ini: cab.h_ent, h_fin: cab.h_sal });
  refrescar();

  main.querySelector('#add-linea').addEventListener('click', () => addLinea({}));
  cont.addEventListener('click', (ev) => {
    if (ev.target.classList.contains('quitar')) { ev.target.closest('.linea').remove(); refrescar(); }
  });
  // Parcela dependiente de la finca de la línea
  cont.addEventListener('change', (ev) => {
    if (ev.target.name !== 'l_finca') return;
    const sel = ev.target.closest('.linea').querySelector('[name=parcela]');
    sel.innerHTML = options(parcelasDe(ev.target.value), '', 'cod_par', (x) => `${x.nom_parc} (${x.superficie ?? '?'} ha)`, '— Sin parcela —');
  });
  // Al elegir la finca de la jornada, las líneas sin finca la heredan
  form.finca.addEventListener('change', () => {
    cont.querySelectorAll('[name=l_finca]').forEach((sel) => {
      if (sel.value) return;
      sel.value = form.finca.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    });
  });
  form.addEventListener('input', refrescar);

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = Object.fromEntries(new FormData(form));
    const nuevaCab = {
      operario: fd.operario, fecha: fd.fecha, h_ent: fd.h_ent, h_sal: fd.h_sal,
      t_alm_min: Number(fd.t_alm_min) || 0, t_com_min: Number(fd.t_com_min) || 0, h_ext: Number(fd.h_ext) || 0,
      mat_nave: form.mat_nave.checked, finca: fd.finca, vehiculo: fd.vehiculo || null, obs: fd.obs,
    };
    const nuevasLineas = [...cont.querySelectorAll('.linea')].map((f) => {
      const v = (n) => f.querySelector(`[name=${n}]`).value;
      return { id_linea: v('id_linea') || null, tarea: v('tarea'), finca: v('l_finca') || null, parcela: v('parcela') || null, vehiculo: v('l_vehiculo') || null,
        apero: v('apero') || null, h_ini: v('h_ini'), h_fin: v('h_fin'), obs: v('l_obs') };
    });
    const msg = main.querySelector('#form-msg');
    const errores = validarParte(nuevaCab, nuevasLineas, cat);
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
