# Prompt para Lovable — Partes de Trabajo (Escribano Cabañero)

Cómo usarlo:
- Pega el **Bloque 0** en el *Knowledge* del proyecto de Lovable (o como primer mensaje). Los demás bloques, uno por
  mensaje y en orden, comprobando cada pantalla antes de pasar a la siguiente.
- Si Lovable se desvía, responde con el apartado correspondiente de "Lo que NO hay que hacer".
- Fuente: base de datos real (migraciones 001–021), `app/js/rules.js`, `app/js/data/supabase.js` y el boceto `app/`.

---

## Bloque 0 · Contexto y reglas fijas (pegar siempre primero)

```
Vas a construir el FRONTEND de una app interna de "Partes de Trabajo" para una empresa agrícola
(Escribano Cabañero). Cada operario registra su jornada diaria y las tareas que hace, en orden de hora.
Sirve para controlar el gasto por parcela; no es el registro horario oficial. Idioma: español de España.

STACK: React + TypeScript + Tailwind + shadcn/ui + supabase-js v2. Usuarios principales: operarios en el
campo, desde el MÓVIL. Supervisores y administradores, también desde ordenador.

BACKEND YA HECHO (no lo cambies):
- El proyecto Supabase ya existe con todas las tablas, RLS, disparadores, funciones y la Edge Function
  "generar-pdf". NO crees tablas, columnas, migraciones, políticas RLS, funciones ni Edge Functions.
  NO uses datos de ejemplo inventados: lee siempre de Supabase.
- Conéctate con la URL del proyecto y la clave PUBLISHABLE (anon). Nunca uses la service_role.
- SIN SESIÓN NO SE LEE NADA: no consultes tablas ni llames a rpc antes de iniciar sesión (la BD responde
  42501). Si con la sesión ya iniciada una petición devuelve 401 o 42501 porque la sesión caducó, vuelve
  al login.
- Con sesión, la app solo LEE las tablas, salvo estas escrituras directas (las políticas deciden quién):
  catálogos (fincas, parcelas, tareas, vehiculos, aperos) y operarios, y configuracion (solo ADMIN).
  Todo lo demás (partes_cab, partes_det, auditoria, partes_pdf, archivos_partes, tareas_realizadas
  y las vistas) es de solo lectura: un insert/update/delete directo da 42501.
- La base de datos es quien decide: valida todo otra vez y devuelve mensajes en español. La validación en
  pantalla es solo una ayuda.
- Escrituras de partes SOLO mediante RPC. Nunca insert/update/delete directo en partes_cab ni partes_det
  (la BD lo bloquea):
    rpc('guardar_cabecera', { p_id_parte: null | uuid, p_cab })   -> uuid del parte
    rpc('guardar_linea',    { p_id_parte: uuid, p_linea })        -> uuid de la línea
    rpc('borrar_linea',     { p_id_linea: uuid })
    rpc('cerrar_parte',     { p_id_parte })
    rpc('revisar_parte',    { p_id_parte, p_estado: 'Aprobado'|'Rechazado', p_comentario })
    rpc('borrar_parte',     { p_id_parte })                        (solo ADMIN)
    rpc('archivar_partes',  { p_hasta: 'AAAA-MM-DD' })             (solo ADMIN)
  No uses rpc('guardar_parte'): es la forma antigua (todo el parte de una vez); se mantiene solo por
  compatibilidad.

ROLES (columna operarios.rol_app): ADMIN, SUPERVISOR, OPERARIO.
- OPERARIO: ve y crea solo sus partes; los edita y cierra solo en estado Pendiente.
- SUPERVISOR: ve todos; crea partes a nombre de cualquier operario activo; corrige partes Pendientes y
  Cerrados (no Aprobados ni Rechazados); cierra cualquiera; aprueba o rechaza los Cerrados, salvo los suyos
  como titular (esos los revisa un ADMIN).
- ADMIN: todo; edita en cualquier estado (el parte sigue en su estado); borra partes; archiva.
ESTADOS: Pendiente -> Cerrado -> Aprobado | Rechazado. Nadie reabre un parte. Rechazar exige comentario.

LO QUE NO HAY QUE HACER (errores del primer boceto que hay que evitar):
- La cabecera del parte NO tiene finca, vehículo, "tiempo" ni casilla de "mantenimiento nave".
- NO existe una tabla ni una pestaña aparte de mantenimiento: MANTENIMIENTO NAVE y MANTENIMIENTO VEHÍCULOS
  son tipos de TAREA y van en las líneas, mezclados con el resto, en orden de hora.
- El formulario del parte tiene DOS pestañas (Jornada y Líneas del parte), no tres.
- No hay pantalla de registro (sign up): las cuentas las crea un ADMIN en Supabase.
- No hay cultivos, empresas, cuadrillas, supervisor asignado a cada operario, fotos, GPS, notificaciones ni
  importes. No los añadas.
- No hay botón de "reabrir" ni de pasar un parte a Pendiente.
- En esta fase NO hay pantallas de gestión de catálogos, usuarios ni configuración.
- Las horas no se escriben libremente: solo en cuartos de hora (:00, :15, :30, :45).
```

---

## Bloque 1 · Datos y sesión

