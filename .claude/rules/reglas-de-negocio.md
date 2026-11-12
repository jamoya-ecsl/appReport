---
paths:
  - "supabase/**"
  - "app/js/**"
  - "scripts/test-rules.mjs"
  - "docs/**"
---

# Reglas de negocio de los partes

Las impone la BD (`validar_parte()`, disparadores y RPC) y las repite `app/js/rules.js`.
Si cambia una regla, cambiar las dos copias y sus pruebas.

## Roles (`operarios.rol_app`)
- **OPERARIO**:
  - crea y lee sus partes;
  - edita y cierra solo en Pendiente;
  - nunca crea a nombre de otro ni aprueba.
- **SUPERVISOR**:
  - crea partes para cualquier operario activo;
  - corrige los partes Pendientes y Cerrados (no los Aprobados ni los Rechazados);
  - aprueba o rechaza los Cerrados, también los que creó, pero nunca aquellos de los que es titular.
- **ADMIN**:
  - todo, incluido borrar, archivar y modificar la configuración;
  - nunca puede quedar la app sin un ADMIN activo.
- Nadie crea partes a nombre de un operario dado de baja.
- Un registro dado de baja no se usa en partes nuevos; los antiguos lo conservan.

## Estados
- Pendiente → Cerrado → Aprobado | Rechazado, sin vuelta atrás.
- Todo parte nace Pendiente y solo se revisa un parte Cerrado.
- Rechazar exige comentario.
- Cerrar exige:
  - al menos una tarea que no sea MOTIVOS PERSONALES;
  - respuesta de `fin_vuelta` en todas las tareas que la requieren.

## Jornada (cabecera)
- Un parte por operario y día, con salida > entrada.
- Horas, pausas y `h_ext` en múltiplos de 15 minutos.
- Almuerzo y comida:
  - 0 o más, sin superar la jornada;
  - un campo vacío toma el valor de `configuracion` (`cfh_ent` 07:30, `cfh_sal` 18:00, `cft_alm` 30, `cft_com` 90);
  - 0 se respeta.
- `h_ext` lo calcula la BD con `th_jornada` (8,5). Solo el ADMIN lo corrige a mano.

## Líneas (tareas)
- Van dentro de la jornada, en orden de hora y sin solaparse.
- La línea nueva empieza cuando acaba la última; la editada queda entre la anterior y la siguiente.
- La primera línea (sin contar MOTIVOS PERSONALES) es DESPLAZAMIENTO (con finca y vehículo) o MANTENIMIENTO NAVE.
- Cada tipo lleva lo siguiente:

| Tipo | Lleva | Cadena de fincas |
|---|---|---|
| DESPLAZAMIENTO (TD001) | finca y vehículo | marca la finca en curso |
| MANTENIMIENTO NAVE (TN001) | solo horas | no le afecta |
| MANTENIMIENTO VEHÍCULOS (TV001) | vehículo o apero, sin finca | no le afecta |
| MOTIVOS PERSONALES (TP001) | solo horas | no le afecta |
| POR HORAS / POR SUPERFICIE (HAS) | finca (parcela, vehículo y apero opcionales) | exige un desplazamiento previo a esa finca |

- Cambiar de finca exige otro DESPLAZAMIENTO.
- La parcela debe ser de la finca.
- **`fin_vuelta`** (vuelta = parcela + código de tarea):
  - solo se pregunta en líneas con parcela y tipo POR SUPERFICIE o POR HORAS; en el resto la BD guarda No;
  - `null` significa sin responder.

## Archivo, vueltas y PDF
- Solo cuentan los partes **Aprobados**.
- Campaña = año agrícola desde `cfc_inicio` (09-01): `campana_de(fecha)`.
- `archivar_partes(hasta)`:
  - solo ADMIN, como mucho hasta ayer;
  - no se puede si queda algún parte Pendiente o Cerrado en el rango;
  - pasa los Aprobados agrupados a `tareas_realizadas`, sin DESPLAZAMIENTO ni MOTIVOS PERSONALES;
  - borra los Rechazados con su copia en `auditoria`;
  - después no se crean ni se editan partes en esas fechas;
  - no se puede deshacer: exportar antes `horas_trabajador`.
- Las vistas `vueltas`, `tareas_resumen` y `horas_trabajador` solo devuelven filas a ADMIN y SUPERVISOR.
- PDF:
  - se genera solo a petición (`generar-pdf`), en partes Aprobados, y lo piden SUPERVISOR y ADMIN;
  - lo ven también el operario titular;
  - si el parte no cambió, se devuelve la misma versión;
  - archivar no exige PDF.
- Cada cambio en catálogos, usuarios, configuración, partes y tareas queda en `auditoria`.
