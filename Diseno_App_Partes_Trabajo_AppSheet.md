# Diseño de la app "Partes de Trabajo" en AppSheet
### Escribano Cabañero / Grupo agrícola — estructura definitiva, basada en `PT_EC.xlsx`

Modelo de acceso confirmado:
- **ADMIN**: acceso total a datos, gestiona catálogos (fincas, parcelas, tareas, vehículos, aperos, usuarios) y puede corregir cualquier parte.
- **SUPERVISOR**: ve **todos** los partes de **todos** los operarios (no hay jerarquía "mis trabajadores"), y puede validar/aprobar/rechazar cualquiera.
- **OPERARIO**: ve y crea únicamente sus propios partes; solo puede editarlos mientras están en estado "Pendiente".

La seguridad se basa **exclusivamente** en dos columnas de `OPERARIOS`: `EMAIL` (para identificar al usuario conectado vía `USEREMAIL()`) y `ROL_APP` (para decidir sus permisos).

Este documento sustituye a las versiones anteriores. Los nombres de columnas ya son los **definitivos**, tomados de tu archivo `PT_EC.xlsx` (que ya incorporaba casi todo el diseño previo con su propia convención de nombres), y el archivo `BBDD_Corregida_AppSheet.xlsx` adjunto ya los aplica.

---

## 0. Decisiones cerradas en esta última revisión

| Tema | Decisión |
|---|---|
| `CULTIVOS` | No se incorpora en esta primera versión |
| `APEROS.ALIAS` duplicado `A9` | Corregido: el segundo registro (`BBBXXX0002`) es `A9*2` |
| Base de nombres de campos | `PT_EC.xlsx` (ya no `COD`/`USUARIO` genéricos; ver tabla de equivalencias abajo) |
| `VEHICULOS` con `ID_MAT` vacío (5 filas: `Q1`, `Q2`, `Q3`, `T68`, `TRACTOR`) | Se mantiene `ID_MAT` como Key; se ha rellenado un código provisional `SIN-MAT-<ALIAS>` en esas 5 filas — revisar y sustituir por la matrícula real si la tienen |
| `COD. INT.` (VEHICULOS/APEROS) | Eliminada definitivamente |
| `PARTES_MANT` sin `ESTADO` ni `FOTO` | Se mantiene tal cual está en `PT_EC.xlsx` (con `H_INI`/`H_FIN`/`T_HORAS`/`OBS`/`ID_PARTE`, sin estado de seguimiento) |
| Numeración `NUM_PARTE` | Enfoque simple confirmado: `MAX + 1` sobre toda la tabla, correlativo global para todos los usuarios (no por operario) |
| Login / acceso a la app | Añadido apartado 4.13 y vista "Mi Perfil" (apartado 6) — ver más abajo |
| `PARTES_CAB.TIEMPO` | **Sigue pendiente.** No sé qué representa exactamente este campo (en el Excel original era una columna sin nombre). Lo he dejado en el archivo como campo libre tipo Duration, con un comentario en la celda de cabecera recordando que falta confirmarlo. Dime qué es y lo cierro |

---

## 1. Tabla de equivalencias de nombres (respecto a mis propuestas anteriores)

| Concepto | Nombre final (`PT_EC.xlsx`) |
|---|---|
| Clave de operario | `COD_OPE` (no `ID_OPERARIO`) |
| Nombre de operario | `USUARIO` (no `NOMBRE`) |
| Clave de finca | `COD_FIN` |
| Clave de parcela | `COD_PAR`; nombre parcela `NOM_PARC`; superficie `SUPERFICIE` |
| Clave de tarea | `COD_TAR`; texto `TAREAS`; tipo `TIPO` |
| Hora entrada/salida (cabecera) | `H_ENT` / `H_SAL` |
| Almuerzo / comida (cabecera) | `T_ALM` / `T_COM` |
| Horas totales (cabecera) | `TOT_HORAS` |
| Horas extra | `H_EXT` |
| Mantenimiento nave | `MAT_NAVE` |
| Fecha creación / modificación (cabecera) | `FCH_CREACION` / `FCH_MODIFICACION` |
| Hora inicio/fin (detalle y mantenimiento) | `H_INI` / `H_FIN` |
| Horas (detalle y mantenimiento) | `T_HORAS` |
| Tipo de mantenimiento | `TIPO_MANT` |
| Observaciones (cabecera) | `OBS` (corregido desde el typo `OSB`) |

