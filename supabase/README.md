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
| `012_valores_iniciales.sql` | Aplicada 04/11 desde el SQL Editor (no figura en el historial); verificada 18/18 con `pruebas/pruebas_modulo4.sql` | Módulo 4: valores iniciales del parte en `configuracion` (`cfh_ent` 07:30, `cfh_sal` 18:00, `cft_alm` 30, `cft_com` 90), `valores_iniciales_parte()` para todos los roles, campos vacíos → valor de la configuración en `guardar_parte()`; `th_jornada` = 8,5 |

| `013_supervisor_y_auditoria_partes.sql` | Aplicada 04/11 desde el SQL Editor (no figura en el historial); verificada 18/18 con `pruebas/pruebas_modulo5.sql` | Módulo 5: el SUPERVISOR crea partes para cualquier operario activo y corrige los Pendientes y Cerrados; titular activo obligatorio; un parte no Pendiente sin nave conserva al menos una tarea; auditoría de `partes_cab` y `partes_det` (registro = nº de parte); `borrar_parte()` deja la copia por disparador |
| `014_fin_vuelta.sql` | Aplicada 04/11 desde el SQL Editor (no figura en el historial); verificada 10/10 con `pruebas/pruebas_modulo6.sql` | Módulo 6: `partes_det.fin_vuelta` (Sí/No/sin responder) en tareas con parcela y tipo POR SUPERFICIE o POR HORAS (en el resto, No); obligatoria al cerrar y en partes ya cerrados; `requiere_fin_vuelta(partes_det)` para la app |

Decisiones de los módulos 4 a 8 (valores iniciales, supervisor, `fin_vuelta`, archivo de tareas y vueltas, PDF):
`docs/DECISIONES_MODULOS_4_A_8.md`.

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
Con la 013 (04/11): 32 de 32.
La tabla describe el comportamiento actual.

| | ADMIN | SUPERVISOR | OPERARIO | Sin sesión |
|---|---|---|---|---|
| Catálogos (`fincas`, `parcelas`, `tareas`, `vehiculos`, `aperos`) | Todo, incluido borrar | Leer, crear, editar, dar de baja | Leer | Nada |
| `operarios` (usuarios) | Todo, incluido borrar | Solo su ficha | Solo su ficha | Nada |
| `operarios_nombres()` | Todos | Todos (código y nombre) | El suyo | — |
| `partes_cab` (solo vía funciones desde la 010) | Leer todos; crear para cualquiera; editar en cualquier estado; cerrar; aprobar/rechazar; borrar | Leer todos; crear para cualquier operario activo; corregir Pendientes y Cerrados (013); cerrar cualquiera; aprobar/rechazar Cerrados, también los que creó, salvo los suyos como titular | Crear y leer los suyos; editar y cerrar en Pendiente | Nada |
| `partes_det` (solo vía `guardar_parte()` desde la 009) | Todo | Leer; escribir las de partes Pendientes y Cerrados (013) | Los de sus partes en Pendiente | Nada |
| `partes_mant` | Todo | Leer, crear, editar | Los suyos | Nada |
| `auditoria` | Leer | Leer (sin `operarios` ni `configuracion`) | Nada | Nada |

Reglas que impone la BD (no solo la interfaz):
- Nunca queda la app sin un ADMIN activo.
- Un operario no puede aprobar/rechazar ni crear partes a nombre de otro.
- (013) Un supervisor crea partes para cualquier operario activo y corrige (cabecera y tareas) los Pendientes y Cerrados;
  no toca Aprobados ni Rechazados. Rechazar exige comentario.
- Un supervisor no aprueba ni rechaza los partes de los que es titular ni los crea ya revisados; los revisa un ADMIN.
  Sí puede revisar los que creó para otro operario.
- (013) Nadie crea partes a nombre de un operario dado de baja.
- (010) Todo parte nace Pendiente; solo se revisa un parte Cerrado; nadie lo reabre. Un parte Cerrado lo modifican
  SUPERVISOR y ADMIN (013); Aprobados y Rechazados, solo el ADMIN. Cerrar sin nave exige al menos una tarea, y (013) un
  parte que no está Pendiente y no es de nave no puede quedarse sin tareas al corregirlo.
- Un parte por operario y día; salida > entrada; la parcela debe ser de su finca.
- (009) Horas y pausas en múltiplos de 15 min; `h_ext` ≥ 0 en cuartos de hora.
- (009) Líneas dentro de la jornada y sin solapes; la primera (sin contar MOTIVOS PERSONALES) es un
  DESPLAZAMIENTO con vehículo; cambiar de finca exige otro DESPLAZAMIENTO; MOTIVOS PERSONALES solo lleva horas;
  el resto de tareas exige finca. Obliga también al ADMIN y se comprueba al confirmar cada guardado.
- Un registro dado de baja no se puede usar en partes nuevos (los antiguos lo conservan).
- `creado_por`, fechas de creación, `supervisor_revisa`, `fecha_revision`, `fecha_baja`, `baja_por` los fija la BD.
- Cada cambio en catálogos, usuarios, configuración y (013) partes y tareas queda en `auditoria` (quién, cuándo, antes/después).

