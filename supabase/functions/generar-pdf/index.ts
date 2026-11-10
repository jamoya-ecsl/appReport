// Función del servidor (Edge Function) generar-pdf — módulo 8, migración 016.
// La llama el botón "Generar PDF" de la app, con la sesión del usuario:
//   supabase.functions.invoke('generar-pdf', { body: { id_parte } })
//   → { url, ruta, version, nuevo }   (url: enlace temporal de 5 minutos para abrir o imprimir el PDF)
// 1. pdf_pedir(id_parte) se ejecuta CON LA SESIÓN DEL USUARIO: la BD comprueba que es SUPERVISOR o ADMIN y
//    que el parte está Aprobado, y decide si sirve el último PDF o hace falta uno nuevo.
// 2. Si hace falta, dibuja el PDF a partir de la "foto" del parte, lo sube al bucket privado partes-pdf y
//    lo marca con pdf_marcar() (esto último con la clave de servicio, que nunca sale del servidor).
// Desplegar con verify_jwt = true (solo usuarios con sesión).
// Usa las variables SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY que Supabase pone en todas
// las funciones: no hace falta configurar ningún secreto.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { PDFDocument, PDFFont, PDFPage, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const servicio = createClient(URL_SB, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type Linea = {
  h_ini: string; h_fin: string; horas: number | null; tarea: string; nom_tarea: string | null; tipo: string | null;
  finca: string | null; parcela: string | null; vehiculo: string | null; apero: string | null;
  fin_vuelta: string | null; obs: string | null;
};
type Datos = {
  num_parte: number; fecha: string; campana: string; operario: string; nom_operario: string | null;
  h_ent: string; h_sal: string; t_alm_min: number; t_com_min: number; tot_horas: number; h_ext: number;
  ht_tareas: number; obs: string | null;
  cerrado_por: string | null; nom_cerrado_por: string | null; fecha_cierre: string | null;
  supervisor_revisa: string | null; nom_supervisor: string | null; fecha_revision: string | null;
  comentario_supervisor: string | null; lineas: Linea[];
};
type Pedido = { id: number; ruta: string; version: number; nuevo: boolean; datos?: Datos };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405);
  const auth = req.headers.get('Authorization');
  if (!auth) return json({ error: 'Falta la sesión' }, 401);
  const { id_parte } = await req.json().catch(() => ({}));
  if (!id_parte) return json({ error: 'Falta id_parte' }, 400);

  // Con la sesión del usuario: los permisos los decide la base de datos.
  const usuario = createClient(URL_SB, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await usuario.rpc('pdf_pedir', { p_id_parte: id_parte });
  if (error) return json({ error: error.message, code: error.code }, error.code === '42501' ? 403 : 400);
  const p = data as Pedido;

  if (p.nuevo) {
    try {
      const { data: yo } = await usuario.rpc('app_cod_ope');
      const bytes = await dibujar(p, String(yo ?? ''));
      const up = await servicio.storage.from('partes-pdf').upload(p.ruta, bytes, { contentType: 'application/pdf', upsert: true });
      if (up.error) throw up.error;
      const m = await servicio.rpc('pdf_marcar', { p_id: p.id, p_error: null });
      if (m.error) throw m.error;
    } catch (e) {
      const msg = String((e as Error)?.message ?? e);
      await servicio.rpc('pdf_marcar', { p_id: p.id, p_error: msg });
      return json({ error: `No se pudo generar el PDF: ${msg}` }, 500);
    }
  }
  const firmado = await servicio.storage.from('partes-pdf').createSignedUrl(p.ruta, 300);
  if (firmado.error) return json({ error: firmado.error.message }, 500);
  return json({ url: firmado.data.signedUrl, ruta: p.ruta, version: p.version, nuevo: p.nuevo });
});

// ---------- Dibujo del PDF (A4 vertical) ----------
const A4 = { w: 595.28, h: 841.89 };
const M = 40;                       // margen
const GRIS = rgb(0.45, 0.45, 0.45);
const LINEA = rgb(0.8, 0.8, 0.8);

// Las fuentes estándar solo admiten caracteres de Europa occidental (WinAnsi): el resto se cambia por '?'.
const WIN = new Set([...'€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ']);
const limpio = (s: unknown) =>
  [...String(s ?? '')].map((c) => (c.charCodeAt(0) < 256 || WIN.has(c) ? c : '?')).join('').replace(/[\r\n\t]+/g, ' ');

