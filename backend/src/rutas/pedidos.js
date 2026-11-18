import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { ErrorHttp } from '../errores.js';

/**
 * Pantalla 6 — Comprar un producto con causa (pago con Stripe y envío a domicilio).   Dueño: Sebastián
 *   POST /api/pedidos               crea el pedido y el cobro en Stripe; devuelve lo que la app necesita
 *                                   para abrir la hoja de pago (client_secret + llave publicable)
 *   GET  /api/pedidos/condiciones   costo de envío y límites, para mostrar el total antes de pagar (pública)
 *   GET  /api/pedidos/:id           estado del pedido (pendiente / pagado / cancelado)
 *   POST /api/pedidos/:id/cancelar  cancela un pedido que todavía no se pagó
 * Todas exigen el header X-Dispositivo-Id: un pedido solo lo ve el dispositivo que lo creó.
 *
 * REGLAS DE SEGURIDAD
 *   - La app manda producto y cantidad, NUNCA el precio: el precio sale de la base de datos.
 *   - El pedido pasa a "pagado" SOLO cuando Stripe avisa por el webhook (stripeWebhook.js),
 *     nunca porque la app diga "ya pagué".
 *   - Nada de tarjetas pasa por aquí ni se guarda: la tarjeta la captura la hoja de pago de Stripe.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIN_CONTROL = /^[^\u0000-\u001F\u007F]*$/;
const CENTAVOS_MINIMOS = 1000; // Stripe no cobra menos de 10 pesos mexicanos

// Texto sin caracteres de control, con largo mínimo y máximo.
const texto = (etiqueta, min, max) =>
  z.string({ required_error: `falta ${etiqueta}`, invalid_type_error: `${etiqueta} no es válido` })
    .trim()
    .min(min, `${etiqueta} es muy corto`)
    .max(max, `${etiqueta} es muy largo`)
    .regex(SIN_CONTROL, `${etiqueta} no es válido`);

const esquemaPedido = z.object({
  producto_id: z.number({ required_error: 'falta el producto', invalid_type_error: 'el producto no es válido' })
    .int('el producto no es válido').min(1, 'el producto no es válido'),
  cantidad: z.number({ required_error: 'falta la cantidad', invalid_type_error: 'la cantidad no es válida' })
    .int('la cantidad no es válida').min(1, 'la cantidad mínima es 1').max(10, 'la cantidad máxima es 10'),
  nombre: texto('el nombre', 3, 120),
  telefono: z.string({ required_error: 'falta el teléfono', invalid_type_error: 'el teléfono no es válido' })
    .regex(/^[+]?[0-9]{10,15}$/, 'el teléfono no es válido'),
  calle_numero: texto('la calle y el número', 3, 150),
  colonia: texto('la colonia', 2, 100),
  ciudad: texto('la ciudad', 2, 100),
  entidad: texto('el estado', 2, 60),
  codigo_postal: z.string({ required_error: 'falta el código postal', invalid_type_error: 'el código postal no es válido' })
    .regex(/^[0-9]{5}$/, 'el código postal debe tener 5 dígitos'),
  referencias: texto('las referencias', 0, 200).optional(),
});

function dispositivo(req) {
  const id = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
  if (!UUID.test(id)) throw new ErrorHttp(401, 'falta el dispositivo');
  return id;
}

function idPedido(req) {
  if (!UUID.test(req.params.id)) throw new ErrorHttp(404, 'el pedido no existe');
  return req.params.id.toLowerCase();
}

// El dinero se calcula en centavos enteros para no arrastrar errores de decimales.
const aCentavos = (pesos) => Math.round(Number(pesos) * 100);
const aPesosTexto = (centavos) => (centavos / 100).toFixed(2);

/**
 * @param pool    pool de MySQL (el único de la API)
 * @param pagos   lo que devuelve configuracionPagos() de src/stripe.js
 *                (en las pruebas también puede traer limiteCrearPorMinuto)
 */
