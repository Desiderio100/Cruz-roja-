import { Router } from 'express';
import { llamar } from '../db.js';

/**
 * Registro provisional de dispositivos (hasta que la pantalla 1 tenga el suyo).   Dueño: Luis
 *   POST /api/dispositivos   crea un dispositivo y devuelve su id
 */
export function rutasDispositivos(pool) {
  const router = Router();

  router.post('/', async (req, res) => {
    const telefono = (req.body && req.body.telefono) || null;
    const filas = await llamar(pool, 'CALL dispositivo_registrar(?)', [telefono]);
    res.status(201).json(filas[0]);
  });

  return router;
}
