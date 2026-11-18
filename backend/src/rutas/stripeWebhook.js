import express, { Router } from 'express';

/**
 * Aviso (webhook) de Stripe: así se entera el servidor de que un pago se completó.
 *   POST /stripe/webhook
 *
 * REGLAS DE SEGURIDAD
 *   - Se lee el cuerpo SIN convertir a JSON (express.raw): la firma de Stripe se calcula sobre
 *     los bytes exactos. Por eso esta ruta se monta ANTES de express.json() en server.js.
 *   - Se comprueba la firma con STRIPE_WEBHOOK_SECRET. Sin firma válida, 400 y no se toca nada.
 *   - Cada evento (evt_...) se procesa una sola vez: Stripe reintenta si no recibe 200 y a veces
 *     manda el mismo aviso dos veces.
 *   - Un pedido solo pasa a "pagado" si el monto y la moneda del cobro coinciden con el pedido.
 *   - Eventos que atiende: payment_intent.succeeded (pagado), payment_intent.canceled (cancelado)
 *     y charge.refunded (reembolsado). Con `stripe listen` llegan todos; en el Dashboard hay que
 *     marcar esos tres al crear el endpoint.
 */
export function rutaWebhookStripe(pool, { stripe, webhookSecret }) {
  const router = Router();

  router.post('/', express.raw({ type: 'application/json', limit: '64kb' }), async (req, res) => {
    let evento;
    try {
      evento = stripe.webhooks.constructEvent(req.body, req.get('stripe-signature'), webhookSecret);
    } catch {
      return res.status(400).json({ error: 'firma no válida' });
    }

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();

      // ¿Ya procesamos este evento? (INSERT IGNORE no inserta si el id ya existe.)
      const [alta] = await conexion.query(
        'INSERT IGNORE INTO evento_stripe (id, tipo) VALUES (?, ?)', [evento.id, evento.type]);
      if (alta.affectedRows === 0) {
        await conexion.commit();
        return res.json({ recibido: true, repetido: true });
      }

      if (evento.type === 'payment_intent.succeeded') {
        await marcarPagado(conexion, evento.data.object);
      } else if (evento.type === 'payment_intent.canceled') {
        await conexion.query(
          "UPDATE pedido SET estado = 'cancelado' WHERE stripe_payment_intent_id = ? AND estado = 'pendiente'",
          [evento.data.object.id]);
      } else if (evento.type === 'charge.refunded') {
        await marcarReembolsado(conexion, evento.data.object);
      }
      // Los demás tipos de evento se anotan y se ignoran.

      await conexion.commit();
      res.json({ recibido: true });
    } catch (error) {
      await conexion.rollback().catch(() => {});
      console.error('POST /stripe/webhook falló:', error.code ?? error.message);
      // 500: Stripe reintentará el aviso más tarde (el evento no quedó anotado por el rollback).
      res.status(500).json({ error: 'error del servidor' });
    } finally {
      conexion.release();
    }
  });

  return router;
}

async function marcarPagado(conexion, cobro) {
  const [filas] = await conexion.query(
    'SELECT id, folio, estado, total_mxn FROM pedido WHERE stripe_payment_intent_id = ? FOR UPDATE', [cobro.id]);
  if (filas.length === 0) {
    console.warn('Stripe: pago sin pedido en la base (¿otra cuenta o prueba suelta?):', cobro.id);
    return;
  }
  const pedido = filas[0];
  const esperado = Math.round(Number(pedido.total_mxn) * 100);
  if (cobro.amount !== esperado || String(cobro.currency).toLowerCase() !== 'mxn') {
    // No se marca como pagado: alguien debe revisarlo a mano en el Dashboard de Stripe.
    console.error(`Stripe: el cobro ${cobro.id} no coincide con el pedido ${pedido.folio} `
      + `(cobrado ${cobro.amount} ${cobro.currency}, esperado ${esperado} mxn)`);
    return;
  }
  if (pedido.estado === 'pagado') return;
  await conexion.query(
    "UPDATE pedido SET estado = 'pagado', pagado_en = UTC_TIMESTAMP(3) WHERE id = ?", [pedido.id]);
}

/**
 * Stripe avisa que se devolvió dinero de un cobro (lo hizo el sitio de administración o alguien
 * directo en el Dashboard de Stripe). Aquí solo se pone al día el pedido: solo si el reembolso es
 * TOTAL; uno parcial se ignora (el sitio de administración solo hace reembolsos totales).
 */
async function marcarReembolsado(conexion, cargo) {
  if (!cargo.payment_intent) return;
  if (cargo.refunded !== true) {
    console.warn('Stripe: reembolso parcial del cobro', cargo.payment_intent, '(se ignora; revisar a mano en Stripe)');
    return;
  }
  const [filas] = await conexion.query(
    "SELECT id, folio FROM pedido WHERE stripe_payment_intent_id = ? AND estado = 'pagado' FOR UPDATE",
    [cargo.payment_intent]);
  if (filas.length === 0) return; // no es un pedido pagado (o el sitio de administración ya lo anotó)
  const pedido = filas[0];
  await conexion.query(
    `UPDATE pedido
        SET estado = 'reembolsado', reembolsado_en = UTC_TIMESTAMP(3),
            reembolso_motivo = COALESCE(reembolso_motivo, 'Reembolsado desde Stripe')
      WHERE id = ?`, [pedido.id]);
  await conexion.query(
    "INSERT INTO bitacora (personal_id, accion, entidad, entidad_id, detalle) VALUES (NULL, 'reembolso_confirmado_stripe', 'pedido', ?, ?)",
    [pedido.id, JSON.stringify({ folio: pedido.folio })]);
}
