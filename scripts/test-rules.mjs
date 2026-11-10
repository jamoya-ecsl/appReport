// Pruebas de las reglas de la app (app/js/rules.js). Uso: npm test
// Las mismas reglas las impone la base de datos (validar_parte, guardar_linea...); estas pruebas evitan que la copia
// de la app se separe de ellas sin que nadie se entere. Casos tomados de supabase/pruebas (módulos 1, 9 y 10).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validarParte, validarLinea, errorOrdenLinea, errorCierre, errorSinTareas, calcTotHoras, calcHExt, campanaDe,
  fechaLocal, aCsv, conValoresIniciales, requiereFinVuelta,
} from '../app/js/rules.js';

const cat = {
  fincas: [{ cod_fin: 'F1', finca: 'Finca 1' }, { cod_fin: 'F2', finca: 'Finca 2' }],
  parcelas: [{ cod_par: 'P1', finca: 'F1', nom_parc: 'Parcela 1' }],
  tareas: [
    { cod_tar: 'TD', tipo: 'DESPLAZAMIENTO' }, { cod_tar: 'TP', tipo: 'MOTIVOS PERSONALES' },
    { cod_tar: 'TH', tipo: 'POR HORAS' }, { cod_tar: 'TS', tipo: 'POR SUPERFICIE (HAS)' },
    { cod_tar: 'TN', tipo: 'MANTENIMIENTO NAVE' }, { cod_tar: 'TV', tipo: 'MANTENIMIENTO VEHÍCULOS' },
  ],
};
const cab = { operario: 'O', fecha: '2099-01-01', h_ent: '07:00', h_sal: '15:00', t_alm_min: 30, t_com_min: 0 };
const L = (tarea, h_ini, h_fin, x = {}) => ({ tarea, h_ini, h_fin, ...x });
const desp = L('TD', '07:00', '07:30', { finca: 'F1', vehiculo: 'V1', id_linea: 'l1' });
const ok = (errores) => assert.deepEqual(errores, []);
const falla = (errores, texto) => assert.ok(errores.some((e) => e.includes(texto)), `esperado "${texto}" en ${JSON.stringify(errores)}`);

test('jornada: pausas, 15 minutos y total', () => {
  ok(validarParte(cab, [], cat));
  falla(validarParte({ ...cab, t_alm_min: -60 }, [], cat), 'no pueden ser negativos');           // 017
  falla(validarParte({ ...cab, h_sal: '08:00', t_alm_min: 60, t_com_min: 15 }, [], cat), 'superan la duración');
  falla(validarParte({ ...cab, h_ent: '07:10' }, [], cat), '15 minutos');
  assert.equal(calcTotHoras(cab), 7.5);
  assert.equal(calcHExt({ ...cab, h_sal: '17:00' }, 8), 1.5);
});

test('valores iniciales: vacío → configuración; 0 se respeta', () => {
  const ini = { h_ent: '07:30', h_sal: '18:00', t_alm_min: 30, t_com_min: 90 };
  const c = conValoresIniciales({ h_ent: '', h_sal: null, t_alm_min: 0, t_com_min: '' }, ini);
  assert.deepEqual([c.h_ent, c.h_sal, c.t_alm_min, c.t_com_min], ['07:30', '18:00', 0, 90]);
});

test('cadena de desplazamientos (módulo 1)', () => {
  ok(validarParte(cab, [desp, L('TH', '07:30', '09:00', { finca: 'F1' })], cat));
  falla(validarParte(cab, [L('TH', '07:00', '08:00', { finca: 'F1' })], cat), 'la primera tarea');
  falla(validarParte(cab, [desp, L('TH', '07:30', '08:00', { finca: 'F2' })], cat), 'hace falta antes un DESPLAZAMIENTO');
  falla(validarParte(cab, [desp, L('TH', '07:15', '08:00', { finca: 'F1' })], cat), 'se solapa');
  falla(validarParte(cab, [L('TD', '06:45', '07:30', { finca: 'F1', vehiculo: 'V1' })], cat), 'dentro de la jornada');
  falla(validarParte(cab, [L('TP', '07:00', '07:30', { finca: 'F1' })], cat), 'solo se indican las horas');
});

