import { createHmac, timingSafeEqual } from 'node:crypto';
import { ErrorHttp } from '../errores.js';

/**
 * Sesión del personal de Cruz Roja en el sitio de administración.
 *
 * La sesión vive en una cookie firmada (HMAC-SHA256) con ADMIN_SESION_SECRETO:
 *   - HttpOnly: el JavaScript de la página no puede leerla (si alguien lograra meter código, no la roba).
 *   - SameSite=Strict: otro sitio no puede hacer que el navegador la mande (protege contra CSRF).
 *   - Secure: solo por HTTPS (se activa con NODE_ENV=production).
 *   - Dura 8 horas y luego hay que entrar de nuevo.
 * En CADA petición se vuelve a leer la cuenta en la base: si dan de baja a alguien o bloquean su
 * cuenta, pierde el acceso al instante aunque su cookie todavía no haya vencido.
 *
 * Sin ADMIN_SESION_SECRETO el sitio de administración queda apagado (el resto de la API sigue igual).
 */

const NOMBRE_COOKIE = 'sesion_admin';
const VERSION = 'v1';

/** Lee la configuración del sitio de administración desde variables de entorno. */
export function configuracionAdmin() {
  const secreto = (process.env.ADMIN_SESION_SECRETO || '').trim();
  if (!secreto) return { activo: false };
  if (secreto.length < 32) {
    throw new Error('ADMIN_SESION_SECRETO debe tener al menos 32 caracteres (ver backend/.env.example)');
  }
  return {
    activo: true,
    secreto,
    duracionMs: 8 * 60 * 60 * 1000,
    cookieSegura: process.env.NODE_ENV === 'production',
    limiteLoginPorQuinceMin: 10,
    panelPersonal: direccionPanelPersonal(process.env.PANEL_PERSONAL_URL),
  };
}

/**
 * Dirección del panel de llamadas y citas (personal/CruzRoja.Personal), para mostrar un enlace en la
 * barra del sitio de pedidos. Vacía = sin enlace. Solo se acepta http(s): nada de "javascript:" ni rutas raras.
 */
export function direccionPanelPersonal(texto) {
  const valor = (texto || '').trim();
  if (!valor) return null;
  let url;
  try {
    url = new URL(valor);
  } catch {
    throw new Error('PANEL_PERSONAL_URL no es una dirección válida (ejemplo: http://localhost:5050/)');
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('PANEL_PERSONAL_URL debe empezar con http:// o https:// (ejemplo: http://localhost:5050/)');
  }
  return url.href;
}

const aBase64Url = (buffer) => Buffer.from(buffer).toString('base64url');

function firma(secreto, texto) {
  return createHmac('sha256', secreto).update(texto).digest();
}

/** Crea el valor de la cookie para una persona. */
export function firmarSesion(config, personalId, ahora = Date.now()) {
  const carga = aBase64Url(JSON.stringify({ p: personalId, e: ahora + config.duracionMs }));
  const cuerpo = `${VERSION}.${carga}`;
  return `${cuerpo}.${aBase64Url(firma(config.secreto, cuerpo))}`;
}

/** Devuelve el id de la persona si la cookie es auténtica y no ha vencido; si no, null. */
export function leerSesion(config, valor, ahora = Date.now()) {
  if (typeof valor !== 'string' || valor.length > 512) return null;
  const partes = valor.split('.');
  if (partes.length !== 3 || partes[0] !== VERSION) return null;
  const esperada = firma(config.secreto, `${partes[0]}.${partes[1]}`);
  let recibida;
  try { recibida = Buffer.from(partes[2], 'base64url'); } catch { return null; }
  if (recibida.length !== esperada.length || !timingSafeEqual(recibida, esperada)) return null;
  try {
    const { p, e } = JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8'));
    if (typeof p !== 'string' || typeof e !== 'number' || e <= ahora) return null;
    return p;
  } catch {
    return null;
  }
}

/** Lee una cookie de la petición (sin dependencias extra). */
export function leerCookie(req, nombre = NOMBRE_COOKIE) {
  const encabezado = req.get('cookie');
  if (!encabezado) return null;
  for (const trozo of encabezado.split(';')) {
    const i = trozo.indexOf('=');
    if (i > 0 && trozo.slice(0, i).trim() === nombre) return trozo.slice(i + 1).trim();
  }
  return null;
}

export function ponerCookieSesion(res, config, personalId) {
  const atributos = [
    `${NOMBRE_COOKIE}=${firmarSesion(config, personalId)}`,
    'Path=/admin', 'HttpOnly', 'SameSite=Strict', `Max-Age=${Math.floor(config.duracionMs / 1000)}`,
  ];
  if (config.cookieSegura) atributos.push('Secure');
  res.append('Set-Cookie', atributos.join('; '));
}

export function quitarCookieSesion(res, config) {
  const atributos = [`${NOMBRE_COOKIE}=`, 'Path=/admin', 'HttpOnly', 'SameSite=Strict', 'Max-Age=0'];
  if (config.cookieSegura) atributos.push('Secure');
  res.append('Set-Cookie', atributos.join('; '));
}

/**
 * Middleware: exige una sesión válida y deja la persona en req.personal = { id, usuario, rol }.
 * Vuelve a leer la cuenta en la base en cada petición (ver arriba).
 */
export function exigirSesion(pool, config) {
  return async (req, _res, next) => {
    const id = leerSesion(config, leerCookie(req));
    if (!id) throw new ErrorHttp(401, 'Inicia sesión para continuar');
    const [filas] = await pool.query(
      'SELECT id, usuario, rol, activo, bloqueado_hasta FROM personal WHERE id = ?', [id]);
    const p = filas[0];
    const bloqueada = p && p.bloqueado_hasta && new Date(p.bloqueado_hasta) > new Date();
    if (!p || !p.activo || bloqueada) throw new ErrorHttp(401, 'Inicia sesión para continuar');
    req.personal = { id: p.id, usuario: p.usuario, rol: p.rol };
    next();
  };
}

/** Middleware: solo deja pasar a las cuentas con alguno de estos roles. */
export function exigirRol(...roles) {
  return (req, _res, next) => {
    if (!roles.includes(req.personal?.rol)) {
      throw new ErrorHttp(403, 'Tu cuenta no tiene permiso para hacer esto');
    }
    next();
  };
}

/**
 * Middleware contra CSRF (segunda capa, además de SameSite=Strict): en peticiones que cambian algo,
 * si el navegador manda el encabezado Origin, tiene que ser este mismo sitio.
 */
export function mismoOrigen(req, _res, next) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) return next();
  const origen = req.get('origin');
  if (origen) {
    let host = null;
    try { host = new URL(origen).host; } catch { /* queda null */ }
    if (host !== req.get('host')) throw new ErrorHttp(403, 'Petición no permitida');
  }
  next();
}