```
TABLAS QUE LEE LA APP (nombres exactos; RLS ya filtra lo que ve cada rol):
- operarios(cod_ope, usuario, email, rol_app, activo, user_id)
  Ficha del usuario conectado: .from('operarios').select('cod_ope, usuario, email, rol_app, activo')
  .or(`user_id.eq.${user.id},and(user_id.is.null,email.eq."${email}")`).maybeSingle().
  Si no hay ficha o activo = false: mensaje "El email X no está dado de alta como operario activo" y
  cerrar la sesión. Nombres de operarios para listas y filtros: rpc('operarios_nombres') -> cod_ope,
  usuario, activo.
- fincas(cod_fin, finca, activo)
- parcelas(cod_par, finca -> fincas.cod_fin, nom_parc, superficie, activo)
- tareas(cod_tar, tareas [nombre], tipo, activo). Tipos posibles, exactos:
  'DESPLAZAMIENTO', 'POR HORAS', 'POR SUPERFICIE (HAS)', 'MOTIVOS PERSONALES',
  'MANTENIMIENTO NAVE', 'MANTENIMIENTO VEHÍCULOS'
- vehiculos(id_mat, alias, equipo, tipo, activo)  — mostrar "alias · equipo"
- aperos(id_bas, alias, equipo, tipo, activo)     — mostrar "alias · equipo"
  En los selectores de partes NUEVOS solo los activos; para mostrar partes antiguos, leer sin filtrar.
- partes_cab(id_parte, num_parte, operario, fecha, h_ent, h_sal, t_alm [interval], t_com [interval],
  tot_horas, h_ext, h_ext_manual, obs, estado, creado_por, fch_creacion, cerrado_por, fecha_cierre,
  supervisor_revisa, fecha_revision, comentario_supervisor)
  Lista: .from('partes_cab').select('*, ht_tareas, lineas:partes_det(finca)')
          .order('fecha', {ascending:false}).order('num_parte', {ascending:false})
  Filtro por finca (la cabecera no tiene finca): select('*, ht_tareas, lineas:partes_det(finca),
  filtro:partes_det!inner(finca)').eq('filtro.finca', cod).
  Detalle: .select('*, ht_tareas, partes_det(*, requiere_fin_vuelta)').eq('id_parte', id).maybeSingle()
  Las líneas se muestran SIEMPRE ordenadas por h_ini.
- partes_det(id_linea, id_parte, tarea, finca, parcela, vehiculo, apero, h_ini, h_fin, t_horas, obs,
  fin_vuelta [true | false | null = sin responder])
- Valores iniciales del formulario: rpc('valores_iniciales_parte') -> {h_ent, h_sal, t_alm_min, t_com_min}
  (hoy 07:30, 18:00, 30 y 90).
- Horas de jornada para calcular las horas extra (solo la ve el ADMIN):
  .from('configuracion').select('valor').eq('clave','th_jornada') -> 8,5.
Supabase devuelve como mucho 1000 filas por consulta: pagina con .range() en listados y exportaciones.

FORMATO PARA GUARDAR
p_cab = { operario (solo ADMIN/SUPERVISOR al crear para otro; si no, se omite), fecha 'AAAA-MM-DD',
          h_ent 'HH:MM', h_sal 'HH:MM', t_alm '30 minutes', t_com '90 minutes', obs,
          h_ext y h_ext_manual (solo si es ADMIN) }
  Un campo de hora o de pausa vacío se envía como null y la BD pone el valor de la configuración.
  Una pausa de 0 se envía como '0 minutes'.
p_linea = { id_linea (omitir si es nueva), tarea, finca, parcela, vehiculo, apero,
            h_ini 'HH:MM', h_fin 'HH:MM', obs, fin_vuelta true|false|null }
  Los campos que no aplican al tipo de tarea se envían vacíos ('' o null).

ERRORES (mostrar siempre en un aviso dentro del formulario, sin perder lo escrito):
- P0001: regla de negocio. Mostrar error.message TAL CUAL (ya viene en español y dice qué línea falla).
- 23505: "Ya existe un parte de este operario para esa fecha (un parte por día)."
- 23514 según el texto del error:
    cuartos_hora  -> "Las horas y duraciones deben ir en intervalos de 15 minutos."
    horas_ok      -> "La hora de fin debe ser posterior a la de inicio."
    pausas_ok     -> "El almuerzo y la comida no pueden ser negativos ni sumar más que la jornada."
    h_ext_ok      -> "Las horas extra deben ser 0 o más, en múltiplos de 0,25 h."
    rechazo_comentado -> "Para rechazar hay que escribir un comentario."
- 42501: "No tienes permiso para esta operación."
- Error de red: mensaje y botón "Reintentar".

LOGIN: email + contraseña (signInWithPassword) y, como alternativa, "Enviarme un enlace" (signInWithOtp
con emailRedirectTo = origen de la app). Sin registro ni "crear cuenta".
```

---

## Bloque 2 · Navegación, Inicio, Lista y Detalle

```
NAVEGACIÓN (barra inferior en móvil, lateral en escritorio). Arriba: nombre del usuario, rol y "Salir".
  Inicio · Partes ("Mis partes" para OPERARIO, "Todos los partes" para los demás) · Nuevo parte ·
  Vueltas y archivo (solo ADMIN y SUPERVISOR)

RUTAS: /login, /inicio, /partes, /partes/nuevo, /partes/:id, /partes/:id/editar (?tab=lineas abre la
segunda pestaña), /archivo.

INICIO: todos los datos salen de UNA llamada, rpc('panel_resumen') -> JSON. No los calcules en pantalla.
- Para todos: rol, cod_ope, hoy, partes_por_estado {Pendiente: n, ...} (de los partes que ve el usuario),
  mi_parte_hoy {id_parte, num_parte, estado} o null, ultimos_partes (5: id_parte, num_parte, operario,
  fecha, estado, tot_horas, comentario_supervisor).
- Solo ADMIN y SUPERVISOR: pendientes_revision (Cerrados), sin_cerrar (Pendientes), partes_hoy,
  horas_semana (suma de tot_horas de LUNES A DOMINGO de la semana actual), horas_semana_por_finca
  [{finca, nombre, horas}] (horas de las líneas de esa misma semana), operarios_sin_parte_hoy
  [{cod_ope, usuario}], maestros_activos {fincas, parcelas, tareas, vehiculos, aperos}.
- Solo ADMIN: usuarios {activos, inactivos, sin_cuenta_login}.
Qué mostrar:
- Contadores por estado (Pendiente, Cerrado, Aprobado, Rechazado).
- OPERARIO: aviso de sus partes sin cerrar (Pendientes) y de los Rechazados; atajo "Parte de hoy"
  (abre mi_parte_hoy o crea uno nuevo).
- ADMIN y SUPERVISOR: aviso "N partes cerrados por revisar", "Horas esta semana", "Horas por finca esta
  semana", "Sin parte hoy" (con "Crear parte" para ese operario) y los maestros activos.
- Últimos 5 partes.

LISTA DE PARTES
- Filtros: estado, operario (solo gestores), finca (partes con alguna tarea en esa finca), desde, hasta.
- Cada fila o tarjeta: nº de parte, fecha, operario, entrada–salida, total de horas, horas de tareas
  (ht_tareas), fincas de sus líneas y una etiqueta de estado con color (Pendiente ámbar, Cerrado azul,
  Aprobado verde, Rechazado rojo).
- Estados de pantalla: cargando, vacío ("No hay partes con estos filtros"), error con reintentar.

DETALLE DEL PARTE
- Cabecera: nº, fecha, operario, entrada, salida, almuerzo, comida, total, horas de tareas, horas extra,
  observaciones, estado; quién lo creó, quién lo cerró y cuándo; quién lo revisó, cuándo y comentario.
- Tabla de líneas ordenada por hora: Inicio, Fin, Horas, Tarea (con su tipo), Finca, Parcela, Vehículo,
  Apero, Fin de vuelta (Sí / No / "sin responder", solo si requiere_fin_vuelta), Obs.
  En móvil, cada línea es una tarjeta.
- Botones según permisos (ocúltalos si no se pueden usar):
  · "Editar jornada" y "Editar líneas": según los permisos de edición del Bloque 0. Si no se puede editar,
    explica por qué (p. ej. "Este parte está Aprobado y ya no lo puedes editar").
  · "Cerrar parte": en Pendiente, para el titular, SUPERVISOR o ADMIN. Pide confirmación ("Después ya no
    podrás modificarlo").
  · "Aprobar" / "Rechazar": ADMIN o SUPERVISOR en partes Cerrados; un SUPERVISOR no revisa los suyos.
    Rechazar abre un diálogo con un comentario obligatorio.
  · "Borrar": solo ADMIN, con confirmación.
  · "Generar PDF": ver Bloque 4.
```

---

## Bloque 3 · Formulario del parte (lo más importante)

