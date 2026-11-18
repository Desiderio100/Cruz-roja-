// Pruebas de la Agenda de citas (src/rutas/citas.js y src/rutas/dispositivos.js) contra las
// rutinas de db/07_citas_rutinas.sql: el recorrido completo de una cita (crear, leer,
// reprogramar y cancelar) y sus reglas.
//
// Usan un MySQL LOCAL de verdad. Se niegan a correr contra otra base que no sea local,
// porque crean y borran citas y dispositivos de prueba.
//
// Cómo correrlas:  npm run probar:citas   (necesitas backend/.env.local, ver .env.local.example)

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { crearPool } from '../src/db.js';
import { manejadorDeErrores } from '../src/errores.js';
import { rutasCitas } from '../src/rutas/citas.js';
import { rutasDispositivos } from '../src/rutas/dispositivos.js';

const baseLocal = ['127.0.0.1', 'localhost'].includes(process.env.DB_HOST);
const ZONA = '-06:00';
const persona = { nombre: 'Ana Prueba', telefono: '8112345678' };

// Un día entre semana, dentro de dos semanas, como fecha local AAAA-MM-DD.
function diaHabil(semanas = 2) {
  const dia = new Date(Date.now() + semanas * 7 * 86_400_000);
  while ([0, 6].includes(dia.getUTCDay())) dia.setUTCDate(dia.getUTCDate() + 1);
  return dia.toISOString().slice(0, 10);
}

