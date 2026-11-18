import Stripe from 'stripe';

/**
 * Configuración de los pagos con Stripe. Todo sale de variables de entorno (archivo .env):
 *   STRIPE_SECRET_KEY       llave SECRETA (sk_test_... en pruebas). Solo vive aquí, en el servidor:
 *                           NUNCA va en la app, en GitHub ni en un chat.
 *   STRIPE_PUBLISHABLE_KEY  llave PUBLICABLE (pk_test_...). Es la única que se manda a la app.
 *   STRIPE_WEBHOOK_SECRET   secreto del webhook (whsec_...): sirve para comprobar que los avisos
 *                           de "pago recibido" de verdad vienen de Stripe.
 *   ENVIO_MXN               costo fijo del envío a domicilio, en pesos (por defecto 99).
 *
 * Si no hay STRIPE_SECRET_KEY, los pagos quedan apagados: el resto de la API sigue funcionando.
 */
export function configuracionPagos() {
  const llaveSecreta = (process.env.STRIPE_SECRET_KEY || '').trim();
  const llavePublicable = (process.env.STRIPE_PUBLISHABLE_KEY || '').trim();
  const secretoWebhook = (process.env.STRIPE_WEBHOOK_SECRET || '').trim();

  const envioMXN = Number(process.env.ENVIO_MXN ?? '99');
  if (!Number.isFinite(envioMXN) || envioMXN < 0 || envioMXN > 5000 || Math.round(envioMXN * 100) !== envioMXN * 100) {
    throw new Error('ENVIO_MXN debe ser un número de pesos entre 0 y 5000, con máximo 2 decimales');
  }

  if (!llaveSecreta) {
    return { stripe: null, publishableKey: '', webhookSecret: '', envioMXN, modo: 'apagado' };
  }

  const modo = llaveSecreta.startsWith('sk_test_') ? 'prueba' : llaveSecreta.startsWith('sk_live_') ? 'real' : null;
  if (!modo) {
    throw new Error('STRIPE_SECRET_KEY no parece una llave secreta de Stripe (debe empezar con sk_test_ o sk_live_)');
  }
  const prefijoPublicable = modo === 'prueba' ? 'pk_test_' : 'pk_live_';
  if (!llavePublicable.startsWith(prefijoPublicable)) {
    throw new Error(`STRIPE_PUBLISHABLE_KEY debe empezar con ${prefijoPublicable} (la llave secreta es de modo ${modo})`);
  }
  if (secretoWebhook && !secretoWebhook.startsWith('whsec_')) {
    throw new Error('STRIPE_WEBHOOK_SECRET debe empezar con whsec_');
  }

  return {
    stripe: new Stripe(llaveSecreta, { maxNetworkRetries: 2, timeout: 15_000 }),
    publishableKey: llavePublicable,
    webhookSecret: secretoWebhook,
    envioMXN,
    modo,
  };
}