```
El parte se edita en DOS PESTAÑAS dentro de la misma pantalla: "Jornada" y "Líneas del parte (N)".
La jornada y cada línea se GUARDAN POR SEPARADO, en el momento, al pulsar "Aceptar". No hay un botón
"Guardar parte" al final.

PESTAÑA 1 · JORNADA
Campos:
- Operario: solo ADMIN y SUPERVISOR, y solo al crear (lista de operarios activos). El OPERARIO no lo ve:
  el parte es suyo.
- Fecha (hoy por defecto).
- Entrada y Salida: selector de cuartos de hora (07:00, 07:15...), no un campo de texto libre.
  Se proponen los valores iniciales (07:30 y 18:00).
- Almuerzo y Comida en minutos (0, 15, 30... ; se proponen 30 y 90).
- Observaciones.
- Horas extra: el OPERARIO y el SUPERVISOR solo las ven (las calcula la BD: total − 8,5, mínimo 0).
  El ADMIN tiene la casilla "Corregir a mano" y un campo en múltiplos de 0,25.
RESUMEN (panel junto al formulario, se actualiza al escribir):
  Total jornada = (salida − entrada) − almuerzo − comida
  Horas de tareas (todas salvo MOTIVOS PERSONALES y mantenimientos)
  Horas de mantenimiento (MANTENIMIENTO NAVE + MANTENIMIENTO VEHÍCULOS)
  Motivos personales
  Sin asignar a líneas = total − horas de todas las líneas (mínimo 0)
  Nº de líneas
  Horas extra
Botón "Aceptar jornada":
- Parte nuevo: rpc guardar_cabecera(null, cab) -> crea el parte (estado Pendiente), cambia la URL a
  /partes/:id/editar?tab=lineas y abre la pestaña 2.
- Parte existente: guardar_cabecera(id, cab). Si acortar la jornada deja una línea fuera, la BD lo
  rechaza: mostrar el mensaje.
La pestaña "Líneas del parte" está desactivada hasta que la jornada se acepta por primera vez.

PESTAÑA 2 · LÍNEAS DEL PARTE
- Lista de las líneas guardadas, ORDENADAS POR HORA DE INICIO, con botones "Editar" y "Quitar".
- Botón "Añadir línea". Solo puede haber UN editor de línea abierto a la vez (nueva o editando una).
  La línea que se edita se resalta en la lista.
- Editor de línea: Tarea (lista con nombre y tipo), Inicio, Fin (cuartos de hora), y los campos que
  correspondan al tipo de tarea (tabla de abajo), Observaciones. Botones "Aceptar" y "Cancelar".
- "Aceptar": rpc guardar_linea(id_parte, linea). Si va bien, la línea entra en la lista, se cierra el
  editor y se actualiza el resumen. Si falla, el editor sigue abierto con lo escrito y el mensaje de
  la BD debajo.
- "Quitar": confirmar y rpc borrar_linea(id_linea). La BD lo rechaza si el resto deja de ser válido (p. ej.
  quitar el DESPLAZAMIENTO del que dependen las tareas siguientes): mostrar el mensaje.
- Al salir de la pantalla (otra ruta, botón atrás o cerrar la pestaña) con una línea abierta sin aceptar,
  preguntar "Tienes una línea sin aceptar. ¿Salir y perderla?". Lo mismo si la jornada tiene cambios sin
  aceptar.
- Botón "Terminado: ver el parte" -> detalle.

VALORES PROPUESTOS EN UNA LÍNEA NUEVA (el usuario los puede cambiar):
- Primera línea: tarea DESPLAZAMIENTO e inicio = hora de entrada.
- Siguientes: inicio = fin de la última línea; finca, vehículo y apero = los de la última línea que tenga
  finca.
- Al cambiar de finca se vacía la parcela y la lista de parcelas muestra solo las de esa finca.

CAMPOS SEGÚN EL TIPO DE TAREA (ocultar los que no aplican y no enviarlos):
| Tipo                     | Finca        | Parcela  | Vehículo     | Apero    | Fin de vuelta      |
|--------------------------|--------------|----------|--------------|----------|--------------------|
| DESPLAZAMIENTO           | obligatoria  | opcional | OBLIGATORIO  | opcional | no                 |
| POR HORAS                | obligatoria  | opcional | opcional     | opcional | sí, si hay parcela |
| POR SUPERFICIE (HAS)     | obligatoria  | opcional | opcional     | opcional | sí, si hay parcela |
| MOTIVOS PERSONALES       | —            | —        | —            | —        | no (solo horas)    |
| MANTENIMIENTO NAVE       | —            | —        | —            | —        | no (solo horas)    |
| MANTENIMIENTO VEHÍCULOS  | —            | —        | vehículo O apero (uno al menos) | no      |
"Fin de vuelta": selector "Sí, termina la vuelta" / "No" / "— Sin responder —". Se puede guardar sin
responder, pero no cerrar el parte.

REGLAS QUE COMPRUEBA LA BD AL ACEPTAR CADA LÍNEA (repítelas en pantalla como ayuda, antes de llamar):
1. Horas en cuartos de hora; fin posterior al inicio; dentro de la jornada (entrada–salida).
2. Orden: una línea NUEVA empieza cuando acaba la última o más tarde. Una línea EDITADA debe seguir entre
   el fin de la anterior y el inicio de la siguiente. No hay solapes.
3. La primera tarea (sin contar MOTIVOS PERSONALES) es un DESPLAZAMIENTO o un MANTENIMIENTO NAVE.
   MANTENIMIENTO VEHÍCULOS no puede ser la primera.
4. Finca en curso: la fija el último DESPLAZAMIENTO. Una tarea en otra finca exige antes un DESPLAZAMIENTO
   a esa finca. Tras un MANTENIMIENTO NAVE, para trabajar en una finca hace falta un DESPLAZAMIENTO.
   Los mantenimientos y los motivos personales no cambian la finca en curso.
5. La parcela tiene que ser de la finca de la línea.
Mensajes de ejemplo que llegan de la BD: "la primera tarea (sin contar MOTIVOS PERSONALES) debe ser un
DESPLAZAMIENTO o un MANTENIMIENTO NAVE", "para trabajar en la finca CAM hace falta antes un DESPLAZAMIENTO",
"La tarea nueva debe empezar a las 09:00 o más tarde...", "un DESPLAZAMIENTO necesita vehículo".

CERRAR: exige al menos una tarea que no sea MOTIVOS PERSONALES y "Fin de vuelta" respondido en todas las
líneas que lo piden. Si falta, la BD dice cuáles.

MÓVIL (prioridad): una columna, botones grandes (mín. 44 px), selectores en lugar de teclear, las
pestañas siempre visibles arriba, el resumen plegable bajo la jornada y "Aceptar" fijo abajo en el editor.
```

---

## Bloque 4 · Vueltas y archivo, y PDF

```
PDF DEL PARTE (en el detalle)
- Botón "Generar PDF": solo ADMIN y SUPERVISOR, y solo en partes Aprobados.
  supabase.functions.invoke('generar-pdf', { body: { id_parte } }) -> { url, ruta, version, nuevo }.
  Abrir url en una pestaña nueva (caduca en 5 minutos). nuevo = false: el parte no cambió y se devuelve
  el último PDF. Errores: 403 sin permiso, 400 regla (texto en error).
- Lista "Versiones del PDF" (la ven ADMIN, SUPERVISOR y el operario titular):
  .from('partes_pdf').select('id, version, estado, ruta, solicitado, solicitado_por, generado, error')
  .eq('id_parte', id).order('version', {ascending:false}). Botón "Abrir":
  storage.from('partes-pdf').createSignedUrl(ruta, 300).

PANTALLA "VUELTAS Y ARCHIVO" (solo ADMIN y SUPERVISOR), en secciones o pestañas:
1. Vueltas: .from('vueltas') -> campana, finca, parcela, nom_parcela, tarea, nom_tarea, num_vuelta,
   estado ('Abierta'|'Cerrada'), fecha_inicio, fecha_fin, operario_fin, horas, registros, operarios.
   Filtros campaña y estado. Exportar CSV.
2. Tareas realizadas por fechas: .from('tareas_resumen') filtrando fec_tarea. Exportar CSV.
3. Horas por trabajador por fechas: .from('horas_trabajador') -> parte, operario, fecha, h_ent, h_sal,
   t_alm_min, t_com_min, estado. Exportar CSV. Aviso: "Exporta las horas antes de archivar: después ya no
   están".
4. Archivar (solo ADMIN): fecha "hasta", como mucho ayer y posterior al último archivado
   (.from('archivos_partes'), el de mayor hasta). Confirmación doble: no se puede deshacer y borra los
   partes del rango. rpc('archivar_partes') -> {hasta, partes, lineas, filas, rechazados}; mostrar ese
   resumen. Debajo, historial de archivados.
5. PDF de partes por fechas: .from('partes_pdf').eq('estado','Generado') filtrando por fecha, la última
   versión de cada parte, con "Abrir". Incluye partes ya archivados.
CSV: separador ';', coma decimal, UTF-8 con BOM (para Excel en español). Si un texto empieza por
= + - @, anteponer un apóstrofo.
```

