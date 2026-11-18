// Pruebas de los pagos con Stripe (pedidos y webhook).
//
// Usan un MySQL LOCAL de verdad y un Stripe FALSO (no hacen ninguna llamada a internet).
// La verificación de la firma del webhook sí es la real: se firma con el mismo código de Stripe.
// Se niegan a correr contra otra base que no sea local, porque crean y borran datos.
//
// Cómo correrlas:  npm run probar:pagos   (necesitas backend/.env.local, ver .env.local.example)

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import Stripe from 'stripe';
import { crearPool } from '../src/db.js';
import { manejadorDeErrores } from '../src/errores.js';
import { rutasPedidos } from '../src/rutas/pedidos.js';
import { rutaWebhookStripe } from '../src/rutas/stripeWebhook.js';

const baseLocal = ['127.0.0.1', 'localhost'].includes(process.env.DB_HOST);
const SECRETO = 'whsec_prueba_local_1234567890';
const real = new Stripe('sk_test_llave_falsa_para_pruebas');

const direccion = {
  nombre: 'Ana Prueba', telefono: '8112345678', calle_numero: 'Av. Juárez 100',
  colonia: 'Centro', ciudad: 'Monterrey', entidad: 'Nuevo León', codigo_postal: '64000',
};

describe('Pagos con Stripe', { skip: baseLocal ? false : 'DB_HOST debe ser 127.0.0.1 o localhost (ver .env.local.example)' }, () => {
  let pool, servidor, url;
  let dispositivoId, otroDispositivoId, productoId, productoBaratoId, productoInactivoId;
  let contador = 0;
  let fallaStripe = false;
  let fallaCancelacion = false;
  let cobrosCreados = [];
  let cobrosCancelados = [];

  // Stripe falso: guarda lo que se le pide y puede fallar a propósito. Los webhooks son los reales.
  const stripeFalso = {
    webhooks: real.webhooks,
    paymentIntents: {
      async create(parametros, opciones) {
        if (fallaStripe) throw Object.assign(new Error('simulado'), { type: 'StripeConnectionError' });
        const id = `pi_prueba_${Date.now()}_${++contador}`;
        cobrosCreados.push({ id, parametros, opciones });
        return { id, client_secret: `${id}_secret_abc` };
      },
      async cancel(id) {
        if (fallaCancelacion) throw Object.assign(new Error('simulado'), { code: 'payment_intent_unexpected_state' });
        cobrosCancelados.push(id);
        return { id, status: 'canceled' };
      },
    },
  };

  const config = {
    stripe: stripeFalso, publishableKey: 'pk_test_publicable_de_prueba', webhookSecret: SECRETO,
    envioMXN: 99, limiteCrearPorMinuto: 1000,
  };

  before(async () => {
    pool = crearPool();
    const app = express();
    app.use('/stripe/webhook', rutaWebhookStripe(pool, config));
    app.use(express.json({ limit: '16kb' }));
    app.use('/api/pedidos', rutasPedidos(pool, config));
    app.use(manejadorDeErrores);
    servidor = await new Promise((listo) => { const s = app.listen(0, '127.0.0.1', () => listo(s)); });
    url = `http://127.0.0.1:${servidor.address().port}`;

    dispositivoId = randomUUID();
    otroDispositivoId = randomUUID();
    await pool.query('INSERT INTO dispositivo (id) VALUES (?), (?)', [dispositivoId, otroDispositivoId]);
    const sufijo = randomUUID().slice(0, 8);
    const alta = async (nombre, precio, activo) => {
      const [r] = await pool.query(
        'INSERT INTO producto (nombre, precio_mxn, causa, enlace_compra, activo) VALUES (?, ?, ?, ?, ?)',
        [`${nombre} ${sufijo}`, precio, 'Causa de prueba', 'https://tienda.ejemplo.invalid/x', activo]);
      return r.insertId;
    };
    productoId = await alta('Producto de prueba', 150, 1);
    productoBaratoId = await alta('Producto barato de prueba', 5, 1);
    productoInactivoId = await alta('Producto apagado de prueba', 150, 0);
  });

  after(async () => {
    if (servidor) await new Promise((listo) => servidor.close(listo));
    if (pool) {
      await pool.query('DELETE FROM pedido WHERE dispositivo_id IN (?, ?)', [dispositivoId, otroDispositivoId]);
      await pool.query("DELETE FROM evento_stripe WHERE id LIKE 'evt_prueba_%'");
      await pool.query('DELETE FROM producto WHERE id IN (?, ?, ?)', [productoId, productoBaratoId, productoInactivoId]);
      await pool.query('DELETE FROM dispositivo WHERE id IN (?, ?)', [dispositivoId, otroDispositivoId]);
      await pool.end();
    }
  });

  // ── ayudas ────────────────────────────────────────────────────────────────
  const pedir = (metodo, ruta, { cuerpo, dispositivo = dispositivoId, cabeceras = {} } = {}) =>
    fetch(url + ruta, {
      method: metodo,
      headers: {
        ...(cuerpo ? { 'Content-Type': 'application/json' } : {}),
        ...(dispositivo ? { 'X-Dispositivo-Id': dispositivo } : {}),
        ...cabeceras,
      },
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });

  async function crearPedido(extra = {}, opciones = {}) {
    const r = await pedir('POST', '/api/pedidos', {
      cuerpo: { producto_id: productoId, cantidad: 2, ...direccion, ...extra }, ...opciones,
    });
    return { r, json: await r.json() };
  }

  const filaPedido = async (id) => (await pool.query('SELECT * FROM pedido WHERE id = ?', [id]))[0][0];

  function enviarEvento(evento, { secreto = SECRETO, firmar = true } = {}) {
    const payload = JSON.stringify(evento);
    const cabeceras = { 'Content-Type': 'application/json' };
    if (firmar) cabeceras['Stripe-Signature'] = real.webhooks.generateTestHeaderString({ payload, secret: secreto });
    return fetch(`${url}/stripe/webhook`, { method: 'POST', headers: cabeceras, body: payload });
  }

  const eventoPago = (cobroId, monto, tipo = 'payment_intent.succeeded', moneda = 'mxn') => ({
    id: `evt_prueba_${randomUUID()}`, object: 'event', type: tipo,
    data: { object: { id: cobroId, object: 'payment_intent', amount: monto, currency: moneda } },
  });

  // ── crear pedido ──────────────────────────────────────────────────────────
  test('crea el pedido pendiente y el cobro en Stripe con el precio de la base', async () => {
    cobrosCreados = [];
    const { r, json } = await crearPedido();
    assert.equal(r.status, 201);
    assert.equal(json.total_mxn, 399);          // 150 x 2 + 99 de envío
    assert.equal(json.envio_mxn, 99);
    assert.match(json.folio, /^PC-\d{6,}$/);
    assert.equal(json.publishable_key, 'pk_test_publicable_de_prueba');
    assert.match(json.client_secret, /_secret_/);

    assert.equal(cobrosCreados.length, 1);
    const { parametros, opciones } = cobrosCreados[0];
    assert.equal(parametros.amount, 39900);
    assert.equal(parametros.currency, 'mxn');
    // Stripe ya no acepta payment_method_types: los métodos se eligen en el Dashboard. Nunca se ofrece
    // un método que saque a la persona de la app (allow_redirects: 'never').
    assert.deepEqual(parametros.automatic_payment_methods, { enabled: true, allow_redirects: 'never' });
    assert.equal(parametros.payment_method_types, undefined);
    assert.equal(parametros.metadata.pedido_id, json.id);
    assert.equal(parametros.metadata.folio, json.folio);
    assert.equal(opciones.idempotencyKey, `pedido-${json.id}`);

    const fila = await filaPedido(json.id);
    assert.equal(fila.estado, 'pendiente');
    assert.equal(fila.stripe_payment_intent_id, cobrosCreados[0].id);
    assert.equal(fila.dispositivo_id, dispositivoId);
    assert.equal(Number(fila.total_mxn), 399);
    assert.equal(fila.codigo_postal, '64000');
  });

  test('ignora un precio o total que mande la app', async () => {
    cobrosCreados = [];
    const { r, json } = await crearPedido({ precio_mxn: 1, total_mxn: 1, envio_mxn: 0, estado: 'pagado' });
    assert.equal(r.status, 201);
    assert.equal(json.total_mxn, 399);
    assert.equal(cobrosCreados[0].parametros.amount, 39900);
    assert.equal((await filaPedido(json.id)).estado, 'pendiente');
  });

  test('rechaza datos no válidos con un mensaje claro', async () => {
    const casos = [
      [{ cantidad: 0 }, 'la cantidad mínima es 1'],
      [{ cantidad: 11 }, 'la cantidad máxima es 10'],
      [{ cantidad: 1.5 }, 'la cantidad no es válida'],
      [{ cantidad: '2' }, 'la cantidad no es válida'],
      [{ codigo_postal: '6400' }, 'el código postal debe tener 5 dígitos'],
      [{ telefono: 'abc' }, 'el teléfono no es válido'],
      [{ nombre: 'Al' }, 'el nombre es muy corto'],
      [{ calle_numero: 'Calle\nfalsa 123' }, 'la calle y el número no es válido'],
      [{ producto_id: 'x' }, 'el producto no es válido'],
    ];
    for (const [extra, mensaje] of casos) {
      const { r, json } = await crearPedido(extra);
      assert.equal(r.status, 400, JSON.stringify(extra));
      assert.equal(json.error, mensaje);
    }
    const { r, json } = await crearPedido({ colonia: undefined });
    assert.equal(r.status, 400);
    assert.equal(json.error, 'falta la colonia');
  });

  test('producto inexistente o desactivado: 404', async () => {
    for (const id of [999999, productoInactivoId]) {
      const { r, json } = await crearPedido({ producto_id: id });
      assert.equal(r.status, 404);
      assert.equal(json.error, 'el producto no existe');
    }
  });

  test('exige un dispositivo conocido', async () => {
    let { r } = await crearPedido({}, { dispositivo: null });
    assert.equal(r.status, 401);
    ({ r } = await crearPedido({}, { dispositivo: 'no-es-uuid' }));
    assert.equal(r.status, 401);
    let json;
    ({ r, json } = await crearPedido({}, { dispositivo: randomUUID() }));
    assert.equal(r.status, 400);
    assert.equal(json.error, 'dispositivo no registrado'); // la app lo usa para registrarse otra vez
  });

  test('si Stripe falla, el pedido se cancela y el usuario ve un mensaje genérico', async () => {
    fallaStripe = true;
    try {
      const { r, json } = await crearPedido();
      assert.equal(r.status, 502);
      assert.equal(json.error, 'No pudimos iniciar el pago. Intenta de nuevo.');
      const [filas] = await pool.query(
        "SELECT estado FROM pedido WHERE dispositivo_id = ? AND stripe_payment_intent_id IS NULL", [dispositivoId]);
      assert.ok(filas.length >= 1);
      assert.ok(filas.every((f) => f.estado === 'cancelado'));
    } finally { fallaStripe = false; }
  });

  test('no cobra menos de $10', async () => {
    const baratoSinEnvio = { ...config, envioMXN: 0 };
    const app = express();
    app.use(express.json());
    app.use('/api/pedidos', rutasPedidos(pool, baratoSinEnvio));
    app.use(manejadorDeErrores);
    const s = await new Promise((listo) => { const x = app.listen(0, '127.0.0.1', () => listo(x)); });
    try {
      const r = await fetch(`http://127.0.0.1:${s.address().port}/api/pedidos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Dispositivo-Id': dispositivoId },
        body: JSON.stringify({ producto_id: productoBaratoId, cantidad: 1, ...direccion }),
      });
      assert.equal(r.status, 400);
      assert.match((await r.json()).error, /mínimo/);
    } finally { await new Promise((listo) => s.close(listo)); }
  });

  test('con los pagos apagados responde 503', async () => {
    const app = express();
    app.use(express.json());
    app.use('/api/pedidos', rutasPedidos(pool, { ...config, stripe: null }));
    app.use(manejadorDeErrores);
    const s = await new Promise((listo) => { const x = app.listen(0, '127.0.0.1', () => listo(x)); });
    try {
      const r = await fetch(`http://127.0.0.1:${s.address().port}/api/pedidos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Dispositivo-Id': dispositivoId },
        body: JSON.stringify({ producto_id: productoId, cantidad: 1, ...direccion }),
      });
      assert.equal(r.status, 503);
    } finally { await new Promise((listo) => s.close(listo)); }
  });

  test('condiciones: la app puede ver el envío antes de pagar (sin dispositivo y sin datos personales)', async () => {
    let r = await pedir('GET', '/api/pedidos/condiciones', { dispositivo: null });
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { disponible: true, envio_mxn: 99, cantidad_maxima: 10, total_minimo_mxn: 10 });

    // Con los pagos apagados avisa que no están disponibles (la app esconde el botón de pagar).
    const app = express();
    app.use('/api/pedidos', rutasPedidos(pool, { ...config, stripe: null }));
    app.use(manejadorDeErrores);
    const s = await new Promise((listo) => { const x = app.listen(0, '127.0.0.1', () => listo(x)); });
    try {
      r = await fetch(`http://127.0.0.1:${s.address().port}/api/pedidos/condiciones`);
      assert.equal(r.status, 200);
      assert.equal((await r.json()).disponible, false);
    } finally { await new Promise((listo) => s.close(listo)); }
  });

  // ── consultar y cancelar ──────────────────────────────────────────────────
  test('un pedido solo lo ve el dispositivo que lo creó', async () => {
    const { json } = await crearPedido();
    let r = await pedir('GET', `/api/pedidos/${json.id}`);
    assert.equal(r.status, 200);
    const visto = await r.json();
    assert.equal(visto.estado, 'pendiente');
    assert.equal(visto.folio, json.folio);
    assert.equal(visto.total_mxn, 399);
    assert.equal('nombre' in visto || 'calle_numero' in visto || 'telefono' in visto, false); // sin datos personales

    r = await pedir('GET', `/api/pedidos/${json.id}`, { dispositivo: otroDispositivoId });
    assert.equal(r.status, 404);
    r = await pedir('GET', '/api/pedidos/no-es-uuid');
    assert.equal(r.status, 404);
    r = await pedir('GET', `/api/pedidos/${randomUUID()}`);
    assert.equal(r.status, 404);
  });

  test('cancelar: pendiente se cancela (y se cancela el cobro); repetirlo no falla', async () => {
    cobrosCancelados = [];
    const { json } = await crearPedido();
    let r = await pedir('POST', `/api/pedidos/${json.id}/cancelar`);
    assert.equal(r.status, 204);
    assert.equal((await filaPedido(json.id)).estado, 'cancelado');
    assert.equal(cobrosCancelados.length, 1);
    r = await pedir('POST', `/api/pedidos/${json.id}/cancelar`);
    assert.equal(r.status, 204);
    r = await pedir('POST', `/api/pedidos/${json.id}/cancelar`, { dispositivo: otroDispositivoId });
    assert.equal(r.status, 404);
  });

  test('cancelar un pedido ya pagado: 409; si Stripe no cancela, sigue pendiente', async () => {
    const pagado = (await crearPedido()).json;
    await pool.query("UPDATE pedido SET estado = 'pagado', pagado_en = UTC_TIMESTAMP(3) WHERE id = ?", [pagado.id]);
    let r = await pedir('POST', `/api/pedidos/${pagado.id}/cancelar`);
    assert.equal(r.status, 409);

    const pendiente = (await crearPedido()).json;
    fallaCancelacion = true;
    try {
      r = await pedir('POST', `/api/pedidos/${pendiente.id}/cancelar`);
      assert.equal(r.status, 409);
      assert.equal((await filaPedido(pendiente.id)).estado, 'pendiente');
    } finally { fallaCancelacion = false; }
  });

  // ── webhook ───────────────────────────────────────────────────────────────
  test('webhook: sin firma o con firma falsa, 400 y no cambia nada', async () => {
    const { json } = await crearPedido();
    const cobroId = (await filaPedido(json.id)).stripe_payment_intent_id;
    let r = await enviarEvento(eventoPago(cobroId, 39900), { firmar: false });
    assert.equal(r.status, 400);
    r = await enviarEvento(eventoPago(cobroId, 39900), { secreto: 'whsec_otro_secreto_distinto' });
    assert.equal(r.status, 400);
    assert.equal((await filaPedido(json.id)).estado, 'pendiente');
  });

  test('webhook: pago exitoso marca el pedido como pagado, y repetir el aviso no hace nada', async () => {
    const { json } = await crearPedido();
    const cobroId = (await filaPedido(json.id)).stripe_payment_intent_id;
    const evento = eventoPago(cobroId, 39900);
    let r = await enviarEvento(evento);
    assert.equal(r.status, 200);
    let fila = await filaPedido(json.id);
    assert.equal(fila.estado, 'pagado');
    assert.ok(fila.pagado_en);

    const primeraFecha = fila.pagado_en.getTime();
    r = await enviarEvento(evento);                       // Stripe reenvía el mismo aviso
    assert.equal(r.status, 200);
    assert.equal((await r.json()).repetido, true);
    fila = await filaPedido(json.id);
    assert.equal(fila.pagado_en.getTime(), primeraFecha);
    const [[{ cuantos }]] = await pool.query('SELECT COUNT(*) AS cuantos FROM evento_stripe WHERE id = ?', [evento.id]);
    assert.equal(cuantos, 1);

    r = await pedir('GET', `/api/pedidos/${json.id}`);   // y la app lo ve pagado
    assert.equal((await r.json()).estado, 'pagado');
  });

  test('webhook: un monto distinto al del pedido NO lo marca como pagado', async () => {
    const { json } = await crearPedido();
    const cobroId = (await filaPedido(json.id)).stripe_payment_intent_id;
    let r = await enviarEvento(eventoPago(cobroId, 100));
    assert.equal(r.status, 200);
    assert.equal((await filaPedido(json.id)).estado, 'pendiente');
    r = await enviarEvento(eventoPago(cobroId, 39900, 'payment_intent.succeeded', 'usd'));
    assert.equal(r.status, 200);
    assert.equal((await filaPedido(json.id)).estado, 'pendiente');
  });

  test('webhook: cobro desconocido, cancelación y otros tipos de evento', async () => {
    let r = await enviarEvento(eventoPago('pi_que_no_existe', 39900));
    assert.equal(r.status, 200);

    const { json } = await crearPedido();
    const cobroId = (await filaPedido(json.id)).stripe_payment_intent_id;
    r = await enviarEvento(eventoPago(cobroId, 39900, 'payment_intent.canceled'));
    assert.equal(r.status, 200);
    assert.equal((await filaPedido(json.id)).estado, 'cancelado');

    r = await enviarEvento({ id: `evt_prueba_${randomUUID()}`, object: 'event', type: 'charge.refunded', data: { object: {} } });
    assert.equal(r.status, 200);
  });

  test('webhook: si la base falla, responde 500 para que Stripe reintente (y no anota el evento)', async () => {
    const { json } = await crearPedido();
    const cobroId = (await filaPedido(json.id)).stripe_payment_intent_id;
    const evento = eventoPago(cobroId, 39900);
    // Pool que falla al buscar el pedido, después de anotar el evento (dentro de la transacción).
    const conexionReal = await pool.getConnection();
    const original = conexionReal.query.bind(conexionReal);
    const poolRoto = {
      getConnection: async () => ({
        beginTransaction: () => conexionReal.beginTransaction(),
        commit: () => conexionReal.commit(),
        rollback: () => conexionReal.rollback(),
        release: () => {},
        query: (sql, ...resto) => (/FROM pedido/.test(sql) ? Promise.reject(new Error('simulado')) : original(sql, ...resto)),
      }),
    };
    const app = express();
    app.use('/stripe/webhook', rutaWebhookStripe(poolRoto, config));
    const s = await new Promise((listo) => { const x = app.listen(0, '127.0.0.1', () => listo(x)); });
    try {
      const payload = JSON.stringify(evento);
      const r = await fetch(`http://127.0.0.1:${s.address().port}/stripe/webhook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Stripe-Signature': real.webhooks.generateTestHeaderString({ payload, secret: SECRETO }) },
        body: payload,
      });
      assert.equal(r.status, 500);
    } finally {
      await new Promise((listo) => s.close(listo));
      conexionReal.release();
    }
    const [[{ cuantos }]] = await pool.query('SELECT COUNT(*) AS cuantos FROM evento_stripe WHERE id = ?', [evento.id]);
    assert.equal(cuantos, 0);                              // el rollback lo dejó sin anotar: el reintento funcionará
    assert.equal((await filaPedido(json.id)).estado, 'pendiente');
    const reintento = await enviarEvento(evento);          // el reintento de Stripe sí lo procesa
    assert.equal(reintento.status, 200);
    assert.equal((await filaPedido(json.id)).estado, 'pagado');
  });
});
