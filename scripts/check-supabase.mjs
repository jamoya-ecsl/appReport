// Comprobación SEGURA de la conexión a Supabase: solo lecturas, nunca escribe.
// Uso: npm install && npm run check:supabase
// No imprime ningún valor secreto: solo si cada variable está definida.
import { getSupabase, missingEnv } from '../src/lib/supabase.js';

const OK = '✅', KO = '❌', WARN = '⚠️';
const TABLES = ['operarios', 'fincas', 'parcelas', 'tareas', 'vehiculos', 'aperos',
  'partes_cab', 'partes_det', 'partes_mant'];

function report(level, msg) { console.log(`${level} ${msg}`); }

// 1) Variables de entorno
for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
  report(process.env[k] ? OK : KO, `${k}: ${process.env[k] ? 'definida' : 'NO definida'}`);
}
if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
  report(WARN, 'SUPABASE_SERVICE_ROLE_KEY definida: no la uses en la app, solo en scripts de servidor.');
}
if (missingEnv().length) {
  report(KO, 'Estado: NO COMPROBABLE — faltan credenciales. Copia .env.example a .env y rellénalo.');
  process.exit(2);
}

const url = process.env.SUPABASE_URL.replace(/\/+$/, '');
const key = process.env.SUPABASE_ANON_KEY;

// 2) Alcance de red y validez de la clave (endpoint de salud de Auth, solo lectura)
try {
  const res = await fetch(`${url}/auth/v1/health`, { headers: { apikey: key } });
  if (res.ok) report(OK, `Servidor alcanzable y clave aceptada (auth/health HTTP ${res.status})`);
  else if (res.status === 401 || res.status === 403) {
    report(KO, `Servidor alcanzable pero la clave fue rechazada (HTTP ${res.status}). Revisa SUPABASE_ANON_KEY.`);
    process.exit(3);
  } else report(WARN, `Respuesta inesperada de auth/health: HTTP ${res.status}`);
} catch (e) {
  report(KO, `No se puede alcanzar ${url}: ${e.cause?.code ?? e.message}`);
  report(KO, 'Estado: NO COMPROBABLE — sin acceso de red al proyecto.');
  process.exit(4);
}

// 3) Lectura de tablas con el cliente (GET con límite 0 + count: no descarga filas ni modifica datos).
// No se usa HEAD: para una tabla inexistente PostgREST responde 204 sin error y daría un falso positivo.
const supabase = getSupabase();
let existentes = 0;
for (const t of TABLES) {
  const { count, error } = await supabase.from(t).select('*', { count: 'exact' }).limit(0);
  if (!error) {
    existentes++;
    report(OK, `Tabla ${t}: accesible (${count ?? 0} filas visibles para el rol anónimo; RLS puede ocultar filas)`);
  } else if (error.code === 'PGRST205' || error.code === '42P01') {
    report(WARN, `Tabla ${t}: no existe todavía`);
  } else {
    report(WARN, `Tabla ${t}: ${error.code ?? ''} ${error.message}`);
  }
}

report(OK, 'Estado: CONEXIÓN VERIFICADA EN EJECUCIÓN.');
if (existentes === 0) report(WARN, 'El proyecto responde pero aún no tiene el esquema de la app.');