---

## 2. Estructura de tablas

### 2.1 `OPERARIOS`

| Campo | Tipo AppSheet | Key/Label | Obligatorio | Notas |
|---|---|---|---|---|
| COD_OPE | Text | **Key** | Sí | Clave única y estable (`T000`…`T003` ya cargados) |
| USUARIO | Text | **Label** | Sí | Nombre visible del usuario |
| EMAIL | Text (Email) | — | Sí, único | Ya cargado para los 4 usuarios reales; marcar "Unique values" en AppSheet |
| ROL_APP | Enum, lista cerrada: `ADMIN`, `SUPERVISOR`, `OPERARIO` | — | Sí | Único campo que determina permisos en toda la app |
| ACTIVO | Yes/No | — | Sí | Ya cargado (`TRUE` en los 4 registros) |

Datos ya reales (no de ejemplo):

| COD_OPE | USUARIO | EMAIL | ROL_APP |
|---|---|---|---|
| T000 | Escribanosl | partes.ecsl@gmail.com | ADMIN |
| T001 | maria | maria@escribanosl.es | SUPERVISOR |
| T002 | juanangel | jangel@escribanosl.es | ADMIN |
| T003 | juan | juane@escribanosl.es | OPERARIO |

Relaciones: origen de todas las referencias `Ref` a "trabajador" desde `PARTES_CAB`, `PARTES_DET` y `PARTES_MANT`.

---

### 2.2 `FINCAS`

| Campo | Tipo | Key/Label |
|---|---|---|
| COD_FIN | Text | **Key** |
| FINCA | Text | **Label** |

8 filas, ya limpias (sin espacios en blanco).

---

### 2.3 `PARCELAS`

| Campo | Tipo | Key/Label |
|---|---|---|
| COD_PAR | Text | **Key** |
| FINCA | **Ref** → `FINCAS.COD_FIN` | — |
| NOM_PARC | Text | **Label** |
| SUPERFICIE | Decimal | — |

183 filas, ya correctamente referenciadas por código de finca.

---

### 2.4 `TAREAS`

| Campo | Tipo | Key/Label |
|---|---|---|
| COD_TAR | Text | **Key** |
| TAREAS | Text | **Label** |
| TIPO | Enum (`POR SUPERFICIE (HAS)`, `POR HORAS`) | — |

91 filas, ya rellenas (41 "por superficie" / 50 "por horas").

---

### 2.5 `VEHICULOS`

| Campo | Tipo | Key/Label | Notas |
|---|---|---|---|
| ID_MAT | Text | **Key** | 113 con matrícula real + 5 con código provisional `SIN-MAT-<ALIAS>` |
| ALIAS | Text | — | Único en las 118 filas |
| EQUIPO | Text | **Label** | — |
| TIPO | Enum (`CARRETILLA`,`VEHICULO`,`TRACTOR`,`QUART`,`PLANTADORAS`) | — | Ya unificado con `APEROS.TIPO` |

---

### 2.6 `APEROS`

| Campo | Tipo | Key/Label |
|---|---|---|
| ID_BAS | Text | **Key** |
| ALIAS | Text | — |
| EQUIPO | Text | **Label** |
| TIPO | Enum | Ya sin typos (`ABONADORAS`, `SEMBRADORAS` corregidos) |

223 filas, alias sin duplicados.

---

### 2.7 `PARTES_CAB` — un registro por jornada

