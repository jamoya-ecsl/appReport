# Decisiones para los módulos 4 a 8 (04/11/2026)

Respuestas del usuario a las 12 dudas (página "Dudas pendientes · Partes de Trabajo") y conversaciones del 29/10 al 04/11.
Contexto: la app es de **uso interno para controlar el gasto por parcela**; no es el registro horario oficial.
El diseño de pantallas lo hace **Lovable**; la base de datos, las funciones, el PDF y las pruebas, Claude Code.

| Módulo | Migración | Estado |
|---|---|---|
| 4 · Valores iniciales | `012_valores_iniciales.sql` | Aplicada y verificada 04/11 |
| 5 · Supervisor y auditoría de partes | 013 | Por preparar |
| 6 · `fin_vuelta` | 014 | Por preparar |
| 7 · Archivo de tareas y vueltas | 015 | Por preparar |
| 8 · PDF al aprobar | 016 + función del servidor (Edge Function) | Por preparar |

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
- Campaña = **año agrícola** con fecha de inicio en la configuración; las vueltas empiezan de cero en cada campaña.
  Pendiente de decidir al preparar la 015: si además se guarda la campaña en alguna tabla de partes
  (propuesta: no, se calcula a partir de la fecha y se guarda en el archivo).
- Archivo "hasta una fecha" (solo ADMIN): exige que todos los partes del rango estén Aprobados y con PDF;
  después se borran esos partes y nadie puede crear ni editar partes en esas fechas.
- La vista de vueltas (finca, parcela, tarea, operario que marca el fin, fecha de fin) incluye el archivo y los
  Aprobados aún sin archivar. El "archivo de vueltas" del supervisor es una exportación de esa vista.
- **Horas por trabajador**: solo exportación CSV (parte, operario, fecha, entrada, salida, almuerzo, comida)
  **antes de archivar**, sin tabla propia (respuesta 12). Al borrar los partes esos datos dejan de estar en la BD.

## 8 · PDF al aprobar (016)
- Se genera automáticamente al aprobar y se guarda en almacenamiento privado de Supabase (Storage).
- Lo ven el ADMIN, el supervisor y el operario titular; si el ADMIN corrige el parte, se genera uno nuevo y se
  conserva el anterior.
- Pendiente: la "ruta de guardado" configurable. Dentro de Supabase sí (carpeta configurable en `configuracion`);
  una carpeta de un ordenador o servidor de la oficina no, porque Supabase no puede escribir ahí.