---

## Bloque 5 · Estilo y comprobación final

```
ESTILO: sobrio y de trabajo, no de marketing. Verde oscuro como color principal (#2f6b3a), fondo claro,
buen contraste al sol, texto mínimo de 16 px en móvil. Estados con color y texto (no solo color).
Fechas dd/mm/aaaa y horas HH:MM. Horas decimales con coma (8,5 h). Modo oscuro opcional.
Accesible: etiquetas en todos los campos, foco visible y mensajes de error asociados al campo.

COMPRUEBA ANTES DE DAR UNA PANTALLA POR TERMINADA:
- OPERARIO: solo ve sus partes; crea el de hoy; acepta la jornada; añade DESPLAZAMIENTO + tareas en
  orden; no puede añadir una línea que empiece antes del fin de la última; cierra; ya no puede editar.
- OPERARIO: un parte que empieza con MANTENIMIENTO NAVE y luego DESPLAZAMIENTO a una finca es válido;
  uno que empieza con MANTENIMIENTO VEHÍCULOS no.
- SUPERVISOR: crea un parte para otro operario; corrige un Cerrado; aprueba y rechaza (con comentario);
  no puede revisar uno suyo; genera el PDF de un Aprobado.
- ADMIN: corrige un Aprobado, corrige las horas extra a mano, borra y archiva.
- Ninguna pantalla escribe directamente en partes_cab o partes_det; todos los errores de la BD se ven en
  pantalla sin perder lo escrito; todo funciona en un móvil de 360 px de ancho.
```

---

## Bloque C1 · Correcciones al primer boceto (capturas del 10/11/2026)

Pegar como mensaje en el chat de Lovable, cuando el proyecto ya tiene pantallas.

```
Corrige estas pantallas. No toques el resto ni el backend.

1. QUITA "MANTENIMIENTO" DEL MENÚ (y su ruta, su pantalla y cualquier tabla o formulario aparte).
   El mantenimiento NO es una sección: MANTENIMIENTO NAVE y MANTENIMIENTO VEHÍCULOS son tipos de tarea
   (columna tareas.tipo) y se añaden como una línea más dentro del parte, en "Líneas del parte".

2. EL FORMULARIO DEL PARTE VA EN DOS PESTAÑAS, no en una sola página con la jornada arriba y las tareas
   debajo:
   - Pestaña "Jornada": los campos de la jornada + el panel de resumen (Total jornada, Horas de tareas,
     Horas de mantenimiento, Motivos personales, Sin asignar a líneas, Nº de líneas, Horas extra) y UN
     botón "Aceptar jornada" -> rpc('guardar_cabecera', { p_id_parte: null|id, p_cab }).
     Al crear un parte nuevo, ese botón lo crea y salta solo a la pestaña 2 (URL
     /partes/:id/editar?tab=lineas).
   - Pestaña "Líneas del parte (N)": desactivada hasta aceptar la jornada la primera vez.
   - QUITA los botones "Guardar" y "Guardar y cerrar" del panel lateral. No se guarda el parte entero de
     una vez. "Cerrar parte" va solo en el detalle del parte, con confirmación.

3. CADA LÍNEA SE ACEPTA UNA A UNA:
   - Arriba, la lista de líneas YA GUARDADAS, ordenadas por hora de inicio, en modo lectura (tabla en
     escritorio, tarjetas en móvil), cada una con "Editar" y "Quitar".
   - Debajo, UN SOLO editor de línea abierto a la vez, con los botones "Aceptar" y "Cancelar" al final.
     · Aceptar -> rpc('guardar_linea', { p_id_parte, p_linea }). Si va bien: la línea pasa a la lista,
       el editor se cierra y se actualiza el resumen. Si falla: el editor sigue abierto con lo escrito y
       el mensaje de error de la BD (en español, tal cual) debajo de los campos.
     · Cancelar -> cierra el editor sin guardar.
     · Quitar -> confirmación y rpc('borrar_linea', { p_id_linea }); si la BD lo rechaza, mostrar el mensaje.
   - Un solo botón "Añadir línea" (quita el duplicado "Añadir otra tarea"). Desactivado mientras haya un
     editor abierto. Nada de varias tarjetas de tarea abiertas a la vez ni papelera dentro del editor.
   - Si el usuario sale de la pantalla con una línea sin aceptar: "Tienes una línea sin aceptar. ¿Salir y
     perderla?".

4. EDITOR DE LÍNEA:
   - Orden de los campos: Tarea (primero, porque decide qué más se pide), Inicio, Fin, y después solo los
     campos que pide ese tipo de tarea:
       DESPLAZAMIENTO: Finca (obligatoria), Parcela (opcional), Vehículo (OBLIGATORIO), Apero (opcional)
       POR HORAS / POR SUPERFICIE (HAS): Finca (obligatoria), Parcela, Vehículo, Apero (opcionales);
         "Fin de vuelta" (Sí / No / Sin responder) solo si hay parcela
       MOTIVOS PERSONALES y MANTENIMIENTO NAVE: solo Inicio y Fin
       MANTENIMIENTO VEHÍCULOS: Vehículo o Apero (al menos uno), sin finca ni parcela
     Los campos que no aplican se ocultan y se envían vacíos.
   - La lista de Parcela solo muestra las de la finca elegida; al cambiar de finca se vacía.
   - Inicio y Fin: selector de cuartos de hora (07:00, 07:15, 07:30...), no el selector de hora nativo.
   - Valores propuestos: primera línea = DESPLAZAMIENTO con inicio a la hora de entrada; siguientes =
     inicio en el fin de la última línea y la misma finca, vehículo y apero que la última línea con finca.
   - En la lista de tareas muestra "nombre (tipo)".
```

---

## Bloque C2 · Correcciones tras probar la app publicada como operario (10/11/2026)

Probado en appreport.lovable.app con el operario T003: parte nº 510 creado, 2 líneas, errores de la BD y cierre.
Funciona: dos pestañas, "Aceptar jornada", editor único con Aceptar/Cancelar, campos según el tipo, horas de las
líneas en cuartos de hora, valores propuestos, mensajes de la BD, aviso al salir, cierre con confirmación y sin menú
de Mantenimiento.