| Campo | Tipo AppSheet | Obligatorio | Initial value / fórmula | Notas |
|---|---|---|---|---|
| ID_PARTE | Text, **Key** | Sí | App formula: `UNIQUEID()` | Clave técnica robusta |
| NUM_PARTE | Number, **Label** | Sí | Bot server-side (apartado 5 y 7) | Correlativo global para todos los usuarios |
| OPERARIO | **Ref** → `OPERARIOS.COD_OPE` | Sí | `LOOKUP(USEREMAIL(),"OPERARIOS","EMAIL","COD_OPE")` | Autorrelleno con el usuario conectado |
| FECHA | Date | Sí | `TODAY()` | — |
| H_ENT | Time | Sí | — | — |
| H_SAL | Time | Sí | — | — |
| T_ALM | Duration | No | — | — |
| T_COM | Duration | No | — | — |
| TOT_HORAS | Decimal, **App formula** | — | `HOUR([H_SAL]-[H_ENT]) + MINUTE([H_SAL]-[H_ENT])/60 - HOUR([T_ALM]) - HOUR([T_COM]) - MINUTE([T_ALM])/60 - MINUTE([T_COM])/60` | — |
| H_EXT | Decimal | No | `0` | — |
| MAT_NAVE | Yes/No | No | `FALSE` | — |
| FINCA | **Ref** → `FINCAS.COD_FIN` | Sí | — | — |
| VEHICULO | **Ref** → `VEHICULOS.ID_MAT` | No | — | — |
| TIEMPO | Duration | No | — | **Pendiente de confirmar su significado** (ver apartado 0) |
| OBS | Long Text | No | — | Corregido desde `OSB` |
| ESTADO | Enum (`Pendiente`,`Aprobado`,`Rechazado`) | Sí | `"Pendiente"` | — |
| CREADO_POR | Email | Sí | `USEREMAIL()` | — |
| FCH_CREACION | DateTime | Sí | `NOW()` | — |
| FCH_MODIFICACION | DateTime | No | `NOW()` con **Reset on edit = ON** | — |
| SUPERVISOR_REVISA | **Ref** → `OPERARIOS.COD_OPE` | No | — | Se rellena al aprobar/rechazar |
| FECHA_REVISION | DateTime | No | — | — |
| COMENTARIO_SUPERVISOR | Long Text | No | — | — |
| FOTO | Image | No | — | — |
| UBICACION_GPS | LatLong | No | `HERE()` | — |

---

### 2.8 `PARTES_DET` — líneas de tareas dentro de un parte

| Campo | Tipo | Obligatorio | Fórmula / notas |
|---|---|---|---|
| ID_LINEA | Text, **Key** | Sí | App formula: `UNIQUEID()` *(añadir si no existe aún en la hoja)* |
| ID_PARTE | **Ref** → `PARTES_CAB.ID_PARTE` | Sí | — |
| OPERARIO | **Ref** → `OPERARIOS.COD_OPE` | Sí | App formula: `[ID_PARTE].[OPERARIO]` |
| TAREA | **Ref** → `TAREAS.COD_TAR` | Sí | — |
| FINCA | **Ref** → `FINCAS.COD_FIN` | No | App formula sugerida: `[ID_PARTE].[FINCA]` |
| PARCELA | **Ref** → `PARCELAS.COD_PAR` | No | Dropdown dependiente de `FINCA` |
| VEHICULO | **Ref** → `VEHICULOS.ID_MAT` | No | — |
| APERO | **Ref** → `APEROS.ID_BAS` | No | — |
| H_INI | Time | Sí | — |
| H_FIN | Time | Sí | — |
| T_HORAS | Decimal, App formula | — | `HOUR([H_FIN]-[H_INI]) + MINUTE([H_FIN]-[H_INI])/60` |
| OBS | Long Text | No | — |

(La hoja `PT_EC.xlsx` no incluye `PRODUCTOS`; si lo necesitas para anotar fitosanitarios/dosis, dímelo y lo añado.)

---

### 2.9 `PARTES_MANT` — mantenimiento de vehículos/aperos

| Campo | Tipo | Obligatorio | Notas |
|---|---|---|---|
| ID_MANT | Text, **Key** | Sí | App formula: `UNIQUEID()` |
| ID_PARTE | **Ref** → `PARTES_CAB.ID_PARTE` | No | Enlaza el mantenimiento con el parte de trabajo del día, si aplica |
| FECHA | Date | Sí | Initial value `TODAY()` |
| TIPO_EQUIPO | Enum (`Vehículo`,`Apero`) | Sí | Determina cuál Ref se usa |
| VEHICULO | **Ref** → `VEHICULOS.ID_MAT` | No | Show_If: `[TIPO_EQUIPO]="Vehículo"` |
| APERO | **Ref** → `APEROS.ID_BAS` | No | Show_If: `[TIPO_EQUIPO]="Apero"` |
| OPERARIO | **Ref** → `OPERARIOS.COD_OPE` | Sí | Initial value igual que en `PARTES_CAB` |
| TIPO_MANT | Enum (`Preventivo`,`Correctivo`,`Avería`) | Sí | — |
| DESCRIPCION | Long Text | Sí | — |
| H_INI | Time | No | — |
| H_FIN | Time | No | — |
| T_HORAS | Decimal, App formula | — | `HOUR([H_FIN]-[H_INI]) + MINUTE([H_FIN]-[H_INI])/60` |
| OBS | Long Text | No | — |
| CREADO_POR | Email | Sí | `USEREMAIL()` |
| FECHA_CREACION | DateTime | Sí | `NOW()` |

