# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es

App interna de **Partes de Trabajo** para Escribano Cabañero (empresa agrícola). Cada operario registra su jornada y
las tareas del día, en orden de hora; sirve para controlar el gasto por parcela. Todo (código, documentación, mensajes
de error) está en español de España.

- **Backend**: Supabase, proyecto `baluwelboftnibtyjrer` (conector MCP en `.mcp.json`). Toda la lógica de negocio y los
  permisos están en la base de datos: RLS, disparadores y funciones `SECURITY DEFINER`.
- **Frontend en producción**: lo construye Lovable (https://appreport.lovable.app), no está en este repositorio. Se le
  guía con `docs/PROMPT_LOVABLE.md`. Si cambia algo de la BD que afecte a la interfaz, hay que actualizar ese prompt.
- **`app/`**: boceto funcional en JS sin framework (no es el diseño final), servido por `scripts/serve.mjs`.

## Comandos

```
npm install
npm run dev              # boceto en http://localhost:5180 (sin .env → modo demo; ?demo lo fuerza; ?demo&fallo simula error de red)
npm test                 # pruebas de app/js/rules.js (node --test scripts/test-rules.mjs)
node --test --test-name-pattern="jornada" scripts/test-rules.mjs   # una sola prueba
npm run check:supabase   # comprueba la conexión (solo lecturas)
```

Node ≥ 22. `.env` se copia de `.env.example`, con la clave **publishable/anon**. La service role no va nunca al navegador:
`serve.mjs` la detecta y la rechaza.

## Arquitectura

### Base de datos (`supabase/`)
- `propuesta/NNN_*.sql` son las migraciones, numeradas y en orden (001–021). Varias se aplicaron desde el SQL Editor y
  **no figuran en el historial de migraciones**: estos archivos son el registro.
- Cada migración nueva lleva su fila en la tabla de `supabase/README.md`, con fecha, cómo se aplicó y el resultado de
  las pruebas. El README es también la referencia de permisos por rol y de las RPC para la interfaz.
- `functions/generar-pdf/index.ts` es la Edge Function del PDF (verify_jwt activado).
- `seed/` contiene los catálogos del Excel y `generar_partes_prueba_mes.mjs`, que genera el SQL de un mes de partes de prueba.
- Decisiones de diseño: `docs/DECISIONES_MODULOS_4_A_8.md` y `docs/PLAN_MODULOS_9_Y_10.md`. El diseño original está en
  `Diseno_App_Partes_Trabajo_AppSheet.md`.

Reglas clave:
- Los partes (`partes_cab` y `partes_det`) solo se escriben con RPC:
  - `guardar_cabecera`, `guardar_linea` y `borrar_linea`;
  - `cerrar_parte`, `revisar_parte` y `borrar_parte`;
  - `archivar_partes`;
  - `guardar_parte`, que es la forma antigua y se conserva por compatibilidad.
- Desde la 020, una escritura directa da `42501`. `anon` no tiene ningún permiso en `public`.
- Estados: Pendiente → Cerrado → Aprobado | Rechazado, sin vuelta atrás.
- Roles en `operarios.rol_app`: ADMIN, SUPERVISOR, OPERARIO. Para saber quién está conectado: `app_rol()`, `app_cod_ope()` y `app_es_gestor()`.
- `validar_parte()` impone las reglas del parte:
  - horas en múltiplos de 15 minutos;
  - la primera tarea es DESPLAZAMIENTO o MANTENIMIENTO NAVE (sin contar MOTIVOS PERSONALES);
  - cambiar de finca exige un DESPLAZAMIENTO;
  - `fin_vuelta` es obligatorio al cerrar en las tareas con parcela de tipo POR SUPERFICIE o POR HORAS.
- Las vistas `vueltas`, `tareas_resumen` y `horas_trabajador` son `security_invoker`. Solo devuelven filas a ADMIN y
  SUPERVISOR.

### Reglas duplicadas en la app
`app/js/rules.js` repite en JS las reglas de la BD para validar en pantalla. `scripts/test-rules.mjs` existe para que
las dos copias no se separen. Si cambia una regla en SQL, cambiarla también en `rules.js` y en sus pruebas.

`app/js/data/index.js` elige el adaptador: `supabase.js` o `mock.js`, este con datos ficticios. Los dos exponen la
misma interfaz.

### Pruebas SQL (`supabase/pruebas/`)
- Hay un script por módulo y `pruebas_por_rol.sql`.
- Cada uno simula usuarios con `set_config('request.jwt.claims', ...)` y `set local role authenticated`.
- Cada uno termina con `raise exception 'RESULTADOS(rollback) [...]'` a propósito: el error muestra los resultados y
  deshace todo.
- Cada caso indica lo esperado.
- Usuarios de prueba:
  - T002 (jangel@) es el OPERARIO;
  - T001 (oficinas@) es el SUPERVISOR;
  - T000 (soporte@) es el ADMIN.
- Repetir los scripts afectados tras cada migración y anotar el resultado en el README.
- El conector MCP de Supabase rechaza el SQL que contiene `DELETE`, `UPDATE` o `DROP`, así que esos scripts se pegan
  en Dashboard → SQL Editor. `apply_migration` sí acepta `GRANT`/`REVOKE`.

## Pendiente conocido
- En el panel de Supabase (lo hace el usuario):
  - longitud mínima de contraseña de 12;
  - protección contra contraseñas filtradas, que exige un plan de pago.