```
La app ya funciona bien en lo principal. Corrige solo estos detalles; no cambies nada más:

1. LOGIN: quita las pestañas "Crear cuenta" y "Recuperar" (o deja "Recuperar" solo si envía el enlace
   de restablecer contraseña). El registro está desactivado en Supabase: las cuentas las crea un ADMIN.
   Deja "Entrar" con email + contraseña y un enlace "Entrar con un enlace por email" (signInWithOtp).

2. JORNADA: Entrada y Salida siguen siendo el selector de hora nativo, que deja poner cualquier minuto.
   Usa el mismo selector de cuartos de hora que ya tienen Inicio y Fin de las líneas.
   Almuerzo y Comida: selector de 0 a 180 minutos de 15 en 15.

3. MENSAJE DE ERROR DEL EDITOR DE LÍNEA: cuando el usuario cambia cualquier campo, borra el mensaje de
   error anterior (ahora se queda el viejo aunque ya se haya corregido).

4. LÍNEAS EN MÓVIL Y EN PANTALLAS ESTRECHAS: la tabla de líneas no cabe (en el detalle se cortan
   Vehículo/apero y Horas; en "Líneas del parte" hay que desplazar en horizontal y "Quitar" queda
   escondido). Por debajo de 1024 px muestra cada línea como una tarjeta:
     línea 1: horario (07:30–08:00) y horas a la derecha
     línea 2: tarea y su tipo
     línea 3: finca · parcela
     línea 4: vehículo · apero
     línea 5: Fin de vuelta (si aplica) y Obs.
     botones Editar y Quitar visibles en la tarjeta (en el detalle, sin botones).
   En escritorio, si la tabla no cabe, reduce el texto de vehículo a solo el alias (HT1) con el nombre
   completo en un tooltip, en vez de desplazamiento horizontal.

5. DETALLE DEL PARTE: cambia el botón "Editar" por dos: "Editar jornada" (abre /editar) y "Editar líneas"
   (abre /editar?tab=lineas). Añade la columna Obs. de cada línea si tiene texto.
```

---

## Bloque C3 · Correcciones tras probar como supervisor (10/11/2026)

Probado con el supervisor T001 sobre el parte nº 510. Funciona: rechazar exige motivo, corregir un parte Cerrado
(línea de MANTENIMIENTO VEHÍCULOS, que pide solo vehículo o apero), aprobar y "Generar PDF" (versión 1 correcta),
vueltas y archivos hechos. Falta lo de abajo (todo está en el Bloque 4).

```
Añade lo que falta en estas pantallas, sin cambiar lo que ya funciona:

1. LISTA DE PARTES: falta el filtro por FINCA (partes con alguna línea en esa finca):
   .from('partes_cab').select('*, ht_tareas, lineas:partes_det(finca), filtro:partes_det!inner(finca)')
   .eq('filtro.finca', cod_fin). Muestra también en cada fila las fincas de sus líneas.

2. EXPORTAR CSV (separador ';', coma decimal, UTF-8 con BOM; si un texto empieza por = + - @, anteponer '):
   - Vueltas: botón "Exportar CSV" con los filtros aplicados.
   - Archivo → Tareas realizadas: filtro desde/hasta (fec_tarea) y "Exportar CSV" (vista tareas_resumen).
   - NUEVO apartado en Archivo, "Horas por trabajador": filtro desde/hasta y "Exportar CSV" de la vista
     horas_trabajador (parte, operario, fecha, h_ent, h_sal, t_alm_min, t_com_min, estado), con el aviso
     "Exporta las horas antes de archivar: después ya no están".
   Pagina con .range() de 1000 en 1000 hasta traer todas las filas.

3. NUEVO apartado en Archivo, "PDF de partes": filtro desde/hasta por fecha del parte y lista de la ÚLTIMA
   versión generada de cada parte (.from('partes_pdf').select('id_parte, num_parte, fecha, operario, version,
   ruta, generado').eq('estado','Generado')), con botón "Abrir"
   (storage.from('partes-pdf').createSignedUrl(ruta, 300)). Incluye partes ya archivados.

4. ARCHIVAR (ya existe el botón "Archivar partes" para el ADMIN; mejóralo): en el selector de fecha pon
   como máximo ayer y como mínimo el día siguiente al último archivado; en el diálogo añade el aviso
   "¿Has exportado las horas por trabajador de esas fechas? Después ya no están" con un enlace a esa
   exportación; al terminar muestra el resumen devuelto {hasta, partes, lineas, filas, rechazados}.
   Si la BD lo rechaza (quedan partes Pendientes o Cerrados), muestra su mensaje.
```

---

## Bloque C4 · Correcciones tras probar como administrador (10/11/2026)

Probado con T000. Funciona: editar un parte Aprobado sin cambiar su estado, "Corregir horas extra" a mano (guardado
1,00 h con h_ext_manual), el PDF crea la versión 2 al cambiar el parte y conserva la 1, Configuración y Operarios
cargan. El archivado no se ejecutó (no se puede deshacer); solo se revisó el diálogo.

```
Dos detalles más:

1. BORRAR PARTE (solo ADMIN): en el detalle del parte no aparece. Añade el botón "Borrar parte" (rojo,
   en cualquier estado, solo si el usuario es ADMIN) con confirmación: "Se borra el parte nº X con sus
   líneas. Queda una copia en la auditoría. No se puede deshacer." -> rpc('borrar_parte', { p_id_parte }) y
   volver a la lista.

2. OPERARIOS: el texto "la cuenta se vincula sola cuando confirma el registro" confunde, porque no hay
   registro libre. Cámbialo por: "Para dar acceso: crea aquí el operario con su correo y después crea su
   cuenta en Supabase (Authentication → Users → Add user, con ese mismo correo). La cuenta se vincula sola
   al entrar por primera vez." En la columna Cuenta, cambia "Sin registrarse" por "Sin cuenta".
```

---

## Estado (10/11/2026, tras publicar C2–C4)
Revisado en appreport.lovable.app como ADMIN y en vista móvil (360 px): C1, C2, C3 y C4 aplicados.
Pendiente menor: la pestaña "PDF de partes" del Archivo no tiene filtro desde/hasta (lista todos). Se corrige con el
Bloque C5, aplicado en Lovable el 12/11/2026.

---

## Bloque C5 · Filtro por fechas en "PDF de partes" (12/11/2026)

Pegar como mensaje en el chat de Lovable.

```
Solo un cambio, en Archivo → "PDF de partes". No toques nada más.

Ahora la lista muestra todos los PDF. Añade arriba un filtro por la FECHA DEL PARTE:
- Dos campos de fecha, "Desde" y "Hasta" (dd/mm/aaaa), los dos opcionales, y un botón "Buscar".
  Vacíos = sin límite por ese lado. Si "Desde" es posterior a "Hasta", avisa y no busques.
- Consulta (pagina con .range() de 1000 en 1000 hasta traer todas las filas):
    let q = supabase.from('partes_pdf')
      .select('id_parte, num_parte, fecha, operario, version, ruta, generado')
      .eq('estado', 'Generado')
      .order('fecha', { ascending: false })
      .order('num_parte', { ascending: false })
      .order('version', { ascending: false });
    if (desde) q = q.gte('fecha', desde);   // 'AAAA-MM-DD'
    if (hasta) q = q.lte('fecha', hasta);
  Después deja solo la PRIMERA fila de cada id_parte (la última versión).
- Encima de la tabla: "N parte(s) con PDF". Columnas: Nº parte, Fecha, Operario (nombre con
  rpc('operarios_nombres')), Versión (v1, v2...), Generado (dd/mm/aaaa HH:MM) y botón "Abrir"
  (storage.from('partes-pdf').createSignedUrl(ruta, 300), en una pestaña nueva).
- Sin resultados: "No hay PDF generados en esas fechas." Error: mensaje y "Reintentar".
- Incluye los partes ya archivados (siguen en partes_pdf aunque el parte se haya borrado).
- En móvil, cada PDF es una tarjeta (nº y fecha, operario, versión, botón Abrir).
```

---

## Bloque C6 · Ajustes de "PDF de partes" tras probarlo como supervisora (16/11/2026)

