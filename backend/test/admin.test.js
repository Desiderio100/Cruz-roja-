// Pruebas del sitio de administración de pedidos (inicio de sesión, lista, envío y reembolsos).
//
// Usan un MySQL LOCAL de verdad y un Stripe FALSO (no hacen ninguna llamada a internet).
// La verificación de la firma del webhook sí es la real. Se niegan a correr contra otra base que
// no sea local, porque crean y borran datos.
//
// Cómo correrlas:  npm run probar:admin   (necesitas backend/.env.local con 01, 02, 08, 09 y 10 corridos)
//
// Ojo: la bitácora de la base es de SOLO AGREGAR (nadie puede borrarla, a propósito), así que cada
// corrida deja unas filas ahí y 4 cuentas "prueba.*.pagos" en la tabla personal. Es normal.

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import bcrypt from 'bcryptjs';
import Stripe from 'stripe';
import { crearPool } from '../src/db.js';
import { manejadorDeErrores } from '../src/errores.js';
import { rutasAdmin } from '../src/admin/rutas.js';
import { direccionPanelPersonal, firmarSesion, leerSesion, ponerCookieSesion } from '../src/admin/sesion.js';
import { rutaWebhookStripe } from '../src/rutas/stripeWebhook.js';

const baseLocal = ['127.0.0.1', 'localhost'].includes(process.env.DB_HOST);
const SECRETO_WEBHOOK = 'whsec_prueba_local_1234567890';
const real = new Stripe('sk_test_llave_falsa_para_pruebas');
const CONTRASENA = 'una-contrasena-de-prueba-123';

const config = {
  activo: true, secreto: 'secreto-de-prueba-'.repeat(3), duracionMs: 8 * 3600_000,
  cookieSegura: false, limiteLoginPorQuinceMin: 10_000,
};

const CUENTAS = {
  admin: { usuario: 'prueba.admin.pagos', rol: 'administrativo', activo: 1 },
  operador: { usuario: 'prueba.operador.pagos', rol: 'operador', activo: 1 },
  baja: { usuario: 'prueba.baja.pagos', rol: 'operador', activo: 0 },
  bloqueo: { usuario: 'prueba.bloqueo.pagos', rol: 'operador', activo: 1 },
};