## Referencia rápida para la interfaz
- **Usuario conectado**: `select * from operarios` devuelve solo su ficha (ADMIN: todas; filtrar por `user_id = auth.uid()`).
  Rol: `rpc('app_rol')`; código: `rpc('app_cod_ope')`.
- **Nombres de operarios** (listas, partes): `rpc('operarios_nombres')` → `cod_ope, usuario, activo`.
- **Selectores de partes**: catálogos con `.eq('activo', true)`; para mostrar partes antiguos, leer sin filtro.
- **Guardar parte**: `rpc('guardar_parte', { p_id_parte: null | uuid, p_cab: {...}, p_lineas: [...] })`
  (`t_alm`/`t_com` como intervalo, p. ej. `'30 minutes'`; líneas con `id_linea` se actualizan, sin él se crean).
  (012) `p_cab` va siempre completo: `h_ent`, `h_sal`, `t_alm` o `t_com` vacíos o ausentes toman el valor de la
  configuración, al crear y al editar; 0 minutos se envía como `'0 minutes'`.
- **Fin de vuelta** (014): cada línea de `guardar_parte` lleva `fin_vuelta` (`true` / `false` / `null` = sin responder).
  Para saber en qué tareas preguntarlo: `partes_det(*, requiere_fin_vuelta)`; en las demás la BD guarda `false`.
  Cerrar exige respuesta en todas las que la requieren; el error dice cuáles faltan.
- **Valores iniciales del formulario** (012): `rpc('valores_iniciales_parte')` → `{h_ent, h_sal, t_alm_min, t_com_min}`,
  para cualquier rol. La tabla `configuracion` (incluidos estos valores y `th_jornada`) solo la lee y modifica el ADMIN:
  `update configuracion set valor = '08:00' where clave = 'cfh_ent'`.
- **Cerrar**: `rpc('cerrar_parte', { p_id_parte })`. **Aprobar/rechazar**: `rpc('revisar_parte', { p_id_parte, p_estado: 'Aprobado' | 'Rechazado', p_comentario })`.
  **Borrar** (ADMIN): `rpc('borrar_parte', { p_id_parte })`, deja copia en `auditoria` (desde la 013 la escribe un disparador, también al borrar desde el SQL Editor). La BD sella quién y cuándo cierra y revisa.
  Estados: Pendiente → Cerrado → Aprobado | Rechazado, sin vuelta atrás (también desde el SQL Editor).
- **Dar de baja / reactivar**: `update <catálogo> set activo = false | true`.
- **Panel de inicio**: `rpc('panel_resumen')` → JSON con claves según el rol.
- **Historial de un registro**: `select * from auditoria where tabla = 'fincas' and registro = 'MOJ' order by fecha desc`.
  Historial de un parte con sus tareas (013): `... where tabla in ('partes_cab', 'partes_det') and registro = '<nº de parte>'`.
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
`pruebas_modulo1.sql` con la 011: 31/31 (M19 había quedado anticuada por la 010, porque el UPDATE directo ya afecta
a 0 filas; se reescribió como M19 por la API, 0 filas, y M19b desde el SQL Editor, bloqueado por la validación del parte).
Para la 012 (04/11): `pruebas_modulo4.sql` (18 casos, nuevo). Los demás scripts envían la comida a 0 de forma explícita
(desde la 012 una comida vacía vale 90 min) y `pruebas_modulo3.sql` fija `th_jornada` = 8 al empezar, para que sus
resultados no dependan de la configuración; funcionan antes y después de la 012.
Para la 013: `pruebas_modulo5.sql` (18 casos, nuevo); en `pruebas_modulo1.sql`, S02 y S03 pasan a "OK" (el supervisor
corrige partes en Pendiente; antes de la 013 salen bloqueadas).
Para la 014: `pruebas_modulo6.sql` (10 casos, nuevo); en `pruebas_por_rol.sql` la línea de ejemplo lleva `fin_vuelta = false`
(tiene parcela y se cierra); funciona antes y después de la 014.
Resultados con la 014 aplicada (04/11): módulo 6 10/10, por rol 32/32, módulo 1 32/32, módulo 2 32/32, módulo 3 19/19, módulo 4 18/18 y módulo 5 18/18.
(Los módulos 2 y 4 se ejecutaron desde Claude Code; el conector rechaza los scripts que contienen DELETE, por eso
los módulos 1, 3 y 5 se ejecutaron en el SQL Editor.)
Resultados con la 013 aplicada (04/11): módulo 5 18/18, módulo 4 18/18, módulo 3 19/19, módulo 2 32/32 (D06: una sola
copia en auditoría con sus 2 tareas), módulo 1 32/32 y por rol 32/32.
Resultados con la 012 aplicada (04/11): módulo 4 18/18, módulo 3 19/19, módulo 1 32/32 (el recuento real del script
es 32: M01–M22 con M19b, S01–S04, O01–O02 y D01–D03), módulo 2 32/32 y por rol 32/32.