Probado con T001 en appreport.lovable.app. Funciona: el filtro va a la BD (`fecha=gte/lte`), sin fechas salen los
4 partes con PDF, "hasta 06/11" → 441, "07/11–30/11" → 510 v2, "desde 01/12" → 595 y 596, "desde 01/01/2027" →
"Sin PDFs"; "Abrir" abre el PDF firmado (5 min) en una pestaña nueva; sin errores en la consola. Falla lo de abajo.

```
Solo estos ajustes, en Archivo → "PDF de partes" (y la barra de pestañas de Archivo). No toques nada más.

1. DESDE POSTERIOR A HASTA: ahora sale "Sin PDFs" como si no hubiera resultados. Muestra un aviso
   "La fecha Desde no puede ser posterior a Hasta" y no lances la consulta.

2. NO BUSQUES MIENTRAS SE ESCRIBE LA FECHA: ahora se lanza una consulta por cada tecla (al teclear el año
   pide 0002, 0020, 0202 y 2026). Busca solo cuando la fecha esté completa y sea válida (año de 4 cifras,
   entre 2020 y 2100), o al pulsar un botón "Buscar"; además, espera 400 ms desde el último cambio.

3. MÓVIL (360 px):
   - La barra de pestañas de Archivo (Archivos · Tareas realizadas · Horas por trabajador · PDF de partes)
     no cabe: "PDF de partes" queda fuera de la pantalla y no se puede pulsar, y toda la página se desplaza
     en horizontal. Haz que la barra se desplace sola dentro de su ancho (overflow-x: auto, sin que se mueva
     la página) o que pase a dos líneas.
   - La lista de PDF sigue siendo una tabla y "Abrir" queda fuera de la pantalla. Por debajo de 768 px
     muestra cada PDF como una tarjeta: "Parte nº 510 · 10/11/2026", operario, "Versión 2 · generado
     10/11/2026 23:23" y el botón "Abrir" a todo el ancho.
   - Ninguna pantalla debe desplazarse en horizontal a 360 px.
```

**C6 aplicado y comprobado el 16/11/2026** (versión publicada `index-D1UVxCN5.js`, como T001). Funciona:
- botón "Buscar" y una sola consulta con la fecha completa;
- aviso "La fecha Desde no puede ser posterior a Hasta", sin lanzar la consulta;
- resultados correctos con "hasta 06/11" → 441 y con "07/11–30/11" → 510 v2;
- en el móvil (360 px):
  - la página mide 360 px;
  - la barra de pestañas se desplaza dentro de su ancho;
  - la lista sale en tarjetas, con "Abrir" a todo el ancho.

Detalles menores pendientes (no urgentes):
- El botón "Abrir" mide 32 px de alto; lo recomendado son 44 px.
- El icono de calendario de los campos de fecha queda un poco cortado a 360 px.
- Los campos de fecha no tienen nombre accesible: el lector de pantalla dice "Día", no "Desde, día".
- Al cargar la pestaña "Archivos" sale un momento "Todavía no se ha archivado nada" junto a "Cargando…".

Los cuatro se incluyen en el Bloque C7.

---

## Bloque C7 · El operario usa la app SOLO desde el móvil (revisión del 16/11/2026)

Revisado como el operario T002 (jangel) en un móvil de 360 × 780 px. Pantallas: Panel, Partes, detalle, Nuevo parte
(Jornada) y Líneas del parte. Para ver el editor de líneas se creó el parte de prueba nº 623 (21/11/2026), que se
borró después como ADMIN.

Ya funciona bien:
- detalle del parte en tarjetas;
- cambio automático a "Líneas del parte" al aceptar la jornada;
- un solo editor de línea abierto a la vez;
- valores propuestos (inicio, finca y vehículo de la línea anterior);
- la lista de "Fin" solo ofrece horas entre el inicio y la salida;
- la parcela se filtra por la finca;
- "Fin de vuelta" aparece solo cuando hay parcela;
- el error de la BD sale en rojo encima de "Aceptar" sin perder lo escrito.

Medidas (objetivo: nada de desplazamiento lateral y todo lo que se pulsa con al menos 44 px de alto):
- **Ancho de la página:**
  - Panel: 408 px.
  - Editor de línea: 366 px, y 481 px con una tarea de nombre largo.
  - Lista de partes: una tabla de 578 px.
- **Alto de lo que se pulsa:**
  - Menú: 28 × 28 px.
  - Campos, selectores, "Aceptar", "Cancelar" y "Nuevo parte": 36 px.
  - "Editar" y "Quitar": 32 px.
  - Botones de estado: 31 px.
  - "Sí", "No" y "Sin responder" del fin de vuelta: 28 px.
  - Opciones de las listas: 32 px.
- **Letra:** el buscador de las listas tiene 14 px, así que el iPhone amplía la pantalla al tocarlo.

