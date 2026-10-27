// Servidor local del boceto (sin dependencias). Uso: npm run dev → http://localhost:5180
// Sirve app/, la librería supabase-js desde node_modules y /config.js con la URL y la clave PÚBLICA.
// Nunca envía al navegador la service role key ni ninguna clave secreta.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../app', import.meta.url));
const VENDOR = fileURLToPath(new URL('../node_modules/@supabase/supabase-js/dist/umd/supabase.js', import.meta.url));
const PORT = Number(process.env.PORT) || 5180;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };

function esClaveSecreta(key) {
  if (key.startsWith('sb_secret_')) return true;
  try { return JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role === 'service_role'; } catch { return false; }
}

function publicConfig() {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_ANON_KEY?.trim();
  if (!url || !key) return { cfg: {}, modo: 'DEMO (faltan SUPABASE_URL / SUPABASE_ANON_KEY en .env)' };
  if (esClaveSecreta(key)) return { cfg: {}, modo: 'DEMO — SUPABASE_ANON_KEY contiene una clave SECRETA; no se envía al navegador. Usa la publishable/anon.' };
  return { cfg: { supabaseUrl: url, supabaseKey: key }, modo: 'SUPABASE' };
}

const { cfg, modo } = publicConfig();

http.createServer(async (req, res) => {
  const send = (code, body, type = 'text/plain; charset=utf-8') => {
    res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(body);
  };
  try {
    let p = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (p === '/config.js') return send(200, `window.APP_CONFIG = ${JSON.stringify(cfg)};`, TYPES['.js']);
    if (p === '/vendor/supabase.js') {
      try { return send(200, await readFile(VENDOR), TYPES['.js']); } catch { return send(404, 'supabase-js no instalado: ejecuta npm install'); }
    }
    if (p === '/') p = '/index.html';
    const file = path.resolve(ROOT, `.${p}`);
    if (!file.startsWith(path.resolve(ROOT) + path.sep)) return send(403, 'Prohibido');
    const body = await readFile(file);
    return send(200, body, TYPES[path.extname(file)] || 'application/octet-stream');
  } catch {
    return send(404, 'No encontrado');
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`Boceto Partes de Trabajo → http://localhost:${PORT}`);
  console.log(`Modo: ${modo}  (añade ?demo a la URL para forzar el modo demo)`);
});
