// Elige la fuente de datos:
//  - Modo Supabase si /config.js trae URL + clave pública.
//  - Modo demo (datos FICTICIOS en el navegador) si no hay credenciales o si la URL lleva ?demo.
// Ambos adaptadores exponen la misma interfaz, así que las pantallas no saben cuál usan.

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = () => reject(Object.assign(new Error('No se pudo cargar la librería de Supabase.'), {
      hint: 'Ejecuta "npm install" y reinicia el servidor con "npm run dev".',
    }));
    document.head.append(s);
  });
}

export async function createApi() {
  const cfg = window.APP_CONFIG || {};
  const forced = new URLSearchParams(location.search).has('demo');
  if (forced || !cfg.supabaseUrl || !cfg.supabaseKey) {
    const { createMockApi } = await import('./mock.js');
    return createMockApi(forced ? 'activado con ?demo' : 'no hay credenciales de Supabase en .env');
  }
  await loadScript('/vendor/supabase.js');
  const { createSupabaseApi } = await import('./supabase.js');
  return createSupabaseApi(cfg);
}