```
El usuario OPERARIO usa la app EXCLUSIVAMENTE desde el MÓVIL (360–430 px de ancho, en el campo, a veces
con guantes y al sol). Optimiza para él estas pantallas. No cambies la lógica ni las llamadas a Supabase,
y deja la vista de escritorio de ADMIN y SUPERVISOR como está.

REGLAS GENERALES EN MÓVIL (< 768 px)
- Ninguna pantalla se desplaza en horizontal: comprueba a 360 px que el ancho de la página es 360. Usa
  min-w-0 y truncado en flex/grid, y que los textos largos (nombres de tarea, vehículo, apero) hagan salto
  de línea en vez de ensanchar la caja.
- Todo lo que se pulsa mide al menos 44 px de alto: botones, campos, selectores, opciones de las listas,
  pestañas, "Editar", "Quitar", "Sí / No / Sin responder", el menú y los enlaces.
- Letra de 16 px en todos los campos y en los buscadores de las listas (con menos, el iPhone hace zoom al
  tocarlos). Texto mínimo de 14 px; nada en 12 px salvo etiquetas secundarias.
- Las acciones principales siempre a mano: barra fija abajo con el botón principal de cada pantalla,
  respetando la zona segura del iPhone (padding-bottom: env(safe-area-inset-bottom)).
- Oculta en móvil la insignia "Edit with Lovable" si se puede: tapa botones y textos.

1. NAVEGACIÓN DEL OPERARIO: cambia el menú lateral (botón de 28 px arriba a la izquierda) por una BARRA
   INFERIOR FIJA con 3 botones grandes, con icono y texto: "Inicio", "Mis partes" y "Parte de hoy". "Parte
   de hoy" abre el parte de hoy si existe y, si no, el formulario nuevo. Arriba deja solo el título de la
   pantalla, y "Salir" dentro de un menú de usuario. Quita del menú los textos en inglés ("Sidebar",
   "Displays the mobile sidebar", "Toggle Sidebar"): ponlos en español.

2. INICIO (panel):
   - La lista "Últimos partes" se sale de la pantalla (408 px). En móvil, cada parte es una tarjeta: "Nº 533 ·
     04/12/2026" y la etiqueta de estado. Sin la columna de operario: es el propio usuario.
   - El aviso grande "Tu parte de hoy" primero, con su botón a todo el ancho (48 px de alto). Si no hay parte
     hoy, el botón dice "Empezar el parte de hoy".
   - "Partes por estado": botones de 44 px, que llevan a la lista filtrada (ya lo hacen).

3. MIS PARTES (lista):
   - Ahora es una tabla de 8 columnas (578 px) con desplazamiento lateral; el estado no se ve. En móvil,
     una TARJETA por parte, toda ella pulsable (un enlace, no una fila con onclick):
       línea 1: "Nº 533 · jue 04/12/2026" y la etiqueta de estado a la derecha
       línea 2: 07:30–18:00 · 8,50 h (y "+1,00 h extra" si hay)
       línea 3: fincas
     Sin columna "Operario".
   - Los filtros ocupan media pantalla antes de la lista. En móvil, deja visibles solo los botones de estado
     (en una fila que se desplaza de lado dentro de su ancho, de 44 px de alto) y mete Nº de parte, Finca,
     Desde y Hasta en un botón "Filtros" que abre un panel desde abajo. Muestra cuántos filtros hay activos.
   - "Nuevo parte" pasa a la barra inferior ("Parte de hoy"); quita el botón de arriba en móvil.

4. NUEVO PARTE · JORNADA:
   - Quita el campo "Operario" para el operario (el parte es suyo; ahora sale desactivado).
   - Si ya tiene parte en la fecha elegida, avisa antes de aceptar: "Ya tienes el parte nº X de ese día" con
     un botón "Abrir ese parte" (ahora propone hoy aunque ya exista y la BD lo rechaza al aceptar).
   - Entrada y Salida en la misma fila (2 columnas); Almuerzo y Comida en la misma fila.
   - Las listas de hora tienen 96 opciones (00:00–23:45) de 32 px. Ofrece solo de 05:00 a 22:00, con
     opciones de 44 px, y al abrir colócate en la hora elegida. Mejor aún: usa en móvil el selector nativo
     (<select>), que en el teléfono se ve como una rueda.
   - "Aceptar jornada" en la barra fija de abajo, a todo el ancho.
   - El resumen (Total jornada, horas…) plegado bajo el formulario: muestra solo "Total 8,50 h · Sin asignar
     8,00 h" y despliega el resto al tocarlo.

5. LÍNEAS DEL PARTE (lo más importante: el operario lo usa varias veces al día):
   - El editor se sale de su recuadro: los campos miden más que la tarjeta (página de 366 px, y 481 px con un
     nombre de tarea largo). Los campos deben medir el 100 % del ancho de la tarjeta y el texto del valor
     elegido debe partirse en dos líneas o cortarse con "…", nunca ensanchar la caja.
   - Abre el editor de línea a PANTALLA COMPLETA en móvil (una hoja que sube desde abajo, con el título "Nueva
     línea" o "Editar línea" y una X para cerrar), con "Cancelar" y "Aceptar" FIJOS ABAJO. Ahora "Aceptar"
     queda a 1100 px y hay que desplazarse para encontrarlo.
   - Lista de TAREAS (95, sin agrupar): en móvil los nombres se cortan y no se distingue "*LABRAR CON DISCOS
     POR HAS" de "...POR HORAS". Muestra el nombre completo en dos líneas y el tipo debajo, en pequeño.
     Agrupa por tipo (Desplazamiento, Mantenimiento, Por superficie, Por horas, Motivos personales) y pon
     arriba un grupo "Recientes" con las 5 últimas tareas que ha usado el operario.
   - Lo mismo para Finca, Parcela, Vehículo y Apero: opciones de 44 px, buscador de 16 px, y "Recientes"
     arriba en Vehículo y Apero. Ábrelas como hoja desde abajo en vez de como desplegable pegado al campo.
   - "Fin de vuelta": los tres botones (Sí / No / Sin responder) a 44 px de alto.
   - En cada línea guardada, "Editar" y "Quitar" de 44 px. "Quitar" en rojo, con confirmación.
   - No repitas el tipo cuando coincide con el nombre: "DESPLAZAMIENTO (DESPLAZAMIENTO)" → "DESPLAZAMIENTO".

6. DETALLE DEL PARTE:
   - "Cerrar parte", "Editar jornada" y "Editar líneas" en la barra fija de abajo cuando se pueden usar.
     "Cerrar parte" es el principal, a todo el ancho.
   - "Seguimiento": muestra siempre el NOMBRE de la persona (ahora mezcla correo, nombre y el código "T001").

7. ARCHIVO → PDF DE PARTES (supervisor, detalles pendientes del C6):
   - Botón "Abrir" a 44 px (ahora 32).
   - El icono de calendario de los campos de fecha se corta a 360 px.
   - Los campos de fecha no tienen nombre accesible: el lector dice "Día", no "Desde, día". Asocia la
     etiqueta (label for/id o aria-label="Desde").
   - Al cargar la pestaña "Archivos" sale un momento "Todavía no se ha archivado nada" junto a "Cargando…":
     mientras carga, muestra solo "Cargando…".

COMPRUEBA ANTES DE DARLO POR TERMINADO, a 360 × 780 px y como OPERARIO:
- Ninguna pantalla se desplaza de lado (ancho de la página = 360).
- Todo lo que se pulsa mide 44 px o más.
- Se puede crear el parte de un día libre, añadir un DESPLAZAMIENTO y una tarea con parcela respondiendo el
  fin de vuelta, y cerrar el parte, sin hacer zoom ni desplazarse de lado.
- "Aceptar" está siempre visible sin desplazarse.
```

**C7 aplicado y comprobado el 16/11/2026** (versión `index-BP-Jivqa.js`, como T002, a 360 × 780 px; parte de prueba
nº 624 del 21/11, borrado después como ADMIN).

Funciona:
- **Navegación:** barra inferior fija (Inicio · Mis partes · Parte de hoy, de 56 px) y menú de usuario de 44 px. La
  insignia de Lovable ya no se ve.
- **Ancho:** todas las pantallas miden 360 px.
- **Panel y lista de partes:** van en tarjetas; la lista tiene el botón "Filtros".
- **Pestaña Jornada:**
  - sin campo "Operario";
  - aviso "Ya tienes el parte nº 519 de ese día" con "Abrir ese parte", y "Aceptar jornada" desactivado;
  - horas en listas nativas de 05:00 a 22:00, de dos en dos por fila;
  - "Aceptar jornada" fijo abajo y el resumen plegado.
- **Editor de líneas:**
  - a pantalla completa, con "Cancelar" y "Aceptar" fijos abajo (48 px);
  - listas en hoja desde abajo, con opciones de 44 px y buscador de 16 px;
  - tareas agrupadas por tipo, con "Recientes" y el nombre completo;
  - "Recientes" también en Vehículo;
  - fin de vuelta con botones de 48 px.
- **Líneas guardadas y detalle:** "Editar" y "Quitar" de 44 px; "Cerrar parte" fijo abajo; el tipo ya no se repite.

Falta lo del Bloque C8. No se volvieron a comprobar los detalles de "PDF de partes" del punto 7, porque son de la vista
del supervisor.

---

## Bloque C8 · Últimos ajustes del móvil del operario (16/11/2026)