test('mantenimiento como tarea (módulo 9, migración 018)', () => {
  ok(validarParte(cab, [L('TN', '07:00', '08:00'), L('TD', '08:00', '08:30', { finca: 'F1', vehiculo: 'V1' }), L('TH', '08:30', '10:00', { finca: 'F1' })], cat));
  falla(validarParte(cab, [L('TN', '07:00', '08:00', { finca: 'F1' })], cat), 'solo se indican las horas');
  falla(validarParte(cab, [L('TV', '07:00', '08:00', { vehiculo: 'V1' })], cat), 'la primera tarea');
  falla(validarParte(cab, [desp, L('TV', '07:30', '08:30')], cat), 'vehículo o apero');
  falla(validarParte(cab, [desp, L('TV', '07:30', '08:30', { finca: 'F1', vehiculo: 'V1' })], cat), 'no se indica finca ni parcela');
  ok(validarParte(cab, [desp, L('TH', '07:30', '09:00', { finca: 'F1' }), L('TV', '09:00', '10:00', { vehiculo: 'V1' }), L('TH', '10:00', '11:00', { finca: 'F1' })], cat));
  falla(validarParte(cab, [L('TN', '07:00', '08:00'), L('TH', '08:00', '09:00', { finca: 'F1' })], cat), 'hace falta antes un DESPLAZAMIENTO');
  ok(validarParte(cab, [L('TN', '07:00', '08:00'), L('TV', '08:00', '09:00', { apero: 'A1' })], cat));
});

test('cierre: al menos una tarea que no sea MOTIVOS PERSONALES', () => {
  assert.ok(errorCierre([L('TP', '07:00', '08:00')], cat));
  assert.equal(errorCierre([L('TN', '07:00', '14:30')], cat), null);
  assert.ok(errorSinTareas('Cerrado', [], cat));
  assert.equal(errorSinTareas('Pendiente', [], cat), null);
});

test('guardar por líneas (módulo 10, migración 019)', () => {
  const lineas = [desp, L('TH', '07:30', '09:00', { finca: 'F1', id_linea: 'l2' }), L('TH', '09:00', '10:00', { finca: 'F1', id_linea: 'l3' })];
  assert.match(errorOrdenLinea(lineas, L('TH', '09:45', '11:00', { finca: 'F1' })), /10:00 o más tarde/);
  assert.equal(errorOrdenLinea(lineas, L('TH', '10:00', '11:00', { finca: 'F1' })), null);
  assert.match(errorOrdenLinea(lineas, L('TH', '07:30', '09:30', { finca: 'F1', id_linea: 'l2' })), /09:00 o antes/);
  assert.equal(errorOrdenLinea(lineas, L('TH', '07:30', '08:30', { finca: 'F1', id_linea: 'l2' })), null);
  ok(validarLinea(cab, L('TH', '10:00', '11:00', { finca: 'F1' }), lineas, cat));
  falla(validarLinea(cab, L('TH', '10:00', '11:00', { finca: 'F2' }), lineas, cat), 'hace falta antes un DESPLAZAMIENTO');
  falla(validarLinea(cab, L('', '10:00', '11:00'), lineas, cat), 'Falta la tarea');
  falla(validarLinea(cab, L('TH', '14:30', '15:30', { finca: 'F1' }), lineas, cat), 'dentro de la jornada');
});

test('fin de vuelta solo en tareas con parcela y por horas o superficie', () => {
  assert.equal(requiereFinVuelta(L('TH', '07:30', '08:00', { parcela: 'P1' }), cat), true);
  assert.equal(requiereFinVuelta(L('TH', '07:30', '08:00'), cat), false);
  assert.equal(requiereFinVuelta(L('TV', '07:30', '08:00', { parcela: 'P1' }), cat), false);
});

test('campaña agrícola y fecha local', () => {
  assert.equal(campanaDe('2026-08-31'), '2025/26');
  assert.equal(campanaDe('2026-09-01'), '2026/27');
  assert.equal(fechaLocal(new Date(2026, 0, 1, 0, 30)), '2026-01-01');   // en España, toISOString daría el 31/12
});

test('CSV: texto que parece fórmula se neutraliza; números negativos no', () => {
  const csv = aCsv([{ a: '=HYPERLINK("x")', b: '+1', c: -1.5, d: 'normal', e: true }],
    [['a', 'A'], ['b', 'B'], ['c', 'C'], ['d', 'D'], ['e', 'E']]);
  const fila = csv.split('\r\n')[1];
  assert.equal(fila, `"'=HYPERLINK(""x"")";'+1;-1,5;normal;Sí`);
});