describe('Sitio de administración', { skip: baseLocal ? false : 'DB_HOST debe ser 127.0.0.1 o localhost (ver .env.local.example)' }, () => {
  let pool, servidor, url, servidorSinStripe, urlSinStripe;
  let dispositivoId, productoId, sufijo;
  const ids = {};
  let contador = 0;
  let refundsCreados = [];
  let fallaRefund = null;
  let estadoRefund = 'succeeded';
  let alCrearRefund = null;

  const stripeFalso = {
    webhooks: real.webhooks,
    refunds: {
      async create(parametros, opciones) {
        if (alCrearRefund) await alCrearRefund(parametros);
        if (fallaRefund) throw Object.assign(new Error('simulado'), fallaRefund);
        const id = `re_prueba_${Date.now()}_${++contador}`;
        refundsCreados.push({ id, parametros, opciones });
        return { id, status: estadoRefund };
      },
      async list() { return { data: [{ id: `re_ya_hecho_${Date.now()}_${++contador}`, status: 'succeeded' }] }; },
    },
  };
  const pagos = { stripe: stripeFalso, modo: 'prueba', webhookSecret: SECRETO_WEBHOOK, publishableKey: 'pk_test_x', envioMXN: 99 };

  async function levantar(app) {
    const s = await new Promise((listo) => { const x = app.listen(0, '127.0.0.1', () => listo(x)); });
    return { s, u: `http://127.0.0.1:${s.address().port}` };
  }

  before(async () => {
    pool = crearPool();

    let app = express();
    app.use('/stripe/webhook', rutaWebhookStripe(pool, pagos));
    app.use(express.json({ limit: '16kb' }));
    app.use('/admin/api', rutasAdmin(pool, pagos, config));
    app.use(manejadorDeErrores);
    ({ s: servidor, u: url } = await levantar(app));

    // Segundo servidor: pagos apagados (sin Stripe).
    app = express();
    app.use(express.json({ limit: '16kb' }));
    app.use('/admin/api', rutasAdmin(pool, { ...pagos, stripe: null, modo: 'apagado' }, config));
    app.use(manejadorDeErrores);
    ({ s: servidorSinStripe, u: urlSinStripe } = await levantar(app));

    // Cuentas de prueba (fijas: la bitácora no deja borrarlas). Se restablecen en cada corrida.
    const [[{ id: delegacionId }]] = await pool.query('SELECT id FROM delegacion ORDER BY id LIMIT 1');
    const hash = await bcrypt.hash(CONTRASENA, 4);
    for (const [clave, c] of Object.entries(CUENTAS)) {
      await pool.query(
        `INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol, activo)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE hash_contrasena = VALUES(hash_contrasena), rol = VALUES(rol),
                                 activo = VALUES(activo), intentos_fallidos = 0, bloqueado_hasta = NULL`,
        [delegacionId, c.usuario, hash, c.rol, c.activo]);
      const [[fila]] = await pool.query('SELECT id FROM personal WHERE usuario = ?', [c.usuario]);
      ids[clave] = fila.id;
    }

    dispositivoId = randomUUID();
    sufijo = randomUUID().slice(0, 8);
    await pool.query('INSERT INTO dispositivo (id) VALUES (?)', [dispositivoId]);
    const [r] = await pool.query(
      'INSERT INTO producto (nombre, precio_mxn, causa, enlace_compra, activo) VALUES (?, 150, ?, ?, 1)',
      [`Producto admin ${sufijo}`, 'Causa de prueba', 'https://tienda.ejemplo.invalid/x']);
    productoId = r.insertId;
  });

  after(async () => {
    for (const s of [servidor, servidorSinStripe]) if (s) await new Promise((listo) => s.close(listo));
    if (pool) {
      await pool.query('DELETE FROM pedido WHERE dispositivo_id = ?', [dispositivoId]);
      await pool.query("DELETE FROM evento_stripe WHERE id LIKE 'evt_prueba_%'");
      await pool.query('DELETE FROM producto WHERE id = ?', [productoId]);
      await pool.query('DELETE FROM dispositivo WHERE id = ?', [dispositivoId]);
      await pool.query('UPDATE personal SET intentos_fallidos = 0, bloqueado_hasta = NULL WHERE usuario LIKE ?', ['prueba.%.pagos']);
      await pool.end();
    }
  });

  // ── ayudas ────────────────────────────────────────────────────────────────
  async function entrar(usuario, contrasena = CONTRASENA, base = url) {
    const r = await fetch(`${base}/admin/api/sesion`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ usuario, contrasena }),
    });
    const cookie = (r.headers.getSetCookie?.() ?? [])[0]?.split(';')[0] ?? null;
    return { r, cookie, json: await r.json().catch(() => ({})) };
  }

  const api = (cookie, metodo, ruta, cuerpo, { base = url, cabeceras = {} } = {}) =>
    fetch(`${base}/admin/api${ruta}`, {
      method: metodo,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(cuerpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...cabeceras,
      },
      body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined,
    });

  let cookieAdmin, cookieOperador;
  async function sesiones() {
    cookieAdmin ??= (await entrar(CUENTAS.admin.usuario)).cookie;
    cookieOperador ??= (await entrar(CUENTAS.operador.usuario)).cookie;
  }

  async function sembrar({ estado = 'pagado', nombre = `Cliente Admin ${sufijo}`, telefono = '8112345678' } = {}) {
    const id = randomUUID();
    await pool.query(
      `INSERT INTO pedido (id, dispositivo_id, producto_id, producto_nombre, cantidad, precio_unitario_mxn, envio_mxn,
                           total_mxn, estado, stripe_payment_intent_id, nombre, telefono, calle_numero, colonia, ciudad,
                           entidad, codigo_postal, referencias, pagado_en)
       VALUES (?, ?, ?, ?, 1, 150, 99, 249, ?, ?, ?, ?, 'Av. Juárez 100', 'Centro', 'Monterrey', 'Nuevo León', '64000',
               'Casa azul', ?)`,
      [id, dispositivoId, productoId, `Producto admin ${sufijo}`, estado,
       estado === 'pendiente' ? null : `pi_adm_${randomUUID()}`, nombre, telefono,
       estado === 'pagado' ? new Date() : null]);
    return id;
  }

  const fila = async (id) => (await pool.query('SELECT * FROM pedido WHERE id = ?', [id]))[0][0];
  const bitacora = async (id) =>
    (await pool.query('SELECT accion, personal_id, detalle FROM bitacora WHERE entidad = ? AND entidad_id = ? ORDER BY id', ['pedido', id]))[0];

  function enviarEvento(evento) {
    const payload = JSON.stringify(evento);
    return fetch(`${url}/stripe/webhook`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Stripe-Signature': real.webhooks.generateTestHeaderString({ payload, secret: SECRETO_WEBHOOK }),
      },
      body: payload,
    });
  }
  const eventoReembolso = (cobroId, completo = true) => ({
    id: `evt_prueba_${randomUUID()}`, object: 'event', type: 'charge.refunded',
    data: { object: { id: `ch_prueba_${randomUUID()}`, object: 'charge', payment_intent: cobroId, refunded: completo } },
  });

  // ── sesión (funciones puras) ──────────────────────────────────────────────
  describe('cookie de sesión', () => {
    test('se firma, se lee y se rechaza si la tocan o si venció', () => {
      const valor = firmarSesion(config, 'persona-1');
      assert.equal(leerSesion(config, valor), 'persona-1');

      const [v, carga, firma] = valor.split('.');
      const otraCarga = Buffer.from(JSON.stringify({ p: 'otra-persona', e: Date.now() + 1e9 })).toString('base64url');
      assert.equal(leerSesion(config, `${v}.${otraCarga}.${firma}`), null);               // carga cambiada
      assert.equal(leerSesion(config, `${v}.${carga}.${firma.slice(0, -2)}AA`), null);     // firma cambiada
      assert.equal(leerSesion({ ...config, secreto: 'otro-secreto-'.repeat(4) }, valor), null); // otro secreto
      assert.equal(leerSesion(config, firmarSesion(config, 'persona-1', Date.now() - 9 * 3600_000)), null); // vencida
      for (const basura of ['', 'x', 'v1.a.b', null, undefined, 'v2.a.b', 'a'.repeat(600)]) {
        assert.equal(leerSesion(config, basura), null);
      }
    });

    test('la cookie es HttpOnly y SameSite=Strict; Secure solo en producción', () => {
      const capturar = (cfg) => { let c; ponerCookieSesion({ append: (_n, v) => { c = v; } }, cfg, 'p'); return c; };
      const normal = capturar(config);
      assert.match(normal, /HttpOnly/);
      assert.match(normal, /SameSite=Strict/);
      assert.match(normal, /Path=\/admin/);
      assert.doesNotMatch(normal, /Secure/);
      assert.match(capturar({ ...config, cookieSegura: true }), /; Secure/);
    });

    test('el enlace al panel de llamadas y citas solo acepta http(s); vacío = sin enlace', async () => {
      assert.equal(direccionPanelPersonal(''), null);
      assert.equal(direccionPanelPersonal(undefined), null);
      assert.equal(direccionPanelPersonal(' http://localhost:5050 '), 'http://localhost:5050/');
      assert.equal(direccionPanelPersonal('https://personal.ejemplo.org/Llamadas'), 'https://personal.ejemplo.org/Llamadas');
      for (const malo of ['javascript:alert(1)', 'localhost:5050', 'ftp://x.org', 'http://usuario:clave@x.org', 'no es url']) {
        assert.throws(() => direccionPanelPersonal(malo), /PANEL_PERSONAL_URL/, malo);
      }

      // Con la dirección configurada, /yo la entrega para que la barra muestre el enlace.
      const app = express();
      app.use(express.json());
      app.use('/admin/api', rutasAdmin(pool, pagos, { ...config, panelPersonal: 'http://localhost:5050/' }));
      app.use(manejadorDeErrores);
      const { s, u } = await levantar(app);
      try {
        const { cookie } = await entrar(CUENTAS.operador.usuario, CONTRASENA, u);
        const yo = await (await api(cookie, 'GET', '/yo', undefined, { base: u })).json();
        assert.equal(yo.panel_personal, 'http://localhost:5050/');
      } finally {
        await new Promise((listo) => s.close(listo));
      }
    });
  });

  // ── inicio de sesión ──────────────────────────────────────────────────────
  describe('inicio de sesión', () => {
    test('sin sesión, todo lo de administración responde 401', async () => {
      for (const [m, ruta] of [['GET', '/yo'], ['GET', '/pedidos'], ['GET', `/pedidos/${randomUUID()}`],
        ['POST', `/pedidos/${randomUUID()}/envio`], ['POST', `/pedidos/${randomUUID()}/reembolso`]]) {
        const r = await api(null, m, ruta, m === 'POST' ? {} : undefined);
        assert.equal(r.status, 401, `${m} ${ruta}`);
      }
    });

    test('entra con la contraseña correcta y la cookie queda protegida', async () => {
      const { r, cookie, json } = await entrar(CUENTAS.admin.usuario);
      assert.equal(r.status, 200);
      assert.deepEqual(json, { usuario: CUENTAS.admin.usuario, rol: 'administrativo' });
      const setCookie = r.headers.getSetCookie()[0];
      assert.match(setCookie, /HttpOnly/);
      assert.match(setCookie, /SameSite=Strict/);
      assert.equal(r.headers.get('cache-control'), 'no-store');

      const yo = await (await api(cookie, 'GET', '/yo')).json();
      assert.deepEqual(yo, {
        usuario: CUENTAS.admin.usuario, rol: 'administrativo', pagos: { disponible: true, modo: 'prueba' }, panel_personal: null,
      });
    });

    test('el usuario no distingue mayúsculas y el login queda en la bitácora', async () => {
      const { r } = await entrar(CUENTAS.operador.usuario.toUpperCase());
      assert.equal(r.status, 200);
      const [filas] = await pool.query(
        "SELECT accion FROM bitacora WHERE personal_id = ? AND accion = 'login_ok'", [ids.operador]);
      assert.ok(filas.length >= 1);
    });

    test('contraseña mala, usuario que no existe y cuenta dada de baja dan el mismo mensaje', async () => {
      const mensajes = new Set();
      for (const [u, c] of [[CUENTAS.admin.usuario, 'contrasena-equivocada'], ['nadie.existe.aqui', CONTRASENA],
        [CUENTAS.baja.usuario, CONTRASENA]]) {
        const { r, json } = await entrar(u, c);
        assert.equal(r.status, 401, u);
        assert.equal(r.headers.getSetCookie().length, 0);
        mensajes.add(json.error);
      }
      assert.deepEqual([...mensajes], ['Usuario o contraseña incorrectos']);
    });

    test('una cuenta que solo entra con matrícula (panel de llamadas) no entra aquí ni se bloquea', async (t) => {
      const [[{ hay }]] = await pool.query(
        `SELECT COUNT(*) AS hay FROM information_schema.COLUMNS
          WHERE table_schema = DATABASE() AND table_name = 'personal' AND column_name = 'matricula_huella'`);
      if (!hay) return t.skip('falta correr db/10_modo_personal.sql en tu MySQL local');

      const usuario = 'prueba.matricula.pagos';
      const [[{ id: delegacionId }]] = await pool.query('SELECT id FROM delegacion ORDER BY id LIMIT 1');
      await pool.query(
        `INSERT INTO personal (delegacion_id, usuario, hash_contrasena, matricula_huella, rol, activo)
         VALUES (?, ?, NULL, SHA2('PRUEBAMATRICULAPAGOS00001', 256), 'operador', 1)
         ON DUPLICATE KEY UPDATE hash_contrasena = NULL, activo = 1, intentos_fallidos = 0, bloqueado_hasta = NULL`,
        [delegacionId, usuario]);

      for (let i = 0; i < 6; i++) {
        const { r, json } = await entrar(usuario, CONTRASENA);
        assert.equal(r.status, 401);                       // antes de este arreglo: 500 (bcrypt sin hash)
        assert.equal(json.error, 'Usuario o contraseña incorrectos');
        assert.equal(r.headers.getSetCookie().length, 0);
      }
      const [[cuenta]] = await pool.query(
        'SELECT intentos_fallidos, bloqueado_hasta FROM personal WHERE usuario = ?', [usuario]);
      assert.equal(cuenta.intentos_fallidos, 0);           // su acceso con matrícula no se ve afectado
      assert.equal(cuenta.bloqueado_hasta, null);
    });

    test('datos incompletos o enormes: 400', async () => {
      for (const cuerpo of [{}, { usuario: 'ab', contrasena: 'x' }, { usuario: 'ana', contrasena: 'x'.repeat(500) }, { usuario: 123 }]) {
        const r = await fetch(`${url}/admin/api/sesion`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo) });
        assert.equal(r.status, 400, JSON.stringify(cuerpo).slice(0, 40));
      }
    });

    test('5 contraseñas malas bloquean la cuenta; mientras dura, ni la correcta entra', async () => {
      for (let i = 0; i < 5; i++) assert.equal((await entrar(CUENTAS.bloqueo.usuario, 'mala-contrasena')).r.status, 401);
      const bloqueada = await entrar(CUENTAS.bloqueo.usuario);
      assert.equal(bloqueada.r.status, 429);
      assert.equal(bloqueada.cookie, null);

      // Cuando vence el bloqueo, vuelve a entrar y el conteo se reinicia.
      await pool.query("UPDATE personal SET bloqueado_hasta = UTC_TIMESTAMP(3) - INTERVAL 1 MINUTE WHERE id = ?", [ids.bloqueo]);
      assert.equal((await entrar(CUENTAS.bloqueo.usuario)).r.status, 200);
      const [[p]] = await pool.query('SELECT intentos_fallidos, bloqueado_hasta FROM personal WHERE id = ?', [ids.bloqueo]);
      assert.equal(p.intentos_fallidos, 0);
      assert.equal(p.bloqueado_hasta, null);
    });

    test('una cookie manipulada, vencida o de una cuenta dada de baja no sirve', async () => {
      const buena = (await entrar(CUENTAS.operador.usuario)).cookie;
      assert.equal((await api(buena, 'GET', '/yo')).status, 200);
      assert.equal((await api(`${buena.slice(0, -3)}AAA`, 'GET', '/yo')).status, 401);
      assert.equal((await api(`sesion_admin=${firmarSesion(config, ids.operador, Date.now() - 9 * 3600_000)}`, 'GET', '/yo')).status, 401);

      // Dan de baja a la persona: su cookie, que todavía no vence, deja de funcionar al instante.
      await pool.query('UPDATE personal SET activo = 0 WHERE id = ?', [ids.operador]);
      try {
        assert.equal((await api(buena, 'GET', '/yo')).status, 401);
      } finally {
        await pool.query('UPDATE personal SET activo = 1 WHERE id = ?', [ids.operador]);
      }
    });

    test('cerrar sesión borra la cookie', async () => {
      const r = await api(null, 'DELETE', '/sesion');
      assert.equal(r.status, 204);
      assert.match(r.headers.getSetCookie()[0], /Max-Age=0/);
    });

    test('el límite de intentos por IP también frena el login', async () => {
      const app = express();
      app.use(express.json());
      app.use('/admin/api', rutasAdmin(pool, pagos, { ...config, limiteLoginPorQuinceMin: 3 }));
      app.use(manejadorDeErrores);
      const { s, u } = await levantar(app);
      try {
        const codigos = [];
        for (let i = 0; i < 5; i++) codigos.push((await entrar('nadie.existe.aqui', 'x', u)).r.status);
        assert.deepEqual(codigos, [401, 401, 401, 429, 429]);
      } finally {
        await new Promise((listo) => s.close(listo));
      }
    });

    test('rechaza peticiones que cambian algo desde otro sitio (Origin distinto)', async () => {
      await sesiones();
      const id = await sembrar();
      const ajeno = await api(cookieAdmin, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'preparando' },
        { cabeceras: { Origin: 'https://sitio-malo.example' } });
      assert.equal(ajeno.status, 403);
      assert.equal((await fila(id)).estado_envio, 'por_preparar');

      const propio = await api(cookieAdmin, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'preparando' },
        { cabeceras: { Origin: url } });
      assert.equal(propio.status, 200);
    });
  });

  // ── lista ─────────────────────────────────────────────────────────────────
  describe('lista de pedidos', () => {
    test('filtra por estado y por envío, y no trae teléfono ni domicilio', async () => {
      await sesiones();
      const nombre = `Lista ${sufijo}`;
      const pagado = await sembrar({ nombre });
      const pendiente = await sembrar({ nombre, estado: 'pendiente' });
      const cancelado = await sembrar({ nombre, estado: 'cancelado' });
      await api(cookieOperador, 'POST', `/pedidos/${pagado}/envio`, { estado_envio: 'preparando' });

      const todos = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}`)).json();
      assert.equal(todos.total, 3);
      assert.deepEqual(new Set(todos.pedidos.map((p) => p.id)), new Set([pagado, pendiente, cancelado]));
      for (const p of todos.pedidos) {
        for (const prohibido of ['telefono', 'calle_numero', 'colonia', 'referencias', 'dispositivo_id', 'stripe_payment_intent_id']) {
          assert.ok(!(prohibido in p), `la lista no debe traer ${prohibido}`);
        }
      }

      const soloPendientes = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}&estado=pendiente`)).json();
      assert.deepEqual(soloPendientes.pedidos.map((p) => p.id), [pendiente]);

      const porEnviar = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}&estado=pagado&envio=por_preparar,preparando`)).json();
      assert.deepEqual(porEnviar.pedidos.map((p) => p.id), [pagado]);
      const enviados = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}&envio=enviado`)).json();
      assert.equal(enviados.total, 0);

      assert.ok(todos.resumen.pagado >= 1 && todos.resumen.pendiente >= 1 && todos.resumen.cancelado >= 1);
      assert.ok(todos.resumen.por_enviar >= 1);
      assert.ok(Number.isInteger(todos.resumen.enviado) && Number.isInteger(todos.resumen.entregado));
    });

    test('pagina de 25 en 25', async () => {
      await sesiones();
      const nombre = `Paginacion ${sufijo}`;
      for (let i = 0; i < 27; i++) await sembrar({ nombre: `${nombre} ${i}` });
      const p1 = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}`)).json();
      assert.equal(p1.total, 27);
      assert.equal(p1.paginas, 2);
      assert.equal(p1.pedidos.length, 25);
      const p2 = await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(nombre)}&pagina=2`)).json();
      assert.equal(p2.pedidos.length, 2);
      assert.equal(p2.pagina, 2);
    });

    test('busca por nombre, folio y teléfono; los comodines de SQL se toman literales', async () => {
      await sesiones();
      const nombre = `Buscar ${sufijo}`;
      const id = await sembrar({ nombre: `${nombre} 100% Real`, telefono: '5598765432' });
      const { folio } = await fila(id);

      const por = async (q) => (await (await api(cookieOperador, 'GET', `/pedidos?q=${encodeURIComponent(q)}`)).json()).pedidos.map((p) => p.id);
      assert.deepEqual(await por(folio), [id]);
      assert.deepEqual(await por('5598765432'), [id]);
      assert.deepEqual(await por(`${nombre} 100% Real`), [id]);
      assert.deepEqual(await por(`${nombre} 100%`), [id]);
      assert.deepEqual(await por(`${nombre}%Real`), []);       // % no es comodín
      assert.deepEqual(await por(`${nombre} 1_0% Real`), []);  // _ tampoco
    });

    test('filtros no válidos: 400', async () => {
      await sesiones();
      for (const q of ['estado=inventado', 'envio=volando', 'pagina=0', 'pagina=abc', `q=${'x'.repeat(100)}`]) {
        assert.equal((await api(cookieOperador, 'GET', `/pedidos?${q}`)).status, 400, q);
      }
    });
  });

  // ── detalle ───────────────────────────────────────────────────────────────
  describe('detalle de un pedido', () => {
    test('trae domicilio y teléfono, y ver el pedido queda en la bitácora', async () => {
      await sesiones();
      const id = await sembrar();
      const r = await api(cookieOperador, 'GET', `/pedidos/${id}`);
      assert.equal(r.status, 200);
      assert.equal(r.headers.get('cache-control'), 'no-store');
      const p = await r.json();
      assert.equal(p.telefono, '8112345678');
      assert.equal(p.calle_numero, 'Av. Juárez 100');
      assert.equal(p.referencias, 'Casa azul');
      assert.equal(p.total_mxn, 249);
      assert.equal(p.estado_envio, 'por_preparar');
      assert.ok(!('dispositivo_id' in p));
      assert.equal(p.puede_reembolsar, false);   // el operador no reembolsa

      const comoAdmin = await (await api(cookieAdmin, 'GET', `/pedidos/${id}`)).json();
      assert.equal(comoAdmin.puede_reembolsar, true);

      const vistas = (await bitacora(id)).filter((b) => b.accion === 'ver_pedido');
      assert.deepEqual(vistas.map((v) => v.personal_id), [ids.operador, ids.admin]);
    });

    test('un pedido que no existe o un id raro: 404', async () => {
      await sesiones();
      for (const id of [randomUUID(), 'no-es-uuid', '1; DROP TABLE pedido']) {
        assert.equal((await api(cookieOperador, 'GET', `/pedidos/${encodeURIComponent(id)}`)).status, 404, id);
      }
    });
  });

  // ── envío ─────────────────────────────────────────────────────────────────
  describe('estado del envío', () => {
    test('avanza por preparando > enviado (con guía) > entregado y todo queda anotado', async () => {
      await sesiones();
      const id = await sembrar();

      let r = await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'preparando' });
      assert.equal(r.status, 200);
      assert.equal((await r.json()).estado_envio, 'preparando');
      assert.equal((await fila(id)).enviado_en, null);

      r = await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'enviado', guia: 'DHL 123-456' });
      const enviado = await r.json();
      assert.equal(enviado.estado_envio, 'enviado');
      assert.equal(enviado.guia_envio, 'DHL 123-456');
      assert.ok(enviado.enviado_en);

      // Corregir la guía estando enviado sí se puede; avanzar a "entregado" cierra el envío.
      r = await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'enviado', guia: 'DHL 999-000' });
      assert.equal((await r.json()).guia_envio, 'DHL 999-000');
      r = await api(cookieAdmin, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'entregado' });
      const entregado = await r.json();
      assert.equal(entregado.estado_envio, 'entregado');
      assert.equal(entregado.guia_envio, 'DHL 999-000');
      assert.ok(entregado.entregado_en);

      assert.deepEqual(entregado.historial.map((h) => [h.accion, h.usuario, h.detalle.a]), [
        ['actualizar_envio', CUENTAS.operador.usuario, 'preparando'],
        ['actualizar_envio', CUENTAS.operador.usuario, 'enviado'],
        ['actualizar_envio', CUENTAS.operador.usuario, 'enviado'],
        ['actualizar_envio', CUENTAS.admin.usuario, 'entregado'],
      ]);
    });

    test('se puede saltar de preparando a entregado, pero nunca retroceder ni repetir', async () => {
      await sesiones();
      const id = await sembrar();
      assert.equal((await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'entregado' })).status, 200);
      const fila1 = await fila(id);
      assert.ok(fila1.enviado_en && fila1.entregado_en);                       // las dos fechas se llenan
      for (const estado of ['preparando', 'enviado', 'entregado']) {
        assert.equal((await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: estado })).status, 409, estado);
      }
    });

    test('solo pedidos pagados; guías y estados inventados se rechazan', async () => {
      await sesiones();
      for (const estado of ['pendiente', 'cancelado']) {
        const id = await sembrar({ estado });
        assert.equal((await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'preparando' })).status, 409, estado);
        assert.equal((await fila(id)).estado_envio, 'por_preparar');
      }
      const id = await sembrar();
      for (const cuerpo of [{ estado_envio: 'volando' }, { estado_envio: 'por_preparar' }, {}, { estado_envio: 'enviado', guia: '<script>' },
        { estado_envio: 'enviado', guia: 'ab' }, { estado_envio: 'enviado', guia: 'x'.repeat(41) }]) {
        assert.equal((await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, cuerpo)).status, 400, JSON.stringify(cuerpo));
      }
      assert.equal((await api(cookieOperador, 'POST', `/pedidos/${randomUUID()}/envio`, { estado_envio: 'preparando' })).status, 404);
      assert.equal((await fila(id)).estado_envio, 'por_preparar');
    });
  });

  // ── reembolsos ────────────────────────────────────────────────────────────
  describe('reembolsos con Stripe', () => {
    test('el operador no puede reembolsar (403) y no se toca Stripe', async () => {
      await sesiones();
      refundsCreados = [];
      const id = await sembrar();
      const r = await api(cookieOperador, 'POST', `/pedidos/${id}/reembolso`, {});
      assert.equal(r.status, 403);
      assert.equal(refundsCreados.length, 0);
      assert.equal((await fila(id)).estado, 'pagado');
    });

    test('el administrativo reembolsa: Stripe recibe llave de idempotencia y el pedido queda reembolsado', async () => {
      await sesiones();
      refundsCreados = [];
      const id = await sembrar();
      const antes = await fila(id);

      const r = await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, { motivo: 'Llegó roto' });
      assert.equal(r.status, 200);
      const p = await r.json();
      assert.equal(p.estado, 'reembolsado');
      assert.equal(p.reembolso_motivo, 'Llegó roto');
      assert.ok(p.reembolsado_en);
      assert.equal(p.puede_reembolsar, false);

      assert.equal(refundsCreados.length, 1);
      assert.equal(refundsCreados[0].parametros.payment_intent, antes.stripe_payment_intent_id);
      assert.equal(refundsCreados[0].parametros.amount, undefined);           // reembolso total
      assert.equal(refundsCreados[0].opciones.idempotencyKey, `reembolso-${id}`);
      assert.equal((await fila(id)).stripe_refund_id, refundsCreados[0].id);

      const anotado = (await bitacora(id)).find((b) => b.accion === 'reembolsar_pedido');
      assert.equal(anotado.personal_id, ids.admin);
      assert.equal(anotado.detalle.reembolso, refundsCreados[0].id);
      assert.equal(anotado.detalle.motivo, 'Llegó roto');

      // Reembolsado: ni se reembolsa otra vez ni se mueve su envío.
      assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {})).status, 409);
      assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'preparando' })).status, 409);
      assert.equal(refundsCreados.length, 1);
    });

    test('un pedido ya enviado también se puede reembolsar (devolución)', async () => {
      await sesiones();
      const id = await sembrar();
      await api(cookieOperador, 'POST', `/pedidos/${id}/envio`, { estado_envio: 'entregado' });
      const r = await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {});
      assert.equal(r.status, 200);
      const p = await fila(id);
      assert.equal(p.estado, 'reembolsado');
      assert.equal(p.estado_envio, 'entregado');
    });

    test('solo pedidos pagados; sin cuerpo y con motivo malo', async () => {
      await sesiones();
      refundsCreados = [];
      for (const estado of ['pendiente', 'cancelado']) {
        const id = await sembrar({ estado });
        assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {})).status, 409, estado);
      }
      assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${randomUUID()}/reembolso`, {})).status, 404);
      const id = await sembrar();
      assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, { motivo: 'x'.repeat(201) })).status, 400);
      assert.equal(refundsCreados.length, 0);
      // Sin cuerpo también es válido (el motivo es opcional).
      assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`)).status, 200);
    });

    test('si Stripe falla, el pedido sigue pagado y se avisa con 502', async () => {
      await sesiones();
      const id = await sembrar();
      fallaRefund = { type: 'StripeConnectionError' };
      try {
        const r = await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {});
        assert.equal(r.status, 502);
        assert.equal((await fila(id)).estado, 'pagado');
        assert.equal((await bitacora(id)).filter((b) => b.accion === 'reembolsar_pedido').length, 0);
      } finally {
        fallaRefund = null;
      }
      estadoRefund = 'failed';
      try {
        assert.equal((await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {})).status, 502);
        assert.equal((await fila(id)).estado, 'pagado');
      } finally {
        estadoRefund = 'succeeded';
      }
    });

    test('si en Stripe ya estaba reembolsado, el pedido se pone al día', async () => {
      await sesiones();
      const id = await sembrar();
      fallaRefund = { code: 'charge_already_refunded', type: 'StripeInvalidRequestError' };
      try {
        const r = await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {});
        assert.equal(r.status, 200);
        const p = await fila(id);
        assert.equal(p.estado, 'reembolsado');
        assert.match(p.stripe_refund_id, /^re_ya_hecho_/);
      } finally {
        fallaRefund = null;
      }
    });

    test('con pagos apagados no se puede reembolsar (503) y el detalle no lo ofrece', async () => {
      const { cookie } = await entrar(CUENTAS.admin.usuario, CONTRASENA, urlSinStripe);
      const id = await sembrar();
      assert.equal((await api(cookie, 'POST', `/pedidos/${id}/reembolso`, {}, { base: urlSinStripe })).status, 503);
      const p = await (await api(cookie, 'GET', `/pedidos/${id}`, undefined, { base: urlSinStripe })).json();
      assert.equal(p.puede_reembolsar, false);
      const yo = await (await api(cookie, 'GET', '/yo', undefined, { base: urlSinStripe })).json();
      assert.deepEqual(yo.pagos, { disponible: false, modo: 'apagado' });
    });

    test('doble clic: Stripe recibe la misma llave y el pedido se anota una sola vez', async () => {
      await sesiones();
      refundsCreados = [];
      const id = await sembrar();
      const [a, b] = await Promise.all([
        api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {}),
        api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, {}),
      ]);
      assert.ok([a.status, b.status].includes(200));
      assert.ok(refundsCreados.every((x) => x.opciones.idempotencyKey === `reembolso-${id}`));
      assert.equal((await bitacora(id)).filter((x) => x.accion === 'reembolsar_pedido').length, 1);
      assert.equal((await fila(id)).estado, 'reembolsado');
    });
  });

  // ── aviso de Stripe: charge.refunded ──────────────────────────────────────
  describe('webhook charge.refunded', () => {
    test('un reembolso hecho directo en Stripe pone el pedido en reembolsado y queda en el historial', async () => {
      await sesiones();
      const id = await sembrar();
      const cobro = (await fila(id)).stripe_payment_intent_id;
      assert.equal((await enviarEvento(eventoReembolso(cobro))).status, 200);

      const p = await fila(id);
      assert.equal(p.estado, 'reembolsado');
      assert.equal(p.reembolso_motivo, 'Reembolsado desde Stripe');
      assert.ok(p.reembolsado_en);

      const anotado = (await bitacora(id)).find((b) => b.accion === 'reembolso_confirmado_stripe');
      assert.equal(anotado.personal_id, null);
      const detalle = await (await api(cookieAdmin, 'GET', `/pedidos/${id}`)).json();
      assert.ok(detalle.historial.some((h) => h.accion === 'reembolso_confirmado_stripe' && h.usuario === null));
    });

    test('un reembolso parcial se ignora; el mismo aviso dos veces no duplica nada', async () => {
      const id = await sembrar();
      const cobro = (await fila(id)).stripe_payment_intent_id;
      assert.equal((await enviarEvento(eventoReembolso(cobro, false))).status, 200);
      assert.equal((await fila(id)).estado, 'pagado');

      const evento = eventoReembolso(cobro);
      assert.equal((await enviarEvento(evento)).status, 200);
      const repetido = await (await enviarEvento(evento)).json();
      assert.equal(repetido.repetido, true);
      assert.equal((await bitacora(id)).filter((b) => b.accion === 'reembolso_confirmado_stripe').length, 1);
    });

    test('si el aviso llega mientras el sitio hace el reembolso, el pedido conserva quién y por qué', async () => {
      await sesiones();
      const id = await sembrar();
      const cobro = (await fila(id)).stripe_payment_intent_id;
      alCrearRefund = async () => { assert.equal((await enviarEvento(eventoReembolso(cobro))).status, 200); };
      try {
        const r = await api(cookieAdmin, 'POST', `/pedidos/${id}/reembolso`, { motivo: 'Cliente lo pidió' });
        assert.equal(r.status, 200);
      } finally {
        alCrearRefund = null;
      }
      const p = await fila(id);
      assert.equal(p.estado, 'reembolsado');
      assert.match(p.stripe_refund_id, /^re_prueba_/);
      assert.equal(p.reembolso_motivo, 'Cliente lo pidió');
      const acciones = (await bitacora(id)).map((b) => b.accion);
      assert.ok(acciones.includes('reembolsar_pedido') && acciones.includes('reembolso_confirmado_stripe'));
    });
  });
});
