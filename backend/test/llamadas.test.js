// Pruebas de la transcripción de la llamada de emergencia (RF12, HU09, src/rutas/llamadas.js).
//
// Usan un MySQL LOCAL de verdad. Se niegan a correr contra otra base que no sea local,
// porque crean y borran llamadas, dispositivos y una cuenta de operador de prueba.
// Necesitan db/10_modo_personal.sql y db/12_transcripcion_app.sql.
//
// Cómo correrlas:  npm run probar:llamadas   (necesitas backend/.env.local, ver .env.local.example)

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import express from 'express';
import { crearPool, llamar } from '../src/db.js';
import { manejadorDeErrores } from '../src/errores.js';
import { rutasLlamadas } from '../src/rutas/llamadas.js';

const baseLocal = ['127.0.0.1', 'localhost'].includes(process.env.DB_HOST);
// Centro de Monterrey: la delegación más cercana sale de los datos de prueba (db/02).
const MONTERREY = { latitude: 25.6866, longitude: -100.3161 };

describe('Emergencia: transcripción de la llamada', { skip: baseLocal ? false : 'DB_HOST debe ser 127.0.0.1 o localhost (ver .env.local.example)' }, () => {
  let pool, servidor, url;
  let dispositivoId, otroDispositivoId, operadorId;
  const llamadas = [];
  const usuarioOperador = `prueba.operador.${randomUUID().slice(0, 8)}`;

  before(async () => {
    pool = crearPool();
    const app = express();
    app.use(express.json({ limit: '64kb' }));
    app.use('/api/llamadas', rutasLlamadas(pool));
    app.use(manejadorDeErrores);
    servidor = await new Promise((listo) => { const s = app.listen(0, '127.0.0.1', () => listo(s)); });
    url = `http://127.0.0.1:${servidor.address().port}`;

    dispositivoId = randomUUID();
    otroDispositivoId = randomUUID();
    await pool.query('INSERT INTO dispositivo (id) VALUES (?), (?)', [dispositivoId, otroDispositivoId]);
  });

  after(async () => {
    if (servidor) await new Promise((listo) => servidor.close(listo));
    if (pool) {
      if (llamadas.length) {
        // Al borrar la llamada se va su transcripción (ON DELETE CASCADE).
        await pool.query('DELETE FROM ficha WHERE llamada_id IN (?)', [llamadas]);
        await pool.query('DELETE FROM llamada WHERE id IN (?)', [llamadas]);
      }
      // La cuenta del operador se desactiva en vez de borrarse (igual que en producción).
      if (operadorId) await pool.query('UPDATE personal SET activo = 0 WHERE id = ?', [operadorId]);
      await pool.query('DELETE FROM dispositivo WHERE id IN (?, ?)', [dispositivoId, otroDispositivoId]);
      await pool.end();
    }
  });

  // ── ayudas ────────────────────────────────────────────────────────────────
  const enviar = (metodo, ruta, cuerpo) =>
    fetch(url + ruta, { method: metodo, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo) });

  /** Crea una llamada como lo hace la app y devuelve su id y su delegación. */
  async function nuevaLlamada() {
    const r = await enviar('POST', '/api/llamadas', { deviceId: dispositivoId, ...MONTERREY });
    assert.equal(r.status, 201);
    const json = await r.json();
    llamadas.push(json.id);
    return json;
  }

  const transcribir = (llamada, lines, deviceId = dispositivoId) =>
    enviar('POST', `/api/llamadas/${llamada}/transcripcion`, { deviceId, lines });

  async function lineasGuardadas(llamada) {
    const [filas] = await pool.query(
      'SELECT hablante, texto, momento_seg FROM transcripcion WHERE llamada_id = ? ORDER BY id', [llamada]);
    return filas;
  }

  // ── RF12: lo que dice la persona llega como texto al panel del operador ────
  test('guarda las frases en orden y el operador que atiende la llamada las puede leer', async () => {
    const llamada = await nuevaLlamada();

    const r1 = await transcribir(llamada.id, [
      { text: '  Hubo un choque en la avenida Constitución  ', second: 4 },
      { text: 'Hay dos personas lesionadas', second: 9 },
    ]);
    assert.equal(r1.status, 201);
    assert.deepEqual(await r1.json(), { saved: 2 });
    const r2 = await transcribir(llamada.id, [{ text: 'Una no puede mover la pierna', second: 15 }]);
    assert.equal(r2.status, 201);

    const guardadas = await lineasGuardadas(llamada.id);
    assert.deepEqual(guardadas.map((l) => l.texto), [
      'Hubo un choque en la avenida Constitución',   // sin los espacios de las orillas
      'Hay dos personas lesionadas',
      'Una no puede mover la pierna',
    ]);
    assert.deepEqual(guardadas.map((l) => l.momento_seg), [4, 9, 15]);
    assert.ok(guardadas.every((l) => l.hablante === 'solicitante'));

    // El panel lee con el procedimiento transcripcion_listar: solo el operador de la llamada.
    await pool.query(
      `INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol, activo) VALUES (?, ?, ?, 'operador', 1)`,
      [llamada.delegation.id, usuarioOperador, await bcrypt.hash('contrasena-de-prueba', 4)]);
    const [[cuenta]] = await pool.query('SELECT id FROM personal WHERE usuario = ?', [usuarioOperador]);
    operadorId = cuenta.id;
    await pool.query('UPDATE llamada SET operador_id = ? WHERE id = ?', [operadorId, llamada.id]);

    const todas = await llamar(pool, 'CALL transcripcion_listar(?, ?, ?)', [operadorId, llamada.id, 0]);
    assert.equal(todas.length, 3);
    assert.equal(todas[0].texto, 'Hubo un choque en la avenida Constitución');
    // "desde" permite pedir solo lo nuevo, como hace el panel cada pocos segundos.
    const nuevas = await llamar(pool, 'CALL transcripcion_listar(?, ?, ?)', [operadorId, llamada.id, todas[1].id]);
    assert.deepEqual(nuevas.map((l) => l.texto), ['Una no puede mover la pierna']);
  });

  test('rechaza envíos no válidos con 400 y no guarda nada', async () => {
    const llamada = await nuevaLlamada();
    const linea = { text: 'Necesito una ambulancia', second: 3 };
    const invalidos = [
      [],                                                       // sin líneas
      [{ text: '   ', second: 3 }],                             // texto vacío
      [{ text: 'a'.repeat(1001), second: 3 }],                  // texto demasiado largo
      [{ text: 'dos\nrenglones', second: 3 }],                  // caracteres de control
      [{ text: 'Necesito una ambulancia', second: -1 }],        // segundo negativo
      [{ text: 'Necesito una ambulancia', second: 2.5 }],       // segundo con decimales
      Array.from({ length: 21 }, () => linea),                  // más de 20 líneas en un envío
    ];
    for (const lines of invalidos) {
      const r = await transcribir(llamada.id, lines);
      assert.equal(r.status, 400, JSON.stringify(lines).slice(0, 60));
      assert.deepEqual(await r.json(), { error: 'datos no válidos' });
    }
    const sinDispositivo = await enviar('POST', `/api/llamadas/${llamada.id}/transcripcion`, { lines: [linea] });
    assert.equal(sinDispositivo.status, 400);
    const idMalo = await transcribir('no-es-un-id', [linea]);
    assert.equal(idMalo.status, 400);
    assert.equal((await lineasGuardadas(llamada.id)).length, 0);
  });

  test('otro dispositivo no puede escribir en mi llamada', async () => {
    const llamada = await nuevaLlamada();
    const r = await transcribir(llamada.id, [{ text: 'Texto de otro teléfono', second: 1 }], otroDispositivoId);
    assert.equal(r.status, 404);
    assert.equal((await lineasGuardadas(llamada.id)).length, 0);

    const inexistente = await transcribir(randomUUID(), [{ text: 'Llamada que no existe', second: 1 }]);
    assert.equal(inexistente.status, 404);
  });

  test('una llamada que ya terminó no acepta más transcripción', async () => {
    const llamada = await nuevaLlamada();
    assert.equal((await transcribir(llamada.id, [{ text: 'Sigo en la línea', second: 2 }])).status, 201);

    const colgar = await enviar('PATCH', `/api/llamadas/${llamada.id}`, { deviceId: dispositivoId, status: 'finalizada' });
    assert.equal(colgar.status, 204);

    const r = await transcribir(llamada.id, [{ text: 'Esto ya no debe guardarse', second: 30 }]);
    assert.equal(r.status, 404);
    assert.equal((await lineasGuardadas(llamada.id)).length, 1);
  });

  test('si una línea del envío no se puede guardar, no se guarda ninguna', async () => {
    const llamada = await nuevaLlamada();
    // La llamada queda a una línea del tope (2000 por llamada).
    const previas = Array.from({ length: 1999 }, (_, i) => [llamada.id, 'solicitante', `línea ${i + 1}`, i]);
    await pool.query('INSERT INTO transcripcion (llamada_id, hablante, texto, momento_seg) VALUES ?', [previas]);

    const r = await transcribir(llamada.id, [
      { text: 'Esta línea sí cabe', second: 2000 },
      { text: 'Esta ya no cabe', second: 2001 },
    ]);
    assert.equal(r.status, 409);
    assert.equal((await lineasGuardadas(llamada.id)).length, 1999);

    // Una sola línea sí entra, y con ella se llega al tope.
    assert.equal((await transcribir(llamada.id, [{ text: 'Esta línea sí cabe', second: 2000 }])).status, 201);
    assert.equal((await transcribir(llamada.id, [{ text: 'Una más', second: 2002 }])).status, 409);
  });
});
