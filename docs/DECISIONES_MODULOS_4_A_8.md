# Decisiones para los módulos 4 a 8 (04/11/2026)

Respuestas del usuario a las 12 dudas (página "Dudas pendientes · Partes de Trabajo") y conversaciones del 29/10 al 04/11.
Contexto: la app es de **uso interno para controlar el gasto por parcela**; no es el registro horario oficial.
El diseño de pantallas lo hace **Lovable**; la base de datos, las funciones, el PDF y las pruebas, Claude Code.

| Módulo | Migración | Estado |
|---|---|---|
| 4 · Valores iniciales | `012_valores_iniciales.sql` | Aplicada y verificada 04/11 |
| 5 · Supervisor y auditoría de partes | `013_supervisor_y_auditoria_partes.sql` | Aplicada y verificada 04/11 |
| 6 · `fin_vuelta` | `014_fin_vuelta.sql` | Aplicada y verificada 04/11 |
| 7 · Archivo de tareas y vueltas | `015_archivo_tareas_y_vueltas.sql` | Aplicada y verificada 05/11 |
| 8 · PDF del parte | `016_pdf_partes.sql` + función del servidor `generar-pdf` | Aplicada y verificada 05/11 |

## 4 · Valores iniciales (012)
- `configuracion`: `cfh_ent` 07:30, `cfh_sal` 18:00, `cft_alm` 30 min, `cft_com` 90 min.
- Solo el ADMIN lee y modifica la tabla (también desde una pantalla de configuración en Lovable).
  Todos los roles leen esos 4 valores con `valores_iniciales_parte()`.
- Campo vacío o ausente → valor de la configuración, **al crear y al editar**. 0 minutos se escribe como 0.
- `th_jornada` pasa a **8,5 h** para que un parte con los valores iniciales tenga 0 horas extra (respuesta 1a).

## 5 · Supervisor y auditoría (013)
- El supervisor no tiene partes propios: revisa los de los operarios y crea los que un operario olvidó.
- Puede crear partes para cualquier operario activo y **revisar los que él mismo creó**.
- Edita **todos los partes en Pendiente y Cerrado**; los Rechazados solo el ADMIN (respuesta 3).
- Auditoría de `partes_cab` y `partes_det` como la de los catálogos: quién crea, modifica y aprueba.

## 6 · `fin_vuelta` (014)
- Vuelta = **parcela + código de tarea**.
- La pregunta solo aparece en líneas con parcela y tarea con tipo; en el resto la BD pone **No**.
- Sin respuesta al principio; obligatoria al cerrar el parte. El supervisor la verifica antes de aprobar.

## 7 · Archivo de tareas y vueltas (015)
- Solo cuentan los partes **Aprobados** ("confirmados").
- Tabla resumen: operario, fecha de la tarea, **código y nombre de la tarea**, vehículo, apero, finca, parcela,
  `fin_vuelta`, campaña y **duración en horas** (sin hora de inicio ni de fin).
- Se archivan todas las tareas **menos MOTIVOS PERSONALES y DESPLAZAMIENTO** (respuesta 8).
- Filas **agrupadas** por operario, día, tarea, parcela, vehículo y apero, sumando horas.
- Campaña = **año agrícola** con fecha de inicio en la configuración (`cfc_inicio` = 09-01); las vueltas empiezan de cero
  en cada campaña. En los partes no se guarda: se calcula con `campana_de(fecha)` y queda guardada en el archivo.
- Archivo "hasta una fecha" (solo ADMIN, como mucho hasta ayer): no se puede si queda algún parte Pendiente o Cerrado
  en el rango. Los Aprobados pasan al archivo y se borran sin copia individual en la auditoría (queda una anotación del
  archivado); **los Rechazados se borran sin archivar**, con su copia completa en la auditoría (decidido 05/11).
  Después nadie puede crear ni editar partes en esas fechas. (Archivar no exige PDF: ver módulo 8.)
- La vista de vueltas (finca, parcela, tarea, operario que marca el fin, fecha de fin) incluye el archivo y los
  Aprobados aún sin archivar. El "archivo de vueltas" del supervisor es una exportación de esa vista.
- **Horas por trabajador**: solo exportación CSV (parte, operario, fecha, entrada, salida, almuerzo, comida)
  **antes de archivar**, sin tabla propia (respuesta 12). Al borrar los partes esos datos dejan de estar en la BD.

## 8 · PDF del parte (016)
- **Cambio del 05/11: no se genera automáticamente.** Botón "Generar PDF" (imprimir) a petición, solo para el
  SUPERVISOR y el ADMIN y solo en partes **Aprobados**.
- Lo ven el ADMIN, el supervisor y el operario titular. Si el parte no ha cambiado desde el último PDF, el botón
  devuelve ese; si el ADMIN lo corrigió, se genera una versión nueva y se conserva la anterior.
- Se guarda en almacenamiento privado de Supabase (bucket `partes-pdf`), en la carpeta `cfp_carpeta` de la configuración
  (por defecto `partes`). Una carpeta de un ordenador o servidor de la oficina no es posible: Supabase no puede escribir ahí.
- **Archivar no exige el PDF** (decidido 05/11). De los partes archivados sin PDF solo quedan el resumen de tareas y el
  CSV de horas si se exportó. Los PDF existentes se conservan al archivar o borrar el parte.
