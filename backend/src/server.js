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
import { modoSms } from './sms.js';

// ─────────────────────────────────────────────────────────────────────────────
// Servidor ÚNICO de la app. Una pantalla = un archivo en src/rutas/.
// Para agregar la tuya: crea src/rutas/<tu-pantalla>.js (copia productos.js como modelo),
// impórtala arriba y móntala en la sección "PANTALLAS" de abajo. Nada más.
// ─────────────────────────────────────────────────────────────────────────────

const pool = crearPool();
const app = express();

app.disable('x-powered-by');
app.use(helmet());
// Detrás de un proxy (Render, Nginx...) pon TRUST_PROXY=1 para limitar por IP real.
if (process.env.TRUST_PROXY) app.set('trust proxy', Number(process.env.TRUST_PROXY));

// Fotos de los productos: lo que pongas en la carpeta "imagenes" se sirve en /img/nombre.jpg
// (va antes del limitador para que cargar el catálogo con sus fotos no gaste el cupo).
const carpetaImagenes = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'imagenes');
app.use('/img', express.static(carpetaImagenes, { maxAge: '1d', index: false, dotfiles: 'ignore' }));

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
// ─────────────────────────────────────────────────────────────────────────────

app.use((_req, res) => res.status(404).json({ error: 'No encontrado' }));
app.use(manejadorDeErrores);

const puerto = Number(process.env.PORT ?? 3000);
app.listen(puerto, () => {
  console.log(`API escuchando en el puerto ${puerto}`);
  if (modoSms() === 'consola') {
    console.log('SMS en modo consola: los códigos de verificación salen aquí, no se envía nada.');
  } else {
    const respaldo = process.env.SMS_RESPALDO_CONSOLA === 'si' && process.env.NODE_ENV !== 'production';
    console.log(`SMS en modo ${modoSms()}${respaldo ? ' (si el envío falla, el código sale aquí)' : ''}.`);
  }
});
