---
paths:
  - "supabase/**"
---

# Base de datos y migraciones (Supabase `baluwelboftnibtyjrer`)

## Migraciones
- Cada cambio va en una migración nueva: `supabase/propuesta/NNN_nombre.sql`, con el número siguiente.
  - Lleva una cabecera que explica qué corrige y por qué.
  - No se reescribe una migración ya aplicada.
- El archivo es el registro: varias migraciones se aplicaron desde el SQL Editor y no figuran en el historial de Supabase.
- Tras aplicar una migración, añadir su fila en la tabla de `supabase/README.md`. La fila indica:
  - fecha;
  - cómo se aplicó (conector o SQL Editor);
  - qué pruebas pasó y con qué resultado (p. ej. 14/14);
  - qué cambia.
- Si cambia algo que use la interfaz, actualizar también:
  - la "Referencia rápida" del README;
  - `docs/PROMPT_LOVABLE.md`.
- Para redefinir una función:
  - partir de la definición real (`pg_get_functiondef`), no de un archivo antiguo;
  - cambiar solo lo necesario;
  - `CREATE OR REPLACE` conserva los permisos.

## Conector MCP
- `execute_sql` rechaza el texto que contiene `DELETE`, `UPDATE` o `DROP`.
- Esos scripts los pega el usuario en Dashboard → SQL Editor, y lo ejecutado ahí no queda en el historial.
- `apply_migration` acepta DDL, `GRANT` y `REVOKE`.

## Seguridad (020)
- `anon` no tiene ningún permiso en `public`, tampoco en lo que se cree después.
- `authenticated` tiene:
  - SELECT en todas las tablas;
  - INSERT, UPDATE y DELETE solo en `fincas`, `parcelas`, `tareas`, `vehiculos`, `aperos` y `operarios`;
  - UPDATE en `configuracion`.
- **Tabla nueva**:
  - activar RLS con sus políticas;
  - hacer `REVOKE` y `GRANT` explícitos para `authenticated`, porque los privilegios por defecto de Supabase le dan todo, TRUNCATE incluido.
- `partes_cab` y `partes_det` no se escriben directamente: solo con funciones `SECURITY DEFINER`. Una escritura directa da `42501`.
- Funciones `SECURITY DEFINER`:
  - con `set search_path` fijo;
  - comprueban el rol con `app_rol()`, `app_cod_ope()` y `app_es_gestor()`.
- Vistas: con `security_invoker`.
- Las fechas se calculan en hora de Madrid (`set "TimeZone" to 'Europe/Madrid'`).
- Campos que fija la BD y nunca la app:
  - `creado_por` y fechas de creación;
  - `supervisor_revisa` y `fecha_revision`;
  - `fecha_baja` y `baja_por`.

## Errores
- Los mensajes van en español.
- Códigos:
  - `23505`: duplicado;
  - `23514`: regla de datos (check);
  - `42501`: sin permiso;
  - `P0001`: regla de negocio.