Sin `ESTADO` ni `FOTO`, según confirmaste. Si más adelante quieres dar seguimiento (pendiente/en taller/resuelto) o adjuntar fotos de la avería, se pueden añadir sin romper nada de lo ya construido.

---

## 3. Relaciones entre tablas (resumen)

```
FINCAS  ─┬─ Ref ← PARCELAS.FINCA
         └─ Ref ← PARTES_CAB.FINCA, PARTES_DET.FINCA
PARCELAS ── Ref ← PARTES_DET.PARCELA
TAREAS   ── Ref ← PARTES_DET.TAREA
VEHICULOS── Ref ← PARTES_CAB.VEHICULO, PARTES_DET.VEHICULO, PARTES_MANT.VEHICULO
APEROS   ── Ref ← PARTES_DET.APERO, PARTES_MANT.APERO
OPERARIOS─┬─ Ref ← PARTES_CAB.OPERARIO, PARTES_CAB.SUPERVISOR_REVISA
          └─ Ref ← PARTES_DET.OPERARIO, PARTES_MANT.OPERARIO
PARTES_CAB ─┬─ Ref ← PARTES_DET.ID_PARTE   (cabecera 1 — N líneas de tarea)
            └─ Ref ← PARTES_MANT.ID_PARTE  (cabecera 1 — N partes de mantenimiento, opcional)
```

---

## 4. Security Filters y expresiones AppSheet

### 4.1 Averiguar el rol del usuario conectado

```
LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP")
```

### 4.2 Security Filter en `OPERARIOS`

```
AND(
  LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ACTIVO") = TRUE,
  OR(
    [EMAIL] = USEREMAIL(),
    LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") = "ADMIN",
    LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") = "SUPERVISOR"
  )
)
```

### 4.3 Security Filter en `PARTES_CAB`

```
AND(
  LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ACTIVO") = TRUE,
  OR(
    [OPERARIO].[EMAIL] = USEREMAIL(),
    IN(
      LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP"),
      LIST("SUPERVISOR", "ADMIN")
    )
  )
)
```

### 4.4 Security Filter en `PARTES_DET`

```
AND(
  LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ACTIVO") = TRUE,
  OR(
    [OPERARIO].[EMAIL] = USEREMAIL(),
    IN(
      LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP"),
      LIST("SUPERVISOR", "ADMIN")
    )
  )
)
```

### 4.5 Security Filter en `PARTES_MANT`

Igual patrón que 4.3/4.4.

### 4.6 Tablas catálogo (`FINCAS`, `PARCELAS`, `TAREAS`, `VEHICULOS`, `APEROS`)

Security Filter: **`TRUE`** (lectura abierta a todos los roles, necesaria para los desplegables/Ref). La edición se protege en 4.7.

### 4.7 Editable_If — quién puede editar catálogos

```
LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") = "ADMIN"
```

### 4.8 Editable_If en `PARTES_CAB` / `PARTES_DET`

```
OR(
  LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") <> "OPERARIO",
  AND(
    [OPERARIO].[EMAIL] = USEREMAIL(),
    [ESTADO] = "Pendiente"
  )
)
```

### 4.9 Show_If de campos exclusivos de supervisión (en `PARTES_CAB`)

Para `SUPERVISOR_REVISA`, `FECHA_REVISION`, `COMENTARIO_SUPERVISOR`:

```
OR(
  IN(
    LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP"),
    LIST("SUPERVISOR", "ADMIN")
  ),
  NOT(ISBLANK([SUPERVISOR_REVISA]))
)
```

### 4.10 Valid_If — impedir que un operario se autoapruebe

En `ESTADO`:

```
OR(
  LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") <> "OPERARIO",
  [ESTADO] = "Pendiente"
)
```

### 4.11 Editable_If en `OPERARIOS` (protege el propio rol)

Para que nadie pueda auto-otorgarse permisos desde la vista "Mi Perfil" (apartado 6):

