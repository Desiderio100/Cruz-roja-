import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { crearPool } from './db.js';
import { manejadorDeErrores } from './errores.js';
import { rutasProductos } from './rutas/productos.js';
import { rutasCitas } from './rutas/citas.js';
import { rutasDispositivos } from './rutas/dispositivos.js';
import { rutasLlamadas } from './rutas/llamadas.js';
import { rutasRegistro } from './rutas/registro.js';
import { rutasConsentimientos } from './rutas/consentimientos.js';
import { rutasDelegaciones } from './rutas/delegaciones.js';
import { rutasCursos } from './rutas/cursos.js';
import { rutasPedidos } from './rutas/pedidos.js';
import { rutaWebhookStripe } from './rutas/stripeWebhook.js';
import { configuracionPagos } from './stripe.js';
import { configuracionAdmin } from './admin/sesion.js';
import { rutasAdmin } from './admin/rutas.js';
import { modoSms } from './sms.js';

// ─────────────────────────────────────────────────────────────────────────────
// Servidor ÚNICO de la app. Una pantalla = un archivo en src/rutas/.
// Para agregar la tuya: crea src/rutas/<tu-pantalla>.js (copia productos.js como modelo),
// impórtala arriba y móntala en la sección "PANTALLAS" de abajo. Nada más.
// ─────────────────────────────────────────────────────────────────────────────

const pool = crearPool();
const pagos = configuracionPagos();   // Stripe (ver src/stripe.js); sin STRIPE_SECRET_KEY los pagos quedan apagados
const admin = configuracionAdmin();   // sitio de administración (ver src/admin/); sin ADMIN_SESION_SECRETO queda apagado
const app = express();

app.disable('x-powered-by');
app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    // Sin esto, Safari convierte http://localhost en https y el sitio de administración no carga en desarrollo.
    directives: { 'upgrade-insecure-requests': process.env.NODE_ENV === 'production' ? [] : null },
  },
}));
// Detrás de un proxy (Render, Nginx...) pon TRUST_PROXY=1 para limitar por IP real.
if (process.env.TRUST_PROXY) app.set('trust proxy', Number(process.env.TRUST_PROXY));

// Fotos de los productos: lo que pongas en la carpeta "imagenes" se sirve en /img/nombre.jpg
// (va antes del limitador para que cargar el catálogo con sus fotos no gaste el cupo).
const carpetaImagenes = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'imagenes');
app.use('/img', express.static(carpetaImagenes, { maxAge: '1d', index: false, dotfiles: 'ignore' }));

// Sitio web de administración de pedidos: las páginas (HTML, CSS y JS) están en la carpeta "publico/admin" y
// se sirven en /admin. Va antes del limitador, igual que las imágenes. Los datos salen de /admin/api (más abajo).
const carpetaAdmin = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'publico', 'admin');
if (admin.activo) app.use('/admin', express.static(carpetaAdmin, { index: 'index.html', dotfiles: 'ignore', maxAge: 0 }));

// Aviso de Stripe ("pago recibido"). Va ANTES de express.json(): necesita el cuerpo sin convertir
// para comprobar la firma. No lleva el limitador general: la firma de Stripe es su protección.
if (pagos.stripe && pagos.webhookSecret) app.use('/stripe/webhook', rutaWebhookStripe(pool, pagos));

app.use(rateLimit({ windowMs: 60_000, limit: 60, standardHeaders: 'draft-7', legacyHeaders: false }));
app.use(express.json({ limit: '16kb' }));

// Comprobar que el servidor y la base responden.
app.get('/salud', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (error) {
    console.error('GET /salud falló:', error.code ?? error.message);
    res.status(503).json({ ok: false });
  }
});

// ── PANTALLAS ────────────────────────────────────────────────────────────────
app.use('/api/productos', rutasProductos(pool));                 // 6 · Productos con causa
app.use('/api/pedidos', rutasPedidos(pool, pagos));              // 6 · Productos con causa: comprar con Stripe
if (admin.activo) app.use('/admin/api', rutasAdmin(pool, pagos, admin));   // 6 · Productos con causa: administrar pedidos
app.use('/api/citas', rutasCitas(pool));                         // 5 · Citas
app.use('/api/llamadas', rutasLlamadas(pool));                   // Emergencia y llamada
// Cada alta de dispositivo escribe en la base: límite más estricto que el general.
app.use('/api/dispositivos',
  rateLimit({ windowMs: 60_000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false }),
  rutasDispositivos(pool));                                      // 5 · registro del dispositivo
// Cada envío puede costar un SMS: límite más estricto todavía.
app.use('/api/registro',
  rateLimit({ windowMs: 60_000, limit: 6, standardHeaders: 'draft-7', legacyHeaders: false }),
  rutasRegistro(pool));                                          // HU01 · registro con SMS
app.use('/api/consentimientos', rutasConsentimientos(pool));     // HU01 · permisos
app.use('/api/delegaciones', rutasDelegaciones(pool));           // HU11 · delegación según mi ubicación
app.use('/api/cursos', rutasCursos(pool));                       // HU14 · inscripción a capacitación
// ─────────────────────────────────────────────────────────────────────────────

app.use((_req, res) => res.status(404).json({ error: 'No encontrado' }));
app.use(manejadorDeErrores);

const puerto = Number(process.env.PORT ?? 3000);
app.listen(puerto, (error) => {
  // Express 5 entrega aquí el error si no pudo abrir el puerto (por ejemplo, otro backend ya lo usa).
  if (error) {
    console.error(error.code === 'EADDRINUSE'
      ? `El puerto ${puerto} ya está ocupado: probablemente otro backend sigue corriendo en otra Terminal. Ciérralo con Ctrl+C y vuelve a correr npm run dev.`
      : `No se pudo abrir el puerto ${puerto}: ${error.code ?? error.message}`);
    process.exit(1);
  }
  console.log(`API escuchando en el puerto ${puerto}`);
  if (!pagos.stripe) {
    console.log('Pagos con Stripe APAGADOS: falta STRIPE_SECRET_KEY en el .env (ver backend/README.md).');
  } else {
    console.log(`Pagos con Stripe en modo ${pagos.modo}, envío $${pagos.envioMXN} MXN.`);
    if (!pagos.webhookSecret) {
      console.warn('AVISO: falta STRIPE_WEBHOOK_SECRET; sin él los pedidos nunca pasarán a "pagado".');
    }
    if (pagos.modo === 'prueba' && process.env.NODE_ENV === 'production') {
      console.warn('AVISO: producción con llaves de PRUEBA de Stripe (sk_test_): no se cobrará dinero real.');
    }
  }
  if (!admin.activo) {
    console.log('Sitio de administración APAGADO: falta ADMIN_SESION_SECRETO en el .env (ver backend/README.md).');
  } else {
    console.log(`Sitio de administración en http://localhost:${puerto}/admin/`);
  }
  if (modoSms() === 'consola') {
    console.log('SMS en modo consola: los códigos de verificación salen aquí, no se envía nada.');
  } else {
    const respaldo = process.env.SMS_RESPALDO_CONSOLA === 'si' && process.env.NODE_ENV !== 'production';
    console.log(`SMS en modo ${modoSms()}${respaldo ? ' (si el envío falla, el código sale aquí)' : ''}.`);
  }
});
