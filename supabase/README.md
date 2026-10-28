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
| `008_supervisor_sin_autorrevision.sql` | Aplicada y verificada 28/10 (31/31 casos) | El supervisor no toca líneas de ningún parte (salvo al crear el suyo) ni aprueba/rechaza sus propios partes |
| `009a_borrar_partes_prueba.sql` | Ejecutada 28/10 desde el SQL Editor | Borra los partes de prueba nº 1, 2 y 4 (quedan 0 partes y 0 líneas) |
| `009_lineas_y_validaciones.sql` | Aplicada 28/10 desde el SQL Editor (no figura en el historial); verificada 30/30 con `pruebas/pruebas_modulo1.sql` | Módulo 1: tipos DESPLAZAMIENTO / MOTIVOS PERSONALES (TD001, TP001), cabecera sin finca/vehículo/tiempo, 15 min, `validar_parte()`, líneas solo vía `guardar_parte()` |
| `010a_estado_cerrado.sql` | Aplicada 28/10 desde el SQL Editor (no figura en el historial) | Añade el estado `Cerrado` |
| `010_estados_y_funciones.sql` | Aplicada 28/10 desde el SQL Editor (no figura en el historial); objetos y permisos comprobados; verificada 32/32 con `pruebas/pruebas_modulo2.sql` | Módulo 2: Pendiente → Cerrado → Aprobado/Rechazado sin vuelta atrás; `cerrar_parte()`, `revisar_parte()`, `borrar_parte()`; sin escritura directa en `partes_cab` |
| `011_configuracion_y_horas_extra.sql` | Aplicada 28/10 desde el SQL Editor (no figura en el historial); objetos y permisos comprobados; verificada 19/19 con `pruebas/pruebas_modulo3.sql` | Módulo 3: tabla `configuracion` (`th_jornada` = 8, solo ADMIN), `h_ext` calculado por la BD (corrección manual solo ADMIN), `ht_tareas` al consultar |

El conector de Supabase usado desde Claude Code bloquea las sentencias con `DELETE`/`DROP`/`UPDATE`;
por eso 004b y 007b se ejecutaron en Dashboard → SQL Editor. Lo ejecutado desde el SQL Editor no queda en
el historial de migraciones: los archivos de esta carpeta son el registro.

Verificado 22/10/2026: T000, T001 y T003 enlazados por id (T002 sin cuenta de login); `guardar_parte()`
probada (crear, editar conservando líneas, rechazo atómico ante error, tarea de baja, supervisor bloqueado).

## Permisos por rol (RLS + disparadores)
Probado 22/10/2026 con 21 casos y 28/10/2026 con 31 casos (`pruebas/pruebas_por_rol.sql`).
El 28/10 cumplieron 28 de 31: fallaron S08, S10 y S11 (supervisor sobre sus propios partes).
La migración 008 (aplicada 28/10) los corrige: repetidas las pruebas tras aplicarla, cumplen 31 de 31.
Repetidas con la 009 aplicada (script adaptado): 31 de 31. Con la 010 (script adaptado, 32 casos): 32 de 32.
La tabla describe el comportamiento actual.

| | ADMIN | SUPERVISOR | OPERARIO | Sin sesión |
|---|---|---|---|---|
| Catálogos (`fincas`, `parcelas`, `tareas`, `vehiculos`, `aperos`) | Todo, incluido borrar | Leer, crear, editar, dar de baja | Leer | Nada |
| `operarios` (usuarios) | Todo, incluido borrar | Solo su ficha | Solo su ficha | Nada |
| `operarios_nombres()` | Todos | Todos (código y nombre) | El suyo | — |
| `partes_cab` (solo vía funciones desde la 010) | Leer todos; crear para cualquiera; editar en cualquier estado; cerrar; aprobar/rechazar; borrar | Leer todos; crear los suyos; cerrar cualquiera; aprobar/rechazar Cerrados de otros | Crear y leer los suyos; editar y cerrar en Pendiente | Nada |
| `partes_det` (solo vía `guardar_parte()` desde la 009) | Todo | Leer; añadir líneas solo al crear su propio parte | Los de sus partes en Pendiente | Nada |
| `partes_mant` | Todo | Leer, crear, editar | Los suyos | Nada |
| `auditoria` | Leer | Leer (sin `operarios`) | Nada | Nada |