```
LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") = "ADMIN"
```
Aplicado a nivel de columna en `ROL_APP` y `ACTIVO` (el resto de campos del propio usuario, como `USUARIO`, se pueden dejar editables por el propio interesado si quieres).

### 4.12 Slices (organización, no seguridad)

- `Slice_MisPartes`: `PARTES_CAB`, filtro `[OPERARIO].[EMAIL] = USEREMAIL()`
- `Slice_PendientesRevision`: `PARTES_CAB`, filtro `[ESTADO] = "Pendiente"`
- `Slice_PartesPorFinca`, `Slice_PartesPorFecha`: sin filtro adicional, solo agrupación para las vistas de supervisor.

### 4.13 Acceso a la aplicación (login)

Esto se configura en **AppSheet → Users & Access**, no dentro de las tablas:

1. **Require sign-in**: activar sign-in con Google (o Microsoft, según qué usen en Escribano Cabañero). Sin esto, `USEREMAIL()` no identifica a nadie y todo el resto de la seguridad no tiene efecto.
2. **App Users source table**: configurar `OPERARIOS` como tabla de usuarios de la app, usando `EMAIL` como columna de correo y `ACTIVO` como condición de acceso (`[ACTIVO] = TRUE`). Así, dar de baja a alguien en la tabla también le bloquea la entrada a la app, no solo la visibilidad de datos.
3. Cada uno de los 4 usuarios ya cargados (`partes.ecsl@gmail.com`, `maria@escribanosl.es`, `jangel@escribanosl.es`, `juane@escribanosl.es`) debe existir como cuenta real de Google/Microsoft con la que esa persona inicia sesión.

---

## 5. Fórmulas clave adicionales

| Necesidad | Dónde | Expresión |
|---|---|---|
| Autorrelleno de operario al crear parte | `PARTES_CAB.OPERARIO`, Initial value | `LOOKUP(USEREMAIL(),"OPERARIOS","EMAIL","COD_OPE")` |
| Registrar creador | `CREADO_POR`, Initial value | `USEREMAIL()` |
| Fecha de creación | `FCH_CREACION`, Initial value | `NOW()` |
| Fecha de modificación | `FCH_MODIFICACION`, Initial value + **Reset on edit = ON** | `NOW()` |
| Numeración correlativa `NUM_PARTE` (global, confirmado enfoque simple) | Bot en Add de `PARTES_CAB` | `NUM_PARTE = MAX(SELECT(PARTES_CAB[NUM_PARTE], TRUE)) + 1` — mira toda la tabla sin filtrar por operario, así el correlativo es único y compartido entre todos los usuarios |
| Parcelas dependientes de la finca elegida | `PARTES_DET.PARCELA`, Valid_If | `[_THISROW].[PARCELA] IN SELECT(PARCELAS[COD_PAR], [FINCA] = [_THISROW].[FINCA])` |
| Evitar horas imposibles | `H_FIN`, Valid_If | `[H_FIN] > [H_INI]` |
| Evitar parte duplicado (mismo operario, misma fecha) | `PARTES_CAB.FECHA`, Valid_If | `COUNT(SELECT(PARTES_CAB[ID_PARTE], AND([OPERARIO]=[_THISROW].[OPERARIO],[FECHA]=[_THISROW].[FECHA]))) <= 1` |
| Cambiar estado (acción "Aprobar") | Action (Set columns) | `ESTADO = "Aprobado"`, `SUPERVISOR_REVISA = LOOKUP(USEREMAIL(),"OPERARIOS","EMAIL","COD_OPE")`, `FECHA_REVISION = NOW()` |
| Cambiar estado (acción "Rechazar") | Action (Set columns) | igual que arriba con `ESTADO = "Rechazado"` y `COMENTARIO_SUPERVISOR` obligatorio |

⚠️ Recordatorio sobre `MAX(...)+1`: con el enfoque simple que has confirmado, si dos personas guardan un parte en el mismo instante exacto existe un riesgo mínimo de colisión de número. Como lo has aceptado conscientemente, no lo cambio — si en el futuro este número adquiere valor administrativo/legal (tipo numeración de factura), se puede migrar a una tabla contador dedicada sin tener que rehacer el resto del diseño.

---

## 6. Vistas recomendadas

