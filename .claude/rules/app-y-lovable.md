---
paths:
  - "app/**"
  - "scripts/**"
  - "src/**"
  - "docs/PROMPT_LOVABLE.md"
---

# Boceto (`app/`) y frontend de Lovable

- `app/` es un boceto funcional en JS sin framework. El diseño final lo hace Lovable (React + TypeScript + Tailwind +
  shadcn/ui + supabase-js v2), pensado sobre todo para el móvil de los operarios.
- `app/js/data/index.js` elige el adaptador:
  - `supabase.js` si `/config.js` trae la URL y la clave pública;
  - si no, `mock.js`, con datos ficticios. `?demo` lo fuerza y `?demo&fallo` simula un error de red.

  Los dos adaptadores exponen la misma interfaz: cualquier función nueva va en los dos.
- `scripts/serve.mjs` solo envía al navegador la URL y la clave publishable. Si detecta una clave secreta o la service
  role, no la envía.
- Escrituras de partes, solo con RPC:
  - `guardar_cabecera`, `guardar_linea` y `borrar_linea`;
  - `cerrar_parte`, `revisar_parte`, `borrar_parte` y `archivar_partes`.

  `guardar_parte` es la forma antigua y se mantiene solo por compatibilidad: no usarla en código nuevo. Nunca
  insert/update/delete directo en `partes_cab` ni `partes_det`.
- Datos de apoyo:
  - usuario conectado: `rpc('app_rol')` y `rpc('app_cod_ope')`;
  - nombres de operarios: `rpc('operarios_nombres')`;
  - valores iniciales: `rpc('valores_iniciales_parte')`;
  - catálogos en selectores: `.eq('activo', true)`.
- Pantalla del parte en 2 pestañas, **Jornada** y **Líneas del parte**:
  - "Aceptar jornada" crea el parte en Pendiente;
  - cada línea se valida y se guarda al pulsar "Aceptar".
- `docs/PROMPT_LOVABLE.md` es la guía que se pega en Lovable. Se actualiza cuando cambia una RPC, una regla visible o
  una pantalla. Lovable no crea tablas, migraciones, políticas ni Edge Functions, y nunca usa datos inventados.
