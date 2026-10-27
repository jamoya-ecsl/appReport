# Boceto funcional — Partes de Trabajo (Escribano Cabañero)

Primera exploración: sirve para entender el flujo de la app. **No es el diseño final** (eso se hará en Lovable).

## Cómo ejecutarlo
```
npm install
npm run dev          → http://localhost:5180
```
- Sin `.env` → **modo demo** con datos ficticios (aviso amarillo arriba). Se guardan solo en la pestaña.
- Con `.env` (copiar `.env.example` y rellenar `SUPABASE_ANON_KEY` con la clave *publishable*) → **modo Supabase**.
- `?demo` en la URL fuerza el modo demo. `?demo&fallo` simula un error de red para ver el estado de error.

## En qué se basa
| Fuente | Qué aporta |
|---|---|
| `Diseno_App_Partes_Trabajo_AppSheet.md` | Roles, campos, reglas de edición, vistas |
| `supabase/propuesta/001_esquema_partes_trabajo.sql` | Nombres de tablas/columnas y RLS que usa el modo Supabase |
| `PT_EC.xlsx`, `BBDD_Corregida_AppSheet.xlsx` | Estructura de los catálogos (el boceto **no** usa sus datos) |

## Pantallas y navegación
```
Login ──► Inicio ──► Lista de partes ──► Detalle ──► Editar
            │            ▲  (filtros)       │
            └──► Nuevo parte ───────────────┘ (al guardar va al detalle)
```
| Pantalla | Ruta | Quién | Qué hace |
|---|---|---|---|
| Login | `#/login` | Todos | Demo: elegir usuario ficticio. Supabase: enlace mágico por email |
| Inicio | `#/inicio` | Todos | Contadores por estado, aviso de pendientes (gestor) o rechazados (operario), últimos 5 partes |
| Lista | `#/partes` | Todos | "Mis partes" (operario) / "Todos los partes" (supervisor/admin). Filtros: estado, operario, finca, fechas |
| Detalle | `#/partes/:id` | Todos | Jornada, líneas de tareas, revisión. Aprobar/Rechazar (gestor, si está Pendiente) |
| Nuevo / Editar | `#/partes/nuevo`, `#/partes/:id/editar` | Todos | Cabecera + líneas de tareas; parcelas filtradas por finca; total de horas en vivo |

Estados cubiertos: carga, lista vacía, error (con reintentar), éxito (aviso flotante), validación de formulario, sin permiso.

## Reglas implementadas (mismas que el SQL propuesto)
- OPERARIO: ve y crea solo sus partes; edita solo en `Pendiente`.
- SUPERVISOR y ADMIN: ven todos; pueden editar y aprobar/rechazar.
- Solo ADMIN puede crear un parte a nombre de otro operario.
- Un parte por operario y día. Salida > entrada. Rechazar exige comentario.
- `tot_horas` = (salida − entrada) − almuerzo − comida.

## Decisiones provisionales (supuestos)
| Tema | Decisión del boceto |
|---|---|
| Campo `TIEMPO` | **No se muestra**: su significado sigue sin confirmar en el diseño |
| Parte rechazado | El operario no puede editarlo (así lo dice el diseño). Falta decidir cómo se corrige: ¿lo edita el supervisor, o vuelve a `Pendiente`? |
| Login en Supabase | Email + contraseña (cuentas creadas en el Dashboard) y, como alternativa, enlace mágico. El diseño original hablaba de Google |
| Guardado de cabecera + líneas | Dos llamadas seguidas (no atómico). En producción, una función RPC en una transacción |
| Almuerzo / comida | Se piden en minutos y se guardan como `interval` |

## Fuera de alcance (existe en el diseño, no en el boceto)
Partes de mantenimiento (`partes_mant`), gestión de catálogos y usuarios (admin), "Mi perfil", informes, fotos y GPS, notificaciones y PDF.

## Archivos del boceto
| Archivo | Función |
|---|---|
| `app/index.html`, `app/styles.css` | Página y estilos mínimos |
| `app/js/main.js` | Pantallas y navegación |
| `app/js/rules.js` | Reglas de negocio y cálculo de horas |
| `app/js/ui.js` | Formatos y estados (carga, vacío, error, aviso) |
| `app/js/data/index.js` | Elige el modo demo o Supabase |
| `app/js/data/mock.js` | Modo demo — **datos ficticios** |
| `app/js/data/supabase.js` | Modo Supabase (clave pública + RLS) |
| `scripts/serve.mjs` | Servidor local sin dependencias; no envía nunca claves secretas al navegador |

## Qué llevar a Lovable
- **Trasladar tal cual**: el flujo de pantallas, las reglas de `rules.js`, la interfaz de datos (`listPartes`, `getParte`, `saveParte`, `setEstado`) y los mensajes de error de `supabase.js`.
- **Ajustar**: login (Google o email según decidáis), el formulario para usarlo desde el móvil en el campo, y el guardado atómico con una RPC.
- **Reconstruir**: todo el diseño visual (Lovable usa React + Tailwind); este HTML/JS es desechable.
- **Añadir después**: mantenimiento, administración de catálogos, informes, fotos (Storage) y notificaciones.
