import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import helmet from 'helmet';
import { crearPool } from './db.js';
import { manejadorDeErrores } from './errores.js';
import { crearRepositorio } from './repositorio.js';
import { middlewareSesion, prepararSesion, validarCsrf } from './sesion.js';
import { rutasAcceso } from './rutas/acceso.js';
import { rutasLlamadas } from './rutas/llamadas.js';
import { rutasCitas } from './rutas/citas.js';
import { origenesLivekit } from './livekit.js';

const enProduccion = process.env.NODE_ENV === 'production';
const origenesVivo = origenesLivekit();
const config = {
  maximoIntentos: Number(process.env.MAXIMO_INTENTOS ?? 5),
  bloqueoMinutos: Number(process.env.BLOQUEO_MINUTOS ?? 3),
  perdidasHoras: Number(process.env.PERDIDAS_HORAS ?? 24),
};

const pool = crearPool();
const repositorio = crearRepositorio(pool);
const app = express();

app.disable('x-powered-by');
if (process.env.TRUST_PROXY) app.set('trust proxy', Number(process.env.TRUST_PROXY));

app.use(
  helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        'connect-src': ["'self'", ...origenesVivo],
        'media-src': ["'self'", 'blob:'],
        'worker-src': ["'self'", 'blob:'],
        ...(enProduccion ? {} : { 'upgrade-insecure-requests': null }),
      },
    },
  }),
);

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const carpetaPublica = path.join(raiz, 'publico');
app.get('/js/livekit-client.umd.js', (_req, res) => {
  res.sendFile(path.join(raiz, 'node_modules', 'livekit-client', 'dist', 'livekit-client.umd.js'), { dotfiles: 'deny' });
});
app.use(express.static(carpetaPublica, { index: false, dotfiles: 'ignore' }));

app.use((_req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

app.get('/salud', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (error) {
    console.error('GET /salud falló:', error.code ?? error.message);
    res.status(503).json({ ok: false });
  }
});

app.use(express.urlencoded({ extended: false, limit: '4kb' }));
app.use(express.json({ limit: '16kb' }));
app.use(middlewareSesion());
app.use(prepararSesion);
app.use(validarCsrf);

app.use(rutasAcceso(repositorio, config));
app.use(rutasLlamadas(repositorio, config));
app.use(rutasCitas(repositorio));

app.use((_req, res) => res.status(404).type('text/plain').send('No encontrado'));
app.use(manejadorDeErrores);

const puerto = Number(process.env.PORT ?? 4000);
app.listen(puerto, () => {
  console.log(`Sitio del personal escuchando en el puerto ${puerto}`);
});