| Vista | Para | Tipo AppSheet | Origen |
|---|---|---|---|
| Inicio | Operario | Dashboard | Resumen de sus últimos partes + botón "Nuevo parte" |
| Nuevo parte | Operario | Form | `PARTES_CAB` (+ líneas `PARTES_DET` como Inline/Related) |
| Mis partes | Operario | Deck | `Slice_MisPartes` |
| Detalle del parte | Todos | Detail | `PARTES_CAB` |
| Pendientes/Rechazados | Operario | Deck (filtrado por `ESTADO`) | `Slice_MisPartes` |
| **Mi Perfil** | Todos | Detail (autorrellenada por email) | `OPERARIOS`, filtro `[EMAIL]=USEREMAIL()` — ver apartado 4.13 |
| Inicio supervisor | Supervisor | Dashboard | Contadores por estado |
| Partes pendientes de revisión | Supervisor | Table | `Slice_PendientesRevision` |
| Partes por trabajador | Supervisor | Table (agrupada) | `PARTES_CAB` |
| Partes por fecha | Supervisor | Calendar | `PARTES_CAB` |
| Partes por finca | Supervisor | Table + Chart | `PARTES_CAB` / `PARTES_DET` |
| Validación y revisión | Supervisor | Detail + Actions (Aprobar/Rechazar) | `PARTES_CAB` |
| Panel general | Admin | Dashboard | KPIs globales |
| Todos los partes | Admin | Table | `PARTES_CAB` |
| Usuarios/Operarios | Admin | Table/Form | `OPERARIOS` |
| Fincas y parcelas | Admin | Table/Form | `FINCAS`, `PARCELAS` |
| Tareas | Admin | Table/Form | `TAREAS` |
| Vehículos y aperos | Admin | Table/Form | `VEHICULOS`, `APEROS` |
| Mantenimiento | Admin/Supervisor | Deck/Table | `PARTES_MANT` |
| Informes | Admin | Chart/Dashboard | Agregados de `PARTES_CAB`/`PARTES_DET` |

Visibilidad de vistas por rol, en **View → Position/Behavior → Show if**:

```
LOOKUP(USEREMAIL(), "OPERARIOS", "EMAIL", "ROL_APP") = "ADMIN"
```
(sustituyendo por `"SUPERVISOR"` u `"OPERARIO"` donde corresponda).

---

## 7. Automatizaciones (Bots)

| Bot | Evento | Condición | Acción |
|---|---|---|---|
| Asignar NUM_PARTE | Add de `PARTES_CAB` | `ISBLANK([NUM_PARTE])` | Set columns: `NUM_PARTE = MAX(SELECT(PARTES_CAB[NUM_PARTE], TRUE)) + 1` |
| Notificar al crear parte | Add de `PARTES_CAB` | — | Notificación push/email a todos los `OPERARIOS` con `ROL_APP="SUPERVISOR"` |
| Notificar aprobación/rechazo | Update de `PARTES_CAB`, cambio en `ESTADO` | `ESTADO` pasa a `Aprobado` o `Rechazado` | Email/push al `[OPERARIO].[EMAIL]` |
| Recordatorio de pendientes | Programado (diario, 8:00) | `ESTADO = "Pendiente"` y `FCH_CREACION` > 3 días | Email a `ROL_APP="SUPERVISOR"` |
| Generar PDF del parte | Update de `PARTES_CAB`, `ESTADO="Aprobado"` | — | Acción "Generate PDF" con `PARTES_CAB` + `PARTES_DET` relacionadas |
| Enviar PDF por email | Igual que el anterior | — | Send Email con el PDF adjunto |
| Resumen semanal | Programado (lunes 7:00) | — | Email a `ROL_APP="ADMIN"` con horas totales por operario/finca |
| Notificar partes incompletos | Programado (diario) | `PARTES_CAB` sin ninguna línea en `PARTES_DET` tras X horas | Email al operario y/o supervisor |

---

## 8. Archivo Excel definitivo

Adjunto `BBDD_Corregida_AppSheet.xlsx`, generado a partir de tu `PT_EC.xlsx`, con estos cambios ya aplicados (detallados también en la hoja `LEEME` del propio archivo):

