---
paths:
  - "supabase/pruebas/**"
  - "supabase/propuesta/**"
  - "scripts/test-rules.mjs"
  - "app/js/rules.js"
---

# Pruebas

## Pruebas SQL (`supabase/pruebas/`)
- Cada script es un bloque `do $$ ... $$`. Simula a cada usuario así:
  ```
  perform set_config('request.jwt.claims', <json con sub, email y role 'authenticated'>, true);
  set local role authenticated;
  ... ;
  reset role;
  ```
- Cada caso:
  - tiene un código (M01, S02, L05...);
  - indica lo esperado en el texto (`(esperado OK)`, `(esperado bloqueado 42501 ...)`);
  - va en su propio `begin ... exception when others` y añade su resultado a `res`.
- El script termina con `raise exception 'RESULTADOS(rollback) %', res`, a propósito: muestra los resultados y deshace
  todo. Solo puede saltar la numeración de `num_parte`.
- Usuarios de prueba:

| Código | Usuario | Rol |
|---|---|---|
| T002 | jangel@ | OPERARIO |
| T001 | oficinas@ | SUPERVISOR |
| T000 | soporte@ | ADMIN |

  T003 (campo@) es SUPERVISOR desde el 11/11; no usarlo como operario.
- Los partes de prueba usan fechas que no chocan con datos reales (p. ej. 2099). El módulo 7 usa el año 2000.
- Tras una migración, repetir los scripts afectados y anotar el resultado (n/n) en `supabase/README.md`.
- Si una regla cambia el resultado esperado de un caso existente:
  - actualizar el texto del caso con la migración que lo cambia ("desde la 0NN");
  - no borrar el caso.
- Una migración que añade reglas lleva su propio script nuevo (`pruebas_moduloN.sql`).
- Los scripts con `DELETE`, `UPDATE` o `DROP` no pasan por el conector MCP: los ejecuta el usuario en el SQL Editor.

## Pruebas de la app
- `npm test` ejecuta `node --test scripts/test-rules.mjs`, con casos tomados de los scripts SQL.
- Una sola prueba: `node --test --test-name-pattern="<nombre>" scripts/test-rules.mjs`.
- Cualquier cambio en `app/js/rules.js` o en una regla de la BD actualiza estas pruebas.