const dma = (d: string | null) => (d ? d.slice(0, 10).split('-').reverse().join('/') : '—');
const dmaHora = (ts: string | null) => {
  if (!ts) return '—';
  const f = new Date(ts);
  return f.toLocaleString('es-ES', { timeZone: 'Europe/Madrid', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
};
const horas = (n: number | null) => (n == null ? '—' : `${Number(n).toLocaleString('es-ES', { maximumFractionDigits: 2 })} h`);

async function dibujar(t: Pedido, por: string): Promise<Uint8Array> {
  const d = t.datos!;
  const pdf = await PDFDocument.create();
  pdf.setTitle(`Parte de trabajo nº ${d.num_parte}`);
  pdf.setSubject(`Versión ${t.version}`);
  pdf.setProducer('Partes de Trabajo');
  const f = await pdf.embedFont(StandardFonts.Helvetica);
  const fb = await pdf.embedFont(StandardFonts.HelveticaBold);

  let page = pdf.addPage([A4.w, A4.h]);
  let y = A4.h - M;
  const nuevaPagina = () => { page = pdf.addPage([A4.w, A4.h]); y = A4.h - M; };
  const hay = (alto: number) => { if (y - alto < M + 20) nuevaPagina(); };

  const texto = (s: unknown, x: number, yy: number, size = 9, font: PDFFont = f, color = rgb(0, 0, 0)) =>
    page.drawText(limpio(s), { x, y: yy, size, font, color });
  // Corta el texto para que quepa en el ancho dado.
  const cabe = (s: unknown, ancho: number, size = 8, font: PDFFont = f) => {
    let v = limpio(s);
    if (font.widthOfTextAtSize(v, size) <= ancho) return v;
    while (v.length > 1 && font.widthOfTextAtSize(`${v}…`, size) > ancho) v = v.slice(0, -1);
    return `${v}…`;
  };
  // Párrafo con saltos de línea automáticos.
  const parrafo = (s: string, x: number, ancho: number, size = 9) => {
    const palabras = limpio(s).split(' ');
    let linea = '';
    for (const p of palabras) {
      const prueba = linea ? `${linea} ${p}` : p;
      if (f.widthOfTextAtSize(prueba, size) > ancho && linea) {
        hay(size + 3); texto(linea, x, y, size); y -= size + 3; linea = p;
      } else linea = prueba;
    }
    if (linea) { hay(size + 3); texto(linea, x, y, size); y -= size + 3; }
  };

  // Cabecera
  texto(`Parte de trabajo nº ${d.num_parte}`, M, y, 16, fb);
  texto(`Versión ${t.version} · Aprobado`, A4.w - M - 150, y + 2, 9, f, GRIS);
  y -= 22;
  page.drawLine({ start: { x: M, y }, end: { x: A4.w - M, y }, thickness: 1, color: LINEA });
  y -= 18;

  // Datos de la jornada en dos columnas
  const campo = (et: string, val: unknown, x: number) => { texto(et, x, y, 8, f, GRIS); texto(val, x + 85, y, 9, fb); };
  const filas: [string, unknown, string, unknown][] = [
    ['Operario', `${d.nom_operario ?? d.operario} (${d.operario})`, 'Fecha', dma(d.fecha)],
    ['Entrada', d.h_ent, 'Salida', d.h_sal],
    ['Almuerzo', `${d.t_alm_min} min`, 'Comida', `${d.t_com_min} min`],
    ['Total jornada', horas(d.tot_horas), 'Horas extra', horas(d.h_ext)],
    ['Horas de tareas', horas(d.ht_tareas), 'Campaña', d.campana],
  ];
  for (const [a, va, b, vb] of filas) {
    campo(a, va, M);
    if (b) campo(b, vb, A4.w / 2);
    y -= 15;
  }
  if (d.obs) { y -= 2; texto('Observaciones', M, y, 8, f, GRIS); y -= 12; parrafo(d.obs, M, A4.w - 2 * M); }
  y -= 10;

  // Tabla de tareas
  texto(`Tareas realizadas (${d.lineas.length})`, M, y, 11, fb);
  y -= 16;
  const cols: { t: string; w: number; v: (l: Linea) => unknown }[] = [
    { t: 'Inicio', w: 34, v: (l) => l.h_ini },
    { t: 'Fin', w: 34, v: (l) => l.h_fin },
    { t: 'Horas', w: 36, v: (l) => horas(l.horas) },
    { t: 'Tarea', w: 100, v: (l) => l.nom_tarea ?? l.tarea },
    { t: 'Finca', w: 72, v: (l) => l.finca ?? '—' },
    { t: 'Parcela', w: 72, v: (l) => l.parcela ?? '—' },
    { t: 'Vehículo', w: 70, v: (l) => l.vehiculo ?? '—' },
    { t: 'Apero', w: 60, v: (l) => l.apero ?? '—' },
    { t: 'Fin vuelta', w: 37, v: (l) => l.fin_vuelta ?? '—' },
  ];
  const encabezado = () => {
    let x = M;
    page.drawRectangle({ x: M - 2, y: y - 3, width: A4.w - 2 * M + 4, height: 13, color: rgb(0.93, 0.93, 0.93) });
    for (const c of cols) { texto(cabe(c.t, c.w - 3, 7, fb), x, y, 7, fb); x += c.w; }
    y -= 14;
  };
  encabezado();
  // Cada celda pasa a la línea siguiente si no cabe (hasta 3 líneas; la última se corta con "…").
  const partir = (s: unknown, ancho: number, size = 8) => {
    const out: string[] = [];
    let linea = '';
    for (const p of limpio(s).split(' ')) {
      const prueba = linea ? `${linea} ${p}` : p;
      if (f.widthOfTextAtSize(prueba, size) > ancho && linea) { out.push(linea); linea = p; } else linea = prueba;
    }
    if (linea) out.push(linea);
    if (out.length > 3) out.splice(2, out.length - 2, out.slice(2).join(' '));
    return out.map((t) => cabe(t, ancho, size));
  };
  for (const l of d.lineas) {
    const celdas = cols.map((c) => partir(c.v(l), c.w - 3));
    const alto = 10 * Math.max(...celdas.map((c) => c.length)) + 2;
    if (y - alto < M + 20) { nuevaPagina(); encabezado(); }
    let x = M;
    celdas.forEach((lineas, i) => { lineas.forEach((t, k) => texto(t, x, y - 10 * k, 8)); x += cols[i].w; });
    y -= alto;
    if (l.obs) { parrafo(`Obs.: ${l.obs}`, M + 34, A4.w - 2 * M - 34, 7); y -= 1; }
    page.drawLine({ start: { x: M, y: y + 8 }, end: { x: A4.w - M, y: y + 8 }, thickness: 0.3, color: LINEA });
  }
  if (!d.lineas.length) { texto('Sin tareas.', M, y, 9, f, GRIS); y -= 12; }
  y -= 14;

  // Cierre y revisión
  hay(70);
  texto('Cierre y revisión', M, y, 11, fb);
  y -= 16;
  campo('Cerrado por', d.cerrado_por ? `${d.nom_cerrado_por ?? d.cerrado_por} (${d.cerrado_por})` : '—', M);
  campo('Fecha de cierre', dmaHora(d.fecha_cierre), A4.w / 2);
  y -= 15;
  campo('Aprobado por', d.supervisor_revisa ? `${d.nom_supervisor ?? d.supervisor_revisa} (${d.supervisor_revisa})` : '—', M);
  campo('Fecha de aprobación', dmaHora(d.fecha_revision), A4.w / 2);
  y -= 15;
  if (d.comentario_supervisor) { texto('Comentario', M, y, 8, f, GRIS); y -= 12; parrafo(d.comentario_supervisor, M, A4.w - 2 * M); }

  // Pie en todas las páginas
  const paginas = pdf.getPages();
  const pie = `Parte nº ${d.num_parte} · versión ${t.version} · generado el ${dmaHora(new Date().toISOString())}${por ? ` por ${por}` : ''}`;
  paginas.forEach((p: PDFPage, i: number) => {
    p.drawText(limpio(pie), { x: M, y: M - 15, size: 7, font: f, color: GRIS });
    p.drawText(`Página ${i + 1} de ${paginas.length}`, { x: A4.w - M - 60, y: M - 15, size: 7, font: f, color: GRIS });
  });
  return await pdf.save();
}