```
Últimos ajustes en la vista móvil del OPERARIO. No toques nada más.

1. PARTE DE OTRO DÍA: en móvil el botón "Nuevo parte" de "Mis partes" está oculto y "Parte de hoy" solo crea
   el de hoy. Si el operario ya tiene el parte de hoy, no puede dar de alta el de un día que se le olvidó.
   Añade en "Mis partes" (móvil) un botón "+ Parte de otro día" a todo el ancho, encima de la lista, que abra
   /partes/nuevo. El formulario ya avisa si ese día tiene parte.

2. FECHA CORTADA EN LAS TARJETAS DE "MIS PARTES": "Nº 533 · vie 04/1…" se corta, porque necesita 221 px y
   tiene 180, ya que comparte línea con la etiqueta de estado. Pon la etiqueta de estado en su propia línea
   o debajo, o la fecha en una segunda línea. La fecha completa debe verse siempre.

3. ERROR TAPADO EN EL EDITOR DE LÍNEA: el mensaje de error de la BD queda detrás de la barra fija de
   "Cancelar / Aceptar" y solo se ve su primera línea. Cuando llegue un error, muéstralo ENCIMA de la barra
   fija (dentro de ella o justo antes, siempre visible), o desplaza el contenido hasta que se vea entero.

4. BOTONES "X" PARA QUITAR la finca, el vehículo, etc. dentro de los campos: miden 36 × 36 px; ponlos a 44 × 44.

5. PANEL: el enlace "Ver todos" de "Últimos partes" mide 20 px de alto; ponlo a 44 px (o toda la cabecera de
   la tarjeta pulsable).

6. ESPACIO DE LAS BARRAS FIJAS EN EL DETALLE: "Cerrar parte" + "Editar jornada/Editar líneas" + la barra
   inferior ocupan 172 px de 780. Pon "Editar jornada" y "Editar líneas" en la misma fila que "Cerrar
   parte" (iconos con texto corto) o dentro de un botón "Editar ▾", para dejar una sola fila de acciones
   encima de la barra inferior.
```

**C8 aplicado y comprobado el 16/11/2026** (versión `index-CpGfvH9K.js`, como T002, a 360 × 780 px; parte de prueba
nº 625 del 21/11, borrado después como ADMIN). Los seis puntos funcionan:
1. "Parte de otro día" (44 px) en "Mis partes" abre el formulario nuevo.
2. La fecha completa se ve en las tarjetas ("Nº 533 · vie 04/12/2026").
3. El error de la BD se ve entero encima de "Cancelar / Aceptar".
4. Las "X" para quitar miden 44 × 44.
5. "Ver todos" mide 44 px.
6. El detalle tiene una sola fila de acciones (Jornada · Líneas · Cerrar), y las barras fijas bajan de 172 a 128 px.

Pendientes:
- No se ha vuelto a comprobar el punto 7 del C7 (PDF de partes, vista del supervisor).
- Resueltos con la migración 022:
  - "T001" en "Seguimiento": `operarios_nombres()` devuelve ya al operario los nombres de ADMIN y SUPERVISOR, y la app
    muestra "maria" sin cambios en Lovable.
  - La fecha de "Parte de otro día": Bloque C9.

---

## Bloque C9 · "Parte de otro día" propone el último día sin parte (16/11/2026)

La BD ya tiene la función (migración 022). Pegar como mensaje en el chat de Lovable.

```
Un solo cambio en el formulario de parte nuevo. No toques nada más.

El operario está obligado a hacer TODOS los partes. Cuando el operario abre "Parte de otro día" (o
/partes/nuevo), la fecha propuesta debe ser el último día laborable que tiene SIN parte, no hoy:

- Al abrir el formulario (solo al crear, no al editar), llama a rpc('ultimo_dia_sin_parte') -> 'AAAA-MM-DD' o null.
  · Si devuelve una fecha: ponla en el campo Fecha y muestra debajo, en ámbar, "Te falta el parte del
    vie 13/11/2026" (día de la semana abreviado y fecha dd/mm/aaaa).
  · Si devuelve null: deja la fecha de hoy y muestra en verde "No tienes partes pendientes".
  · El usuario puede cambiar la fecha libremente; el aviso "Ya tienes el parte nº X de ese día" sigue igual.
- ADMIN y SUPERVISOR, al crear para otro operario: cuando elijan el operario, llama a
  rpc('ultimo_dia_sin_parte', { p_operario: cod_ope }) y haz lo mismo.
- "Parte de hoy" (barra inferior) no cambia: sigue abriendo el parte de hoy o creándolo.
- En INICIO, para el OPERARIO: si la función devuelve una fecha anterior a hoy, muestra arriba un aviso ámbar
  "Te falta el parte del vie 13/11/2026" con el botón "Hacerlo ahora" (44 px), que abre /partes/nuevo.
```

---

## Bloque C10 · Botones de estado de "Mis partes" sin desplazamiento lateral (17/11/2026)

Medido a 360 px como T002: los 5 botones de estado (Todos 72 px, Pendiente 98, Cerrado 88, Aprobado 98 y Rechazado
103, más los huecos) necesitan 522 px en una fila de 360. Por eso la fila se desplaza de lado y muestra una barra de
desplazamiento.

```
Un solo cambio en "Mis partes", en móvil (< 768 px). No toques nada más.

Los botones de estado (Todos, Pendiente, Cerrado, Aprobado, Rechazado) no caben en una fila: necesitan 522 px y
la fila se desplaza en horizontal con una barra de desplazamiento. Quita el desplazamiento (nada de
overflow-x: auto en esa fila) y colócalos en una CUADRÍCULA de 3 columnas iguales y 2 filas, junto con el
botón "Filtros":

   [ Todos     ] [ Pendiente ] [ Cerrado ]
   [ Aprobado  ] [ Rechazado ] [ Filtros ]

- grid-cols-3, gap de 8 px, cada botón al 100 % de su columna, alto de 44 px, texto centrado de 14 px sin
  salto de línea (si no cabe, quita el punto de color antes de cortar el texto).
- El botón elegido se rellena con su color (como ahora "Todos" en verde) y los demás quedan con borde.
- "Filtros" pasa a esta cuadrícula, con su icono y el número de filtros activos si los hay ("Filtros · 2").
  Quítalo de la cabecera de la lista; ahí deja solo "21 partes · 181,50 h".
- Ninguna barra de desplazamiento horizontal en la pantalla. Comprueba a 360 px que la cuadrícula mide como
  mucho 328 px de ancho y que la página mide 360.
- En escritorio deja la fila como está.
```

**C9 y C10 aplicados y comprobados el 17/11/2026** (versión `index-BtuL6cPY.js`, como T002, a 360 × 780 px).

C10:
- Cuadrícula de 3 × 2 (Todos · Pendiente · Cerrado / Aprobado · Rechazado · Filtros), con botones de 104 × 44 px.
- Mide 328 px de ancho y la página 360, sin desplazamiento lateral.
- Los filtros funcionan: Pendiente → 0, Aprobado y Todos → 21. La cabecera muestra "21 partes · 181,50 h".

C9:
- La app llama a `rpc('ultimo_dia_sin_parte')`.
- Sin días pendientes (caso real de T002): propone hoy y muestra "No tienes partes pendientes", sin aviso en Inicio.
- Con un día pendiente, simulado en el navegador devolviendo 2026-11-13 sin tocar la BD:
  - "Parte de otro día" propone el 13/11 y muestra "Te falta el parte del vie 13/11/2026".
  - Inicio muestra el mismo aviso con "Hacerlo ahora" (44 px), que abre /partes/nuevo.

## Cambios del backend del 11 y 12/11/2026 (020 y 021): no hace falta mensaje a Lovable
- **020 · Permisos mínimos**: sin sesión no se lee nada, y una escritura directa no permitida da 42501 en lugar de
  0 filas. Añadido al Bloque 0. La app publicada ya solo escribe con rpc, y se probó el 11/11 como operario y como
  supervisor sin errores.
- **021 · Horas de la semana**: `panel_resumen` cuenta `horas_semana` y `horas_semana_por_finca` de lunes a domingo.
  Antes sumaba también las semanas siguientes (717 h en lugar de 199,5). El panel de Inicio de Lovable lee esos
  valores de la rpc, así que se corrige solo. Bloque 2 documentado con todas las claves de `panel_resumen`.
