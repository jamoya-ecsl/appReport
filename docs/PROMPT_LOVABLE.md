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
Pendiente menor: la pestaña "PDF de partes" del Archivo no tiene filtro desde/hasta (lista todos).

## Cambios del backend del 11 y 12/11/2026 (020 y 021): no hace falta mensaje a Lovable
- **020 · Permisos mínimos**: sin sesión no se lee nada, y una escritura directa no permitida da 42501 en lugar de
  0 filas. Añadido al Bloque 0. La app publicada ya solo escribe con rpc, y se probó el 11/11 como operario y como
  supervisor sin errores.
- **021 · Horas de la semana**: `panel_resumen` cuenta `horas_semana` y `horas_semana_por_finca` de lunes a domingo.
  Antes sumaba también las semanas siguientes (717 h en lugar de 199,5). El panel de Inicio de Lovable lee esos
  valores de la rpc, así que se corrige solo. Bloque 2 documentado con todas las claves de `panel_resumen`.
