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
| `supabase/propuesta/` (001 a 007b, ya aplicadas) | Tablas, RLS, disparadores y funciones que usa el modo Supabase (ver `supabase/README.md`) |
| `PT_EC.xlsx`, `BBDD_Corregida_AppSheet.xlsx` | Estructura de los catálogos (el boceto **no** usa sus datos) |

## Pantallas y navegación
```
Login ──► Inicio ──► Lista de partes ──► Detalle ──► Editar
            │            ▲  (filtros)       │
            └──► Nuevo parte ───────────────┘ (al guardar va al detalle)
            └──► Vueltas y archivo (ADMIN y SUPERVISOR)
```
| Pantalla | Ruta | Quién | Qué hace |
|---|---|---|---|
| Login | `#/login` | Todos | Demo: elegir usuario ficticio. Supabase: email + contraseña o enlace mágico |
| Inicio | `#/inicio` | Todos | Contadores por estado, aviso de cerrados por revisar (gestor) o de partes sin cerrar y rechazados (operario), últimos 5 partes |
| Lista | `#/partes` | Todos | "Mis partes" (operario) / "Todos los partes" (supervisor/admin). Filtros: estado, operario, finca, fechas |
| Detalle | `#/partes/:id` | Todos | Jornada, líneas de tareas, cierre y revisión. Cerrar (si está Pendiente), Aprobar/Rechazar (gestor, si está Cerrado), Borrar (ADMIN) |
| Nuevo | `#/partes/nuevo` | Todos | Cabecera + líneas de tareas; parcelas filtradas por finca; total de horas en vivo |
| Editar | `#/partes/:id/editar` | ADMIN; SUPERVISOR (Pendientes y Cerrados); OPERARIO (suyos, en Pendiente) | Mismo formulario |
| Vueltas y archivo | `#/archivo` | ADMIN y SUPERVISOR | Vueltas por parcela y tarea (filtros campaña y estado, CSV); CSV de horas por trabajador y de tareas realizadas por fechas; archivar hasta una fecha (solo ADMIN) e historial de archivados |

Estados cubiertos: carga, lista vacía, error (con reintentar), éxito (aviso flotante), validación de formulario, sin permiso.

## Reglas implementadas (mismas que la base de datos)
- Estados (migración 010): `Pendiente → Cerrado → Aprobado | Rechazado`. Nadie reabre un parte; Aprobado y Rechazado son finales.
- OPERARIO: ve y crea solo sus partes; edita solo en `Pendiente`; cierra los suyos.
- SUPERVISOR (migración 013): ve todos; crea partes a nombre de cualquier operario activo (para quien olvidó hacerlo);
  **corrige** los Pendientes y Cerrados de cualquiera (no los Aprobados ni Rechazados); cierra cualquiera y aprueba o rechaza
  los Cerrados, también los que él creó, salvo aquellos de los que es titular (esos los revisa un ADMIN).
- Al corregir un parte ya cerrado (supervisor o ADMIN) no se le pueden quitar todas las tareas si no es de mantenimiento en nave.
- ADMIN: ve todos, edita cualquiera en cualquier estado (sigue en su estado), cierra, aprueba/rechaza y borra (con copia en auditoría).
- Cerrar exige un parte válido y, si no es de mantenimiento en nave, al menos una tarea.
- Horas extra (migración 011): las calcula la BD, `max(total − th_jornada, 0)` con `th_jornada` = 8,5 h (desde la 012).
  El operario las ve sin poder cambiarlas; el ADMIN puede corregirlas a mano (se mantienen hasta que cambien horas o pausas).
- Valores iniciales (migración 012): el formulario propone 07:30 – 18:00, 30 min de almuerzo y 90 de comida, leídos de la
  configuración. Si se deja vacío alguno de esos campos, al crear o al editar, se guarda el valor de la configuración;
  para no tener pausa hay que escribir 0. Con esos valores un parte sale con 8,5 h y 0 horas extra.
- "Horas de tareas" (`ht_tareas`): suma de las tareas sin MOTIVOS PERSONALES, calculada al consultar.
- ADMIN y SUPERVISOR pueden crear un parte a nombre de otro operario (solo operarios activos).
- Fin de vuelta (migración 014): en las tareas con parcela y de tipo POR SUPERFICIE o POR HORAS aparece "Fin de vuelta"
  (Sí / No / sin responder). Se puede guardar sin responder, pero no cerrar; en un parte ya cerrado no se puede dejar sin
  responder. En el resto de tareas no se pregunta y se guarda No. El detalle muestra la columna "Fin de vuelta".
- Archivo y vueltas (migración 015):
  - Vuelta = campaña + parcela + tarea; solo cuentan los partes Aprobados. La tarea marcada como fin de vuelta cierra la
    vuelta en curso; si el mismo día hay registros sin fin, cuentan en la vuelta que se cierra. Cada campaña (año agrícola
    desde el 1 de septiembre) empieza de cero.
  - Archivar (solo ADMIN) hasta una fecha, como mucho ayer: no se puede si queda algún parte Pendiente o Cerrado en el
    rango. Las tareas de los Aprobados pasan al archivo agrupadas (sin MOTIVOS PERSONALES ni DESPLAZAMIENTO) y los partes se
    borran; los Rechazados se borran sin archivar. Después no se pueden crear ni modificar partes de esas fechas.
  - Las horas por trabajador se exportan antes de archivar: después ya no están.
  - Los CSV usan `;` y coma decimal para abrirlos en Excel en español.
- Un parte por operario y día. Salida > entrada. Rechazar exige comentario.
- `tot_horas` = (salida − entrada) − almuerzo − comida.

## Decisiones provisionales (supuestos)
| Tema | Decisión del boceto |
|---|---|
| Campo `TIEMPO` | **No se muestra**: su significado sigue sin confirmar en el diseño |
| Parte rechazado | Decidido 28/10: solo lo corrige el ADMIN y sigue en `Rechazado` (no vuelve a `Pendiente`) |
| Login en Supabase | Email + contraseña (cuentas creadas en el Dashboard) y, como alternativa, enlace mágico. El diseño original hablaba de Google |
| Guardado de cabecera + líneas | Una sola llamada a la función `guardar_parte()` (atómica, migración 007b). Solo si no existiera, el boceto recurre al método antiguo en varios pasos |
| Almuerzo / comida | Se piden en minutos y se guardan como `interval` |

## Fuera de alcance (existe en el diseño, no en el boceto)
Partes de mantenimiento (`partes_mant`), gestión de catálogos y usuarios (admin), pantalla de configuración, "Mi perfil", fotos y GPS,
notificaciones y PDF (módulo 8, migración 016).

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
- **Trasladar tal cual**: el flujo de pantallas, las reglas de `rules.js`, la interfaz de datos (`listPartes`, `getParte`, `saveParte`, `cerrarParte`, `revisarParte`, `borrarParte`, `getValoresIniciales`, `listVueltas`, `listTareasResumen`, `listHorasTrabajador`, `listArchivos`, `archivarPartes`) y los mensajes de error de `supabase.js`.
- **Ajustar**: login (Google o email según decidáis) y el formulario para usarlo desde el móvil en el campo. El guardado atómico ya existe: `rpc('guardar_parte')`.
- **Reconstruir**: todo el diseño visual (Lovable usa React + Tailwind); este HTML/JS es desechable.
- **Añadir después**: mantenimiento, administración de catálogos, informes, fotos (Storage) y notificaciones.