export function rutasPedidos(pool, pagos) {
  const router = Router();
  const { stripe, publishableKey, envioMXN } = pagos;

  // Cada pedido escribe en la base y crea un cobro en Stripe: límite más estricto que el general.
  const limiteCrear = rateLimit({
    windowMs: 60_000, limit: pagos.limiteCrearPorMinuto ?? 10, standardHeaders: 'draft-7', legacyHeaders: false,
  });

  // Crea el pedido (pendiente) y el cobro en Stripe.
  router.post('/', limiteCrear, async (req, res) => {
    const d = dispositivo(req);
    if (!stripe) throw new ErrorHttp(503, 'Los pagos no están disponibles por ahora');

    const lectura = esquemaPedido.safeParse(req.body || {});
    if (!lectura.success) throw new ErrorHttp(400, lectura.error.issues[0].message);
    const datos = lectura.data; // solo los campos del esquema: cualquier otro (como un precio) se descarta

    const [disp] = await pool.query('SELECT 1 FROM dispositivo WHERE id = ?', [d]);
    if (disp.length === 0) throw new ErrorHttp(400, 'dispositivo no registrado');

    // El precio es el de la base de datos, no el que diga la app.
    const [productos] = await pool.query(
      'SELECT id, nombre, precio_mxn FROM producto WHERE id = ? AND activo = 1', [datos.producto_id]);
    if (productos.length === 0) throw new ErrorHttp(404, 'el producto no existe');
    const producto = productos[0];

    const precioCentavos = aCentavos(producto.precio_mxn);
    const envioCentavos = aCentavos(envioMXN);
    const totalCentavos = precioCentavos * datos.cantidad + envioCentavos;
    if (totalCentavos < CENTAVOS_MINIMOS) throw new ErrorHttp(400, 'el total es menor al mínimo que se puede cobrar ($10)');

    const id = randomUUID();
    await pool.query(
      `INSERT INTO pedido (id, dispositivo_id, producto_id, producto_nombre, cantidad, precio_unitario_mxn,
                           envio_mxn, total_mxn, nombre, telefono, calle_numero, colonia, ciudad, entidad,
                           codigo_postal, referencias)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, d, producto.id, producto.nombre, datos.cantidad, aPesosTexto(precioCentavos),
       aPesosTexto(envioCentavos), aPesosTexto(totalCentavos), datos.nombre, datos.telefono,
       datos.calle_numero, datos.colonia, datos.ciudad, datos.entidad, datos.codigo_postal,
       datos.referencias || null]);
    const [[{ folio }]] = await pool.query('SELECT folio FROM pedido WHERE id = ?', [id]);

    let cobro;
    try {
      cobro = await stripe.paymentIntents.create({
        amount: totalCentavos,
        currency: 'mxn',
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
        description: `Pedido ${folio} · ${producto.nombre} x${datos.cantidad}`,
        metadata: { pedido_id: id, folio },
      }, { idempotencyKey: `pedido-${id}` });
    } catch (error) {
      // El detalle se queda en el log del servidor; el usuario solo ve un mensaje claro.
      console.error('POST /api/pedidos: Stripe no creó el cobro:', error.code ?? error.type ?? error.message);
      await pool.query("UPDATE pedido SET estado = 'cancelado' WHERE id = ? AND estado = 'pendiente'", [id]);
      throw new ErrorHttp(502, 'No pudimos iniciar el pago. Intenta de nuevo.');
    }

    await pool.query('UPDATE pedido SET stripe_payment_intent_id = ? WHERE id = ?', [cobro.id, id]);
    res.status(201).json({
      id,
      folio,
      producto_nombre: producto.nombre,
      cantidad: datos.cantidad,
      envio_mxn: envioCentavos / 100,
      total_mxn: totalCentavos / 100,
      client_secret: cobro.client_secret,
      publishable_key: publishableKey,
    });
  });

  // Condiciones de compra que la app muestra ANTES de pagar (costo de envío, cantidad máxima).
  // Es pública y no lleva datos personales. Va antes de "/:id" para que "condiciones" no se lea como un id.
  router.get('/condiciones', (_req, res) => {
    res.json({
      disponible: Boolean(stripe),
      envio_mxn: envioMXN,
      cantidad_maxima: 10,
      total_minimo_mxn: CENTAVOS_MINIMOS / 100,
    });
  });

  // Estado de un pedido del dispositivo (la app lo consulta después de pagar).
  router.get('/:id', async (req, res) => {
    const [filas] = await pool.query(
      `SELECT id, folio, estado, producto_nombre, cantidad, envio_mxn, total_mxn, creado_en, pagado_en
         FROM pedido WHERE id = ? AND dispositivo_id = ?`,
      [idPedido(req), dispositivo(req)]);
    if (filas.length === 0) throw new ErrorHttp(404, 'el pedido no existe');
    res.set('Cache-Control', 'no-store');
    res.json(filas[0]);
  });

  // Cancela un pedido que todavía no se paga (por ejemplo, la persona cerró la hoja de pago).
  router.post('/:id/cancelar', async (req, res) => {
    const id = idPedido(req);
    const [filas] = await pool.query(
      'SELECT estado, stripe_payment_intent_id FROM pedido WHERE id = ? AND dispositivo_id = ?',
      [id, dispositivo(req)]);
    if (filas.length === 0) throw new ErrorHttp(404, 'el pedido no existe');
    const { estado, stripe_payment_intent_id: cobroId } = filas[0];
    if (estado === 'pagado') throw new ErrorHttp(409, 'el pedido ya está pagado');
    if (estado === 'cancelado') return res.status(204).end();

    if (cobroId && stripe) {
      try {
        await stripe.paymentIntents.cancel(cobroId);
      } catch (error) {
        // Por ejemplo, el pago justo se acaba de completar: el webhook marcará el pedido como pagado.
        console.error('POST /api/pedidos/:id/cancelar: Stripe no canceló el cobro:', error.code ?? error.type ?? error.message);
        throw new ErrorHttp(409, 'No se pudo cancelar el pedido. Intenta de nuevo en un momento.');
      }
    }
    await pool.query("UPDATE pedido SET estado = 'cancelado' WHERE id = ? AND estado = 'pendiente'", [id]);
    res.status(204).end();
  });

  return router;
}
