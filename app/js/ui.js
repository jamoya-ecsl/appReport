// Utilidades de presentación: escapado, formatos y estados (carga / vacío / error / éxito).

export const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export const fmtFecha = (d) => (d ? new Date(`${d}T00:00:00`).toLocaleDateString('es-ES') : '—');
export const fmtFechaHora = (ts) => (ts ? new Date(ts).toLocaleString('es-ES') : '—');
export const fmtHoras = (n) =>
  n == null ? '—' : `${Number(n).toLocaleString('es-ES', { maximumFractionDigits: 2 })} h`;

export const badge = (estado) =>
  `<span class="badge badge-${esc(String(estado || '').toLowerCase())}">${esc(estado)}</span>`;

export const loadingHtml = (t = 'Cargando…') =>
  `<div class="state state-loading" role="status"><span class="spinner"></span>${esc(t)}</div>`;

export const emptyHtml = (t, cta = '') =>
  `<div class="state state-empty"><p>${esc(t)}</p>${cta}</div>`;

export function errorHtml(err, { retry = true, extra = '' } = {}) {
  return `<div class="state state-error" role="alert">
    <strong>No se pudo completar la operación</strong>
    <p>${esc(err?.message || err)}</p>
    ${err?.hint ? `<p class="hint">${esc(err.hint)}</p>` : ''}
    <div class="row">${retry ? '<button data-action="retry">Reintentar</button>' : ''}${extra}</div>
  </div>`;
}

export function toast(msg, type = 'ok') {
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.setAttribute('role', 'status');
  t.textContent = msg;
  document.body.append(t);
  setTimeout(() => t.remove(), 3200);
}

// Los registros dados de baja (activo === false) no se ofrecen, salvo el valor ya guardado
// (partes antiguos), que se muestra marcado como "(baja)".
export const options = (list, value, valueKey, labelFn, empty = '— Selecciona —') =>
  `<option value="">${esc(empty)}</option>` +
  list.filter((x) => x.activo !== false || x[valueKey] === value)
    .map((x) => `<option value="${esc(x[valueKey])}" ${x[valueKey] === value ? 'selected' : ''}>${esc(labelFn(x))}${x.activo === false ? ' (baja)' : ''}</option>`).join('');
