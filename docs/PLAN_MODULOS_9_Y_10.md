# Plan: correcciones, mantenimiento como tarea y validación por línea

Plan acordado el 10/11/2026. Estado de cada paso al final del documento.

## Decisiones (respuestas del 10/11/2026)

- **Validación por línea:** cada línea se valida **y se guarda** al pulsar "Aceptar". El parte se crea al
  aceptar la jornada (así también existen partes sin tareas mientras se rellenan).
- **Orden:** las líneas se meten en orden de hora. Cada línea nueva empieza cuando acaba la última o más tarde.
- **Pantalla del parte en 3 pestañas:** Cabecera, Tareas y Mantenimiento.
- **Mantenimiento como tarea:** se elimina la tabla `partes_mant` y la casilla `mat_nave`. Se crean dos tipos de
  tarea nuevos, **MANTENIMIENTO NAVE** y **MANTENIMIENTO VEHÍCULOS**, que forman parte del ciclo normal de tareas
  (`partes_det`).
- **Un solo horario:** tareas y mantenimientos van dentro de la jornada, en orden y sin solaparse.
- **Mantenimiento sin finca:** no lleva finca y no rompe la cadena de desplazamientos.
- **MANTENIMIENTO VEHÍCULOS** lleva vehículo o apero (al menos uno). Lo que se hizo va en Observaciones.
- **Archivo:** los mantenimientos se conservan al archivar (pasan a `tareas_realizadas`).

Comprobado en la BD el 10/11/2026: `partes_mant` vacía, 0 partes con `mat_nave`, 1 parte en total.
No hay datos que migrar.

## Reglas por tipo de tarea

| Tipo | Qué se rellena | ¿Primera tarea? | Cadena de desplazamientos |
|---|---|---|---|
| DESPLAZAMIENTO | finca y vehículo | Sí | Marca la finca en la que se está |
| MANTENIMIENTO NAVE | solo horas | Sí | No le afecta |
| MANTENIMIENTO VEHÍCULOS | vehículo o apero; sin finca ni parcela | No | No le afecta |
| POR HORAS / POR SUPERFICIE (HAS) | finca (parcela, vehículo y apero opcionales) | No | Necesita antes un desplazamiento a esa finca |
| MOTIVOS PERSONALES | solo horas | No cuenta | No le afecta |

- La primera tarea (sin contar MOTIVOS PERSONALES) es DESPLAZAMIENTO o MANTENIMIENTO NAVE.
- Para cerrar un parte hace falta al menos una línea que no sea MOTIVOS PERSONALES
  (sustituye a la regla de `mat_nave`).
- `fin_vuelta` no se pregunta en los mantenimientos (se guarda No).

## Pantalla

1. **Cabecera:** operario, fecha, entrada y salida, almuerzo y comida, horas extra (solo el ADMIN) y
   observaciones. Con **"Aceptar jornada"** se crea el parte en Pendiente; las otras pestañas se activan
   cuando existe. Muestra un resumen: jornada, horas de tareas, horas de mantenimiento y tiempo sin asignar.
2. **Tareas:** DESPLAZAMIENTO, POR HORAS, POR SUPERFICIE y MOTIVOS PERSONALES.
3. **Mantenimiento:** MANTENIMIENTO NAVE y MANTENIMIENTO VEHÍCULOS.

En las dos pestañas de líneas:
- "+ Añadir" abre una sola línea con **Aceptar** y **Cancelar**. Al aceptar se valida contra todas las líneas
  del día (las dos pestañas) y se guarda. Los errores salen debajo de la línea.
- La línea nueva propone como inicio el fin de la última línea del día, de cualquier pestaña. Se muestra cuál es.
- Una sola línea abierta en todo el parte. Aviso al cambiar de pestaña o de pantalla con una línea sin aceptar.
- Editar o quitar una línea se permite si el resto del día sigue siendo válido.
- Cambiar la jornada se rechaza si deja alguna línea fuera; el mensaje dice cuáles.

Detalle y PDF: tareas y mantenimientos en dos tablas separadas; desaparece "Mant. nave".

## Pasos

| Paso | Contenido | Estado |
|---|---|---|
| 0 | Guardar en git el módulo 8 (PDF) | Hecho 10/11 |
| 1 | **017** `017_correcciones_analisis.sql`: sin pausas negativas; pausas no mayores que la jornada. App: fecha de hoy en hora local, listados y CSV sin el corte de 1.000 filas, pausas negativas rechazadas | Hecho 10/11: app; 017 aplicada y verificada 6/6 |
| 2 | **018** mantenimiento como tarea: tipos y tareas nuevos; `validar_parte()`; regla de cierre (disparador de estado); quitar `mat_nave` de `guardar_parte()`, `pdf_datos()` y `panel_resumen()`; borrar `partes_mant` y `mat_nave` (comprobando antes que están vacías). Irreversible: se aplica solo con autorización | Hecho 10/11: 018 aplicada y verificada 14/14; app y `generar-pdf` (v2 desplegada) adaptadas |
| 3 | **019** validación por línea: `guardar_cabecera()`, `guardar_linea()`, `borrar_linea()` con regla de orden y permisos actuales. `guardar_parte()` se mantiene por compatibilidad | Hecho 10/11: 019 aplicada y verificada 14/14 |
| 4 | Función `generar-pdf`: sección de mantenimientos, sin `mat_nave` | Pendiente |
| 5 | App: `rules.js` (tipos nuevos, `validarLinea`), `supabase.js` y `mock.js` (funciones nuevas), `main.js` (formulario en 3 pestañas; detalle y lista sin nave) | Pendiente |
| 6 | Pruebas: `pruebas_modulo9.sql` (mantenimiento), `pruebas_modulo10.sql` (por línea); adaptar las de los módulos 1 a 8 que usan `mat_nave` | Pendiente |
| 7 | Documentación: decisiones, `supabase/README.md`, `docs/BOCETO.md` | Pendiente |

Estimación de los pasos 2 a 7: 2 o 3 días (primero BD y pruebas, después pantalla).

## Riesgos

- Una llamada al servidor por línea: más tráfico en el móvil, pero no se pierde trabajo si se cierra el navegador.
- La 018 borra una tabla y una columna (vacías y sin uso hoy; la migración lo vuelve a comprobar).
- `pdf_datos()` de la 016 usa `mat_nave`: la 018 debe sustituirla a la vez que borra la columna.
