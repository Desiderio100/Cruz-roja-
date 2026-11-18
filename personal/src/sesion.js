import { randomBytes, timingSafeEqual } from 'node:crypto';
import cookieSession from 'cookie-session';

const VIGENCIA_INACTIVO_MS = 30 * 24 * 60 * 60 * 1000;
const REFRESCO_MS = 10 * 60 * 1000;
const revocadas = new Map();

function secreto() {
  const valor = process.env.SESION_SECRETO;
  if (valor) return valor;
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Falta la variable de entorno SESION_SECRETO');
  }
  console.warn('SESION_SECRETO no está definido: se usa uno temporal y las sesiones se pierden al reiniciar.');
  return randomBytes(32).toString('base64url');
}

export function middlewareSesion() {
  return cookieSession({
    name: 'cruzroja.sesion',
    keys: [secreto()],
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    signed: true,
  });
}

export function prepararSesion(req, _res, next) {
  const ahora = Date.now();
  const s = req.session;
  if (s.usuario && (!s.visto || ahora - s.visto > VIGENCIA_INACTIVO_MS || revocadas.has(s.sid))) {
    req.session = null;
    req.session = {};
  }
  if (req.session.usuario && ahora - req.session.visto > REFRESCO_MS) req.session.visto = ahora;
  if (!req.session.csrf) req.session.csrf = randomBytes(24).toString('base64url');
  next();
}

export function iniciarSesion(req, usuario) {
  req.session = {
    usuario,
    sid: randomBytes(16).toString('base64url'),
    visto: Date.now(),
    csrf: randomBytes(24).toString('base64url'),
  };
}

export function cerrarSesion(req) {
  const ahora = Date.now();
  for (const [sid, momento] of revocadas) {
    if (ahora - momento > VIGENCIA_INACTIVO_MS) revocadas.delete(sid);
  }
  if (req.session?.sid) revocadas.set(req.session.sid, ahora);
  req.session = null;
}

function iguales(a, b) {
  const x = Buffer.from(String(a ?? ''));
  const y = Buffer.from(String(b ?? ''));
  return x.length === y.length && timingSafeEqual(x, y);
}

export function validarCsrf(req, res, next) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) return next();
  const recibido = req.get('requestverificationtoken') ?? req.body?._token;
  if (iguales(recibido, req.session?.csrf)) return next();
  if (req.headers['x-requested-with'] !== undefined) return res.status(400).json({ error: 'Solicitud no válida' });
  res.status(400).type('text/plain').send('Solicitud no válida');
}

export function esDeScript(req) {
  return req.headers['x-requested-with'] !== undefined;
}

export function inicioDelRol(usuario) {
  return usuario?.rol === 'operador' ? '/Llamadas' : '/Citas';
}

export function requiereRol(rol) {
  return (req, res, next) => {
    const usuario = req.session?.usuario;
    if (!usuario) {
      if (esDeScript(req)) return res.status(401).json({ error: 'Sesión no iniciada' });
      return res.redirect('/Acceso');
    }
    if (usuario.rol !== rol) {
      if (esDeScript(req)) return res.status(403).json({ error: 'Sin permiso' });
      return res.redirect(inicioDelRol(usuario));
    }
    next();
  };
}
