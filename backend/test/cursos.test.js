// Pruebas de Capacitación: cursos e inscripciones (HU14, src/rutas/cursos.js).
//
// Usan un MySQL LOCAL de verdad. Se niegan a correr contra otra base que no sea local,
// porque crean y borran cursos, inscripciones y dispositivos de prueba.
//
// Cómo correrlas:  npm run probar:cursos   (necesitas backend/.env.local, ver .env.local.example)

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { crearPool } from '../src/db.js';
import { manejadorDeErrores } from '../src/errores.js';
import { folioDe, rutasCursos } from '../src/rutas/cursos.js';

const baseLocal = ['127.0.0.1', 'localhost'].includes(process.env.DB_HOST);
const persona = { nombre: 'Ana Prueba', telefono: '8112345678' };

describe('Capacitación: cursos e inscripciones', { skip: baseLocal ? false : 'DB_HOST debe ser 127.0.0.1 o localhost (ver .env.local.example)' }, () => {
  let pool, servidor, url;
  let dispositivoId, otroDispositivoId, delegacionId;
  let cursoId, cursoUnLugarId, cursoPasadoId, cursoApagadoId;
  const sufijo = randomUUID().slice(0, 8);

  before(async () => {
    pool = crearPool();
    const app = express();
    app.use(express.json({ limit: '16kb' }));
    app.use('/api/cursos', rutasCursos(pool, { limiteInscribirPorMinuto: 1000 }));
    app.use(manejadorDeErrores);
    servidor = await new Promise((listo) => { const s = app.listen(0, '127.0.0.1', () => listo(s)); });
    url = `http://127.0.0.1:${servidor.address().port}`;

    dispositivoId = randomUUID();
    otroDispositivoId = randomUUID();
    await pool.query('INSERT INTO dispositivo (id) VALUES (?), (?)', [dispositivoId, otroDispositivoId]);
    const [[delegacion]] = await pool.query('SELECT id FROM delegacion WHERE activa = 1 ORDER BY id LIMIT 1');
    delegacionId = delegacion.id;

    const alta = async (titulo, dias, cupo, activo = 1) => {
      const [r] = await pool.query(
        `INSERT INTO curso (delegacion_id, titulo, descripcion, inicio, cupo, activo)
         VALUES (?, ?, 'Curso creado por las pruebas', UTC_TIMESTAMP(3) + INTERVAL ? DAY, ?, ?)`,
        [delegacionId, `${titulo} ${sufijo}`, dias, cupo, activo]);
      return r.insertId;
    };
    cursoId = await alta('Curso con lugares', 10, 20);
    cursoUnLugarId = await alta('Curso con un lugar', 11, 1);
    cursoPasadoId = await alta('Curso que ya pasó', -2, 20);
    cursoApagadoId = await alta('Curso desactivado', 12, 20, 0);
  });

  after(async () => {
    if (servidor) await new Promise((listo) => servidor.close(listo));
    if (pool) {
      const cursos = [cursoId, cursoUnLugarId, cursoPasadoId, cursoApagadoId].filter(Boolean);
      if (cursos.length) {
        await pool.query('DELETE FROM inscripcion_curso WHERE curso_id IN (?)', [cursos]);
        await pool.query('DELETE FROM curso WHERE id IN (?)', [cursos]);
      }
      await pool.query('DELETE FROM dispositivo WHERE id IN (?, ?)', [dispositivoId, otroDispositivoId]);
      await pool.end();
    }
  });

  // ── ayudas ────────────────────────────────────────────────────────────────
  const pedir = (metodo, ruta, { cuerpo, dispositivo = dispositivoId } = {}) =>
    fetch(url + ruta, {
      method: metodo,
      headers: {
        ...(cuerpo ? { 'Content-Type': 'application/json' } : {}),
        ...(dispositivo ? { 'X-Dispositivo-Id': dispositivo } : {}),
      },
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });

  async function inscribir(curso, cuerpo = persona, opciones = {}) {
    const r = await pedir('POST', `/api/cursos/${curso}/inscripciones`, { cuerpo, ...opciones });
    return { r, json: await r.json() };
  }

  async function cursoEnLista(id) {
    const r = await pedir('GET', '/api/cursos', { dispositivo: null });
    assert.equal(r.status, 200);
    return (await r.json()).cursos.find((c) => c.id === id);
  }

  // ── CA1: los cursos aparecen con fecha y lugares disponibles ───────────────
  test('la lista trae fecha, sede, cupo e inscritos, sin datos personales y sin pedir dispositivo', async () => {
    const curso = await cursoEnLista(cursoId);
    assert.ok(curso, 'el curso activo y futuro debe aparecer');
    assert.equal(curso.cupo, 20);
    assert.equal(curso.inscritos, 0);
    assert.ok(!Number.isNaN(Date.parse(curso.inicio)));
    assert.equal(typeof curso.sede, 'string');
    assert.deepEqual(Object.keys(curso).sort(), ['cupo', 'descripcion', 'id', 'inicio', 'inscritos', 'sede', 'titulo']);
  });

  test('no aparecen los cursos que ya pasaron ni los desactivados, y la lista va por fecha', async () => {
    assert.equal(await cursoEnLista(cursoPasadoId), undefined);
    assert.equal(await cursoEnLista(cursoApagadoId), undefined);
    const r = await pedir('GET', '/api/cursos', { dispositivo: null });
    const fechas = (await r.json()).cursos.map((c) => Date.parse(c.inicio));
    assert.deepEqual(fechas, [...fechas].sort((a, b) => a - b));
  });

  // ── CA2: con cupo, al inscribirme recibo una confirmación ──────────────────
  test('inscribirse devuelve el folio, baja los lugares y queda en mis inscripciones', async () => {
    const { r, json } = await inscribir(cursoId);
    assert.equal(r.status, 201);
    assert.match(json.folio, /^CAP-[0-9A-F]{6}$/);
    assert.equal(json.curso_id, cursoId);
    assert.equal(json.lugares_disponibles, 19);
    assert.equal((await cursoEnLista(cursoId)).inscritos, 1);

    const mias = await (await pedir('GET', '/api/cursos/inscripciones')).json();
    const mia = mias.inscripciones.find((i) => i.curso_id === cursoId);
    assert.equal(mia.folio, json.folio);

    const [[fila]] = await pool.query(
      'SELECT id, nombre, telefono, dispositivo_id FROM inscripcion_curso WHERE curso_id = ?', [cursoId]);
    assert.equal(folioDe(fila.id), json.folio);
    assert.equal(fila.nombre, persona.nombre);
    assert.equal(fila.dispositivo_id, dispositivoId);
  });

  test('la misma persona no puede inscribirse dos veces al mismo curso', async () => {
    const { r, json } = await inscribir(cursoId);
    assert.equal(r.status, 409);
    assert.equal(json.error, 'Ya estás inscrito en este curso');
    assert.equal((await cursoEnLista(cursoId)).inscritos, 1);
  });

  test('una inscripción solo la ve el dispositivo que la hizo', async () => {
    const otras = await (await pedir('GET', '/api/cursos/inscripciones', { dispositivo: otroDispositivoId })).json();
    assert.deepEqual(otras.inscripciones, []);
  });

  // ── CA3: si el curso está lleno no puedo inscribirme ───────────────────────
  test('el último lugar se da una sola vez: el siguiente recibe 409 y no se pasa del cupo', async () => {
    const primero = await inscribir(cursoUnLugarId);
    assert.equal(primero.r.status, 201);
    assert.equal(primero.json.lugares_disponibles, 0);

    const segundo = await inscribir(cursoUnLugarId, { nombre: 'Luis Prueba', telefono: '8187654321' },
      { dispositivo: otroDispositivoId });
    assert.equal(segundo.r.status, 409);
    assert.equal(segundo.json.error, 'Este curso ya no tiene lugares');
    const [[{ total }]] = await pool.query(
      'SELECT COUNT(*) AS total FROM inscripcion_curso WHERE curso_id = ?', [cursoUnLugarId]);
    assert.equal(total, 1);
  });

  test('dos inscripciones al mismo tiempo por el último lugar: solo entra una', async () => {
    const [r] = await pool.query(
      `INSERT INTO curso (delegacion_id, titulo, inicio, cupo) VALUES (?, ?, UTC_TIMESTAMP(3) + INTERVAL 13 DAY, 1)`,
      [delegacionId, `Curso simultáneo ${sufijo}`]);
    const simultaneo = r.insertId;
    try {
      const respuestas = await Promise.all([
        inscribir(simultaneo, { nombre: 'Persona Uno', telefono: '8110000001' }),
        inscribir(simultaneo, { nombre: 'Persona Dos', telefono: '8110000002' }, { dispositivo: otroDispositivoId }),
      ]);
      assert.deepEqual(respuestas.map((x) => x.r.status).sort(), [201, 409]);
    } finally {
      await pool.query('DELETE FROM inscripcion_curso WHERE curso_id = ?', [simultaneo]);
      await pool.query('DELETE FROM curso WHERE id = ?', [simultaneo]);
    }
  });

  // ── datos no válidos y cursos que no se pueden tomar ───────────────────────
  test('rechaza datos incompletos con un mensaje claro y no inscribe', async () => {
    const casos = [
      [{ nombre: 'Al', telefono: '8112345678' }, 'escribe tu nombre completo'],
      [{ nombre: 'Ana Prueba', telefono: '81123' }, 'el teléfono no es válido'],
      [{ telefono: '8112345678' }, 'falta el nombre'],
      [{ nombre: 'Ana Prueba' }, 'falta el teléfono'],
    ];
    for (const [cuerpo, mensaje] of casos) {
      const { r, json } = await inscribir(cursoId, cuerpo, { dispositivo: otroDispositivoId });
      assert.equal(r.status, 400);
      assert.equal(json.error, mensaje);
    }
    assert.equal((await cursoEnLista(cursoId)).inscritos, 1);
  });

  test('curso inexistente, pasado o desactivado: 404', async () => {
    for (const id of [999999999, cursoPasadoId, cursoApagadoId, 'abc']) {
      const { r, json } = await inscribir(id, { nombre: 'Otra Persona', telefono: '8119999999' });
      assert.equal(r.status, 404);
      assert.equal(json.error, 'el curso no existe');
    }
  });

  test('exige un dispositivo conocido', async () => {
    const sinHeader = await inscribir(cursoId, persona, { dispositivo: null });
    assert.equal(sinHeader.r.status, 401);
    const desconocido = await inscribir(cursoId, persona, { dispositivo: randomUUID() });
    assert.equal(desconocido.r.status, 400);
    assert.equal(desconocido.json.error, 'dispositivo no registrado'); // la app se registra y reintenta
    const lista = await pedir('GET', '/api/cursos/inscripciones', { dispositivo: null });
    assert.equal(lista.status, 401);
  });
});