- `VEHICULOS`: 5 filas sin matrícula recibieron `ID_MAT` provisional (`SIN-MAT-Q1`, `SIN-MAT-Q2`, `SIN-MAT-Q3`, `SIN-MAT-T68`, `SIN-MAT-TRACTOR`).
- `VEHICULOS.TIPO`: `PLANTADORA` unificado a `PLANTADORAS`.
- `APEROS.TIPO`: corregidos `AB0NADORAS`→`ABONADORAS` y `SENBRADORAS`→`SEMBRADORAS` (19 filas afectadas).
- `PARTES_CAB`: cabecera `OSB` corregida a `OBS`.
- Formato profesional: fuente Arial, cabeceras resaltadas, fila de cabecera congelada, columnas autoajustadas.
- Comentario en la celda de cabecera `TIEMPO` recordando que su significado sigue pendiente de confirmar.

No he tocado nada más de tus datos: `OPERARIOS`, `FINCAS`, `PARCELAS`, `TAREAS`, `PARTES_DET` y `PARTES_MANT` se mantienen exactamente como los tenías en `PT_EC.xlsx`.

---

## 9. Guía paso a paso de implementación

1. **Preparar el Excel**: ya hecho — usa `BBDD_Corregida_AppSheet.xlsx`.
2. **Conectar el archivo a AppSheet**: `Data → Add table → From existing Excel`, una tabla por hoja (omite `LEEME`, es solo documentación).
3. **Configurar las tablas**: revisar que AppSheet detecta bien filas/columnas de cada hoja.
4. **Configurar claves y referencias**: fijar cada `Key` del apartado 2 y convertir las columnas `Ref` señaladas.
5. **Configurar tipos de columna**: Enum, Date, Time, Decimal, Yes/No, Image, LatLong según el apartado 2.
6. **Activar el login**: `Users & Access → Require sign-in`, y configurar `OPERARIOS` como App Users source (apartado 4.13).
7. **Configurar los roles**: usar exclusivamente `ROL_APP` (`ADMIN`/`SUPERVISOR`/`OPERARIO`).
8. **Crear los Security Filters**: uno por tabla, según apartado 4, incluyendo `PARTES_DET` y `PARTES_MANT`.
9. **Crear las vistas**: según apartado 6, incluida "Mi Perfil", con `Show_If` por rol.
10. **Crear las acciones**: "Aprobar", "Rechazar", "Generar PDF", "Nueva línea de tarea".
11. **Crear las automatizaciones (Bots)**: según apartado 7.
12. **Probar cada tipo de usuario**: con las 4 cuentas reales ya cargadas (una de ellas es `ADMIN` dos veces — `T000` y `T002` — así que ya tienes cobertura de los 3 roles).
13. **Publicar la aplicación**: `Deploy → Deployment Health Check` antes de publicar.

---

## 10. Lista final de comprobación

**Como Operario (probar con `juane@escribanosl.es`):**
- [ ] Al entrar, solo ve sus propios partes en "Mis partes".
- [ ] No puede ver ni buscar partes de otros operarios.
- [ ] Puede crear un parte nuevo y se autorrellena como `OPERARIO`.
- [ ] Puede editar su parte mientras está "Pendiente"; no puede una vez "Aprobado"/"Rechazado".
- [ ] Ve su propia ficha en "Mi Perfil", pero no puede cambiar su `ROL_APP` ni `ACTIVO`.

**Como Supervisor (probar con `maria@escribanosl.es`):**
- [ ] Ve los partes de todos los operarios, sin excepción.
- [ ] Puede filtrar por trabajador, fecha, finca y tarea.
- [ ] Puede aprobar/rechazar cualquier parte, quedando registrado quién y cuándo.

**Como Admin (probar con `partes.ecsl@gmail.com` o `jangel@escribanosl.es`):**
- [ ] Ve y edita todos los partes.
- [ ] Puede gestionar usuarios, fincas, parcelas, tareas, vehículos y aperos.
- [ ] Puede corregir cualquier parte en cualquier estado.
- [ ] Puede activar/desactivar usuarios.

**Seguridad:**
- [ ] Los Security Filters aplican también por API, no solo por las vistas visibles.
- [ ] Un usuario con `ACTIVO = FALSE` no puede entrar ni ver nada.
- [ ] El `NUM_PARTE` es correlativo y único entre los 4 usuarios de prueba, no reinicia por operario.

---

## Único punto abierto

¿Qué representa el campo `TIEMPO` de `PARTES_CAB`? En cuanto me lo digas, cierro la última incógnita del modelo y el diseño queda 100% definitivo.
