# Supabase — estado y referencia para la app (Lovable)

Proyecto Supabase: `baluwelboftnibtyjrer` (referenciado en `.mcp.json`).

## Migraciones
| Archivo (`supabase/propuesta/`) | Estado | Contenido |
|---|---|---|
| `001_esquema_partes_trabajo.sql` | Aplicada 21/10 | Tablas, tipos, disparadores y RLS base |
| `002_limitar_rls_auto_enable.sql` | Aplicada 21/10 | Quita el permiso público de `rls_auto_enable()` |
| (seed) `../seed/001_catalogos_excel.sql` | Aplicada 22/10 como `003_carga_catalogos_excel` | Catálogos del Excel (operarios con emails reales) |
| `004_roles_y_usuarios.sql` | Aplicada 22/10 | `user_id`, vinculación automática, roles nuevos, último ADMIN protegido, `operarios_nombres()` |
| `004b_enlazar_cuentas_existentes.sql` | Aplicada 22/10 desde el SQL Editor (no figura en el historial) | Enlaza por id las 3 cuentas que ya existían |
| `005_bajas_logicas.sql` | Aplicada 22/10 | `activo`/`fecha_baja`/`baja_por` en catálogos; no se usan registros de baja en partes nuevos; parcela ↔ finca |
| `006_auditoria.sql` | Aplicada 22/10 | Tabla `auditoria` rellenada por disparador |
| `007_funciones_app.sql` | Aplicada 22/10 | `panel_resumen()`, `operarios_sin_parte()` |
| `007b_guardar_parte.sql` | Aplicada 22/10 desde el SQL Editor (no figura en el historial) | `guardar_parte()`: guardado atómico de parte + líneas |

El conector de Supabase usado desde Claude Code bloquea las sentencias con `DELETE`/`DROP`/`UPDATE`;
por eso 004b y 007b se ejecutaron en Dashboard → SQL Editor. Lo ejecutado desde el SQL Editor no queda en
el historial de migraciones: los archivos de esta carpeta son el registro.

Verificado 22/10/2026: T000, T001 y T003 enlazados por id (T002 sin cuenta de login); `guardar_parte()`
probada (crear, editar conservando líneas, rechazo atómico ante error, tarea de baja, supervisor bloqueado).

## Permisos por rol (RLS, probado 22/10/2026 con 21 casos)
| | ADMIN | SUPERVISOR | OPERARIO | Sin sesión |
|---|---|---|---|---|
| Catálogos (`fincas`, `parcelas`, `tareas`, `vehiculos`, `aperos`) | Todo, incluido borrar | Leer, crear, editar, dar de baja | Leer | Nada |
| `operarios` (usuarios) | Todo, incluido borrar | Solo su ficha | Solo su ficha | Nada |
| `operarios_nombres()` | Todos | Todos (código y nombre) | El suyo | — |
| `partes_cab` | Todo, incluido borrar | Leer todos; solo aprobar/rechazar | Crear y leer los suyos; editar en Pendiente | Nada |
| `partes_det` | Todo | Leer | Los de sus partes en Pendiente | Nada |
| `partes_mant` | Todo | Leer, crear, editar | Los suyos | Nada |
| `auditoria` | Leer | Leer (sin `operarios`) | Nada | Nada |

Reglas que impone la BD (no solo la interfaz):
- Nunca queda la app sin un ADMIN activo.
- Un operario no puede aprobar/rechazar ni crear partes a nombre de otro.
- Un supervisor no puede cambiar el contenido de un parte; rechazar exige comentario.
- Un parte por operario y día; salida > entrada; la parcela debe ser de su finca.
- Un registro dado de baja no se puede usar en partes nuevos (los antiguos lo conservan).
- `creado_por`, fechas de creación, `supervisor_revisa`, `fecha_revision`, `fecha_baja`, `baja_por` los fija la BD.
- Cada cambio en catálogos y usuarios queda en `auditoria` (quién, cuándo, antes/después).

## Referencia rápida para la interfaz
- **Usuario conectado**: `select * from operarios` devuelve solo su ficha (ADMIN: todas; filtrar por `user_id = auth.uid()`).
  Rol: `rpc('app_rol')`; código: `rpc('app_cod_ope')`.
- **Nombres de operarios** (listas, partes): `rpc('operarios_nombres')` → `cod_ope, usuario, activo`.
- **Selectores de partes**: catálogos con `.eq('activo', true)`; para mostrar partes antiguos, leer sin filtro.
- **Guardar parte**: `rpc('guardar_parte', { p_id_parte: null | uuid, p_cab: {...}, p_lineas: [...] })`
  (`t_alm`/`t_com` como intervalo, p. ej. `'30 minutes'`; líneas con `id_linea` se actualizan, sin él se crean).
- **Aprobar/rechazar**: `update partes_cab set estado, comentario_supervisor` (la BD sella quién y cuándo).
- **Dar de baja / reactivar**: `update <catálogo> set activo = false | true`.
- **Panel de inicio**: `rpc('panel_resumen')` → JSON con claves según el rol.
- **Historial de un registro**: `select * from auditoria where tabla = 'fincas' and registro = 'MOJ' order by fecha desc`.
- Errores útiles: `23505` duplicado · `23514` regla de datos · `42501` sin permiso · `P0001` regla de negocio (mensaje en español).

## Pendiente (Dashboard, lo hace el usuario)
1. (Hecho) SQL Editor: `004b` y `007b`.
2. Authentication → Sign In / Providers: desactivar "Allow new users to sign up" (las cuentas las crea el ADMIN).
3. Authentication → Passwords: activar la protección de contraseñas filtradas (aviso de Supabase).
4. Alta de usuarios: Authentication → Users → Add user (email = `operarios.email`, Auto Confirm) y fila en `operarios`.
   El enlace por id se hace solo. Una Edge Function para que el ADMIN dé de alta desde la app queda para más adelante.
5. Storage: bucket privado `fotos-partes` (campo `foto` de `partes_cab`), cuando se haga esa función.

## Comprobar la conexión
```
npm install
npm run check:supabase
```
