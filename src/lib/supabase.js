// Cliente único de Supabase para la app.
// Usa SIEMPRE la clave pública (publishable/anon); la seguridad real la ponen las políticas RLS.
import { createClient } from '@supabase/supabase-js';

const REQUIRED = ['SUPABASE_URL', 'SUPABASE_ANON_KEY'];

export function missingEnv(env = process.env) {
  return REQUIRED.filter((k) => !env[k] || !String(env[k]).trim());
}

export function getSupabase(env = process.env) {
  const missing = missingEnv(env);
  if (missing.length) {
    throw new Error(`Faltan variables de entorno de Supabase: ${missing.join(', ')}`);
  }
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
