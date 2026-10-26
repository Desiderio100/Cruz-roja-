import { Router } from 'express';
import { ErrorHttp } from '../errores.js';

/**
 * HU01 — Permisos (RNF08).   (Antes POST /consentimientos de backend/sms_backend.py.)
 *   POST /api/consentimientos   { permiso, aceptado }   header X-Dispositivo-Id
 * Cada respuesta es un registro nuevo, con la versión vigente del aviso de privacidad.
 * No se edita ni se borra: si la persona cambia de opinión, se agrega otro.
 */

const PERMISOS = ['ubicacion', 'microfono', 'camara', 'notificaciones'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function rutasConsentimientos(pool) {
  const router = Router();

  router.post('/', async (req, res) => {
    const dispositivo = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
    if (!UUID.test(dispositivo)) throw new ErrorHttp(401, 'falta el dispositivo');

    const { permiso, aceptado } = req.body || {};
    if (!PERMISOS.includes(permiso) || typeof aceptado !== 'boolean') {
      throw new ErrorHttp(400, 'datos no válidos');
    }

    let resultado;
    try {
      [resultado] = await pool.execute(
        `INSERT INTO consentimiento (dispositivo_id, permiso, aceptado, version_aviso)
         SELECT ?, ?, ?, version FROM aviso_privacidad ORDER BY publicado_en DESC LIMIT 1`,
        [dispositivo, permiso, aceptado ? 1 : 0]
      );
    } catch (error) {
      // La llave foránea falla si el dispositivo no existe: la app se registra y reintenta.
      if (error.code === 'ER_NO_REFERENCED_ROW_2') throw new ErrorHttp(400, 'dispositivo no registrado');
      throw error;
    }
    if (resultado.affectedRows === 0) throw new ErrorHttp(503, 'no hay un aviso de privacidad publicado');
    res.status(201).json({ ok: true });
  });

  return router;
}