describe('Agenda de citas', { skip: baseLocal ? false : 'DB_HOST debe ser 127.0.0.1 o localhost (ver .env.local.example)' }, () => {
  let pool, servidor, url;
  let delegacionId, especialistas;
  const dispositivos = [];
  const fecha = diaHabil();

  before(async () => {
    pool = crearPool();
    const app = express();
    app.use(express.json({ limit: '16kb' }));
    app.use('/api/citas', rutasCitas(pool));
    app.use('/api/dispositivos', rutasDispositivos(pool));
    app.use(manejadorDeErrores);
    servidor = await new Promise((listo) => { const s = app.listen(0, '127.0.0.1', () => listo(s)); });
    url = `http://127.0.0.1:${servidor.address().port}`;

    // La delegación con más especialistas de nutrición en los datos de prueba (02_datos_prueba.sql).
    const [[fila]] = await pool.query(
      `SELECT delegacion_id, COUNT(*) AS total FROM especialista
        WHERE servicio = 'nutricion' AND activo = 1 GROUP BY delegacion_id ORDER BY total DESC, delegacion_id LIMIT 1`);
    delegacionId = fila.delegacion_id;
    especialistas = fila.total;
  });

  after(async () => {
    if (servidor) await new Promise((listo) => servidor.close(listo));
    if (pool) {
      if (dispositivos.length) {
        await pool.query('DELETE FROM cita WHERE dispositivo_id IN (?)', [dispositivos]);
        await pool.query('DELETE FROM dispositivo WHERE id IN (?)', [dispositivos]);
      }
      await pool.end();
    }
  });

  // ── ayudas ────────────────────────────────────────────────────────────────
  const pedir = async (metodo, ruta, { cuerpo, dispositivo } = {}) => {
    const r = await fetch(url + ruta, {
      method: metodo,
      headers: {
        ...(cuerpo ? { 'Content-Type': 'application/json' } : {}),
        ...(dispositivo ? { 'X-Dispositivo-Id': dispositivo } : {}),
      },
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    const texto = await r.text();
    return { estado: r.status, json: texto ? JSON.parse(texto) : null };
  };

  async function nuevoDispositivo() {
    const { estado, json } = await pedir('POST', '/api/dispositivos', { cuerpo: {} });
    assert.equal(estado, 201);
    dispositivos.push(json.id);
    return json.id;
  }

  const horarios = async (servicio = 'nutricion') => (await pedir('GET',
    `/api/citas/horarios?delegacion_id=${delegacionId}&servicio=${servicio}&fecha=${fecha}&zona=${encodeURIComponent(ZONA)}`)).json;

  const agendar = (dispositivo, inicio, extra = {}) => pedir('POST', '/api/citas', {
    dispositivo,
    cuerpo: { delegacion_id: delegacionId, servicio: 'nutricion', inicio, zona: ZONA, ...persona, ...extra },
  });

  const libres = async (inicio) => (await horarios()).find((h) => h.inicio === inicio)?.especialistas_libres ?? 0;

  // ── dispositivo ───────────────────────────────────────────────────────────
  test('registrar un dispositivo devuelve un id con forma de UUID', async () => {
    const id = await nuevoDispositivo();
    assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  });

  // ── horarios (RF20) ───────────────────────────────────────────────────────
  test('nutrición ofrece 7 bloques de una hora (9:00 a 16:00) y psicología 8 (9:00 a 17:00)', async () => {
    const nutricion = await horarios('nutricion');
    assert.equal(nutricion.length, 7);
    assert.equal(nutricion[0].inicio, `${fecha}T15:00:00.000Z`); // 9:00 en -06:00
    assert.ok(nutricion.every((h) => h.especialistas_libres >= 1));
    const psicologia = await horarios('psicologia');
    assert.equal(psicologia.length, 8);
  });

  // ── recorrido completo: crear, leer, reprogramar, cancelar ────────────────
  test('una cita se agenda, aparece en mis citas, se reprograma y se cancela; el horario se libera', async () => {
    const d = await nuevoDispositivo();
    const [primero, segundo] = await horarios();
    const antes = await libres(primero.inicio);

    // Crear
    const alta = await agendar(d, primero.inicio);
    assert.equal(alta.estado, 201);
    assert.match(alta.json.folio, /^CR-\d{6}$/);
    assert.equal(alta.json.estado, 'confirmada');
    assert.equal(alta.json.servicio, 'nutricion');
    assert.equal(alta.json.inicio, primero.inicio);
    assert.equal(alta.json.delegacion_id, delegacionId);
    assert.equal(await libres(primero.inicio), antes - 1);

    // Leer
    const mias = await pedir('GET', '/api/citas', { dispositivo: d });
    assert.equal(mias.estado, 200);
    assert.deepEqual(mias.json.map((c) => c.id), [alta.json.id]);

    // El personal la pospone (lo hace el panel del personal; aquí se simula en la base).
    await pool.query("UPDATE cita SET estado = 'pospuesta' WHERE id = ?", [alta.json.id]);
    assert.equal(await libres(primero.inicio), antes);          // pospuesta libera el horario
    assert.equal((await pedir('GET', '/api/citas', { dispositivo: d })).json[0].estado, 'pospuesta');

    // Reprogramar (actualizar)
    const cambio = await pedir('POST', `/api/citas/${alta.json.id}/reprogramar`, {
      dispositivo: d, cuerpo: { inicio: segundo.inicio, zona: ZONA },
    });
    assert.equal(cambio.estado, 200);
    assert.equal(cambio.json.id, alta.json.id);
    assert.equal(cambio.json.folio, alta.json.folio);
    assert.equal(cambio.json.estado, 'confirmada');
    assert.equal(cambio.json.inicio, segundo.inicio);

    // Cancelar (borrado lógico: la cita queda como cancelada y deja de aparecer)
    const baja = await pedir('POST', `/api/citas/${alta.json.id}/cancelar`, { dispositivo: d });
    assert.equal(baja.estado, 204);
    assert.deepEqual((await pedir('GET', '/api/citas', { dispositivo: d })).json, []);
    const [[fila]] = await pool.query('SELECT estado FROM cita WHERE id = ?', [alta.json.id]);
    assert.equal(fila.estado, 'cancelada');

    // Cancelar otra vez: ya no existe para la persona
    assert.equal((await pedir('POST', `/api/citas/${alta.json.id}/cancelar`, { dispositivo: d })).estado, 404);
  });

  // ── reglas ────────────────────────────────────────────────────────────────
  test('un horario se llena cuando todos los especialistas están ocupados (409) y deja de ofrecerse', async () => {
    const lista = await horarios();
    const inicio = lista[lista.length - 1].inicio;
    const disponibles = await libres(inicio);
    assert.ok(disponibles >= 1 && disponibles <= especialistas);
    for (let i = 0; i < disponibles; i++) {
      const r = await agendar(await nuevoDispositivo(), inicio, { telefono: `811000000${i}` });
      assert.equal(r.estado, 201);
    }
    const sobra = await agendar(await nuevoDispositivo(), inicio);
    assert.equal(sobra.estado, 409);
    assert.equal(sobra.json.error, 'ese horario ya no está disponible');
    assert.equal((await horarios()).some((h) => h.inicio === inicio), false);
  });

  test('una cita solo la ve y la modifica el dispositivo que la creó', async () => {
    const dueno = await nuevoDispositivo();
    const otro = await nuevoDispositivo();
    const [, , tercero, cuarto] = await horarios();
    const alta = await agendar(dueno, tercero.inicio);
    assert.equal(alta.estado, 201);

    assert.deepEqual((await pedir('GET', '/api/citas', { dispositivo: otro })).json, []);
    assert.equal((await pedir('POST', `/api/citas/${alta.json.id}/cancelar`, { dispositivo: otro })).estado, 404);
    const cambio = await pedir('POST', `/api/citas/${alta.json.id}/reprogramar`, {
      dispositivo: otro, cuerpo: { inicio: cuarto.inicio, zona: ZONA },
    });
    assert.equal(cambio.estado, 404);
    assert.equal((await pedir('GET', '/api/citas', { dispositivo: dueno })).json[0].estado, 'confirmada');
  });

  test('rechaza datos no válidos y horas fuera del horario de atención', async () => {
    const d = await nuevoDispositivo();
    const [primero] = await horarios();
    assert.equal((await agendar(d, primero.inicio, { nombre: 'Al' })).estado, 400);
    assert.equal((await agendar(d, primero.inicio, { telefono: '123' })).estado, 400);
    assert.equal((await agendar(d, primero.inicio, { servicio: 'capacitacion' })).estado, 400);
    assert.equal((await agendar(d, 'no-es-fecha')).estado, 400);
    assert.equal((await agendar(d, primero.inicio, { zona: 'Monterrey' })).estado, 400);
    const fueraDeHorario = await agendar(d, `${fecha}T09:00:00.000Z`); // 3:00 de la mañana en -06:00
    assert.equal(fueraDeHorario.estado, 409);
    assert.equal((await pedir('GET', '/api/citas')).estado, 401);       // sin dispositivo
    assert.deepEqual((await pedir('GET', '/api/citas', { dispositivo: d })).json, []);
  });

  test('con un dispositivo que la base no conoce, pide registrarlo (la app reintenta)', async () => {
    const [primero] = await horarios();
    const r = await agendar(randomUUID(), primero.inicio);
    assert.equal(r.estado, 400);
    assert.equal(r.json.error, 'dispositivo no registrado');
  });
});