Reglas que impone la BD (no solo la interfaz):
- Nunca queda la app sin un ADMIN activo.
- Un operario no puede aprobar/rechazar ni crear partes a nombre de otro.
- Un supervisor no puede cambiar el contenido de un parte, ni cabecera ni líneas, tampoco de los suyos; rechazar exige comentario.
- Un supervisor no aprueba ni rechaza sus propios partes ni los crea ya revisados; los revisa un ADMIN.
- (010) Todo parte nace Pendiente; solo se revisa un parte Cerrado; nadie lo reabre. Un parte que no está
  Pendiente solo lo modifica un ADMIN (cabecera y tareas). Cerrar sin nave exige al menos una tarea.
- Un parte por operario y día; salida > entrada; la parcela debe ser de su finca.
- (009) Horas y pausas en múltiplos de 15 min; `h_ext` ≥ 0 en cuartos de hora.
- (009) Líneas dentro de la jornada y sin solapes; la primera (sin contar MOTIVOS PERSONALES) es un
  DESPLAZAMIENTO con vehículo; cambiar de finca exige otro DESPLAZAMIENTO; MOTIVOS PERSONALES solo lleva horas;
  el resto de tareas exige finca. Obliga también al ADMIN y se comprueba al confirmar cada guardado.
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
- **Cerrar**: `rpc('cerrar_parte', { p_id_parte })`. **Aprobar/rechazar**: `rpc('revisar_parte', { p_id_parte, p_estado: 'Aprobado' | 'Rechazado', p_comentario })`.
  **Borrar** (ADMIN): `rpc('borrar_parte', { p_id_parte })`, deja copia en `auditoria`. La BD sella quién y cuándo cierra y revisa.
  Estados: Pendiente → Cerrado → Aprobado | Rechazado, sin vuelta atrás (también desde el SQL Editor).
- **Dar de baja / reactivar**: `update <catálogo> set activo = false | true`.
- **Panel de inicio**: `rpc('panel_resumen')` → JSON con claves según el rol.
- **Historial de un registro**: `select * from auditoria where tabla = 'fincas' and registro = 'MOJ' order by fecha desc`.
- Errores útiles: `23505` duplicado · `23514` regla de datos · `42501` sin permiso · `P0001` regla de negocio (mensaje en español).

## Pendiente (Dashboard, lo hace el usuario)
1. (Hecho) SQL Editor: `004b` y `007b`.
2. (Hecho, comprobado 28/10) Registro libre desactivado: las cuentas las crea el ADMIN.
3. Authentication → Passwords: activar la protección de contraseñas filtradas (sigue desactivada el 28/10).
4. Alta de usuarios: Authentication → Users → Add user (email = `operarios.email`, Auto Confirm) y fila en `operarios`.
   El enlace por id se hace solo. Una Edge Function para que el ADMIN dé de alta desde la app queda para más adelante.
5. Storage: bucket privado `fotos-partes` (campo `foto` de `partes_cab`), cuando se haga esa función.

## Comprobar la conexión
```
npm install
npm run check:supabase
```

## Probar permisos y reglas por rol
`pruebas/pruebas_por_rol.sql`: pegarlo en Dashboard → SQL Editor → Run. Simula T003 (OPERARIO), T001
(SUPERVISOR) y T000 (ADMIN) con 31 casos. Termina con un error `RESULTADOS(rollback) [...]` a propósito:
ese error muestra los resultados y deshace todos los cambios (solo puede saltar la numeración de `num_parte`).
Repetirlo después de cada migración. El conector de Claude Code no puede ejecutarlo porque contiene `UPDATE`/`DELETE`.
Desde el 28/10 el script está adaptado a la migración 009 (cabecera sin finca, líneas que empiezan con DESPLAZAMIENTO):
ejecutarlo solo con la 009 aplicada. Las reglas del módulo 1 se prueban en `pruebas/pruebas_modulo1.sql`
(30/30 el 28/10 tras aplicar la 009), las del módulo 2 en `pruebas/pruebas_modulo2.sql` (32/32 el 28/10)
y las del módulo 3 en `pruebas/pruebas_modulo3.sql` (19/19 el 28/10).
`pruebas_por_rol.sql`: 31/31 con la 009 y 32/32 con la 010 y con la 011 (28/10).
`pruebas_modulo1.sql` con la 011: 29/30; M19 había quedado anticuada por la 010 (el UPDATE directo ya afecta a 0 filas)
y se ha reescrito como M19 (API, 0 filas) + M19b (SQL Editor, bloqueado). Pendiente repetirla.
