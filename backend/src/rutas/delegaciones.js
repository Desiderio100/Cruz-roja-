import { Router } from 'express';
import { z } from 'zod';
import { llamar } from '../db.js';
import { ErrorHttp } from '../errores.js';

/**
 * HU11 — Delegación según mi ubicación (RF17, RF18).   Dueño: Desiderio
 *   GET /api/delegaciones                directorio de delegaciones activas con su versión
 *   GET /api/delegaciones?version=N      si la app ya tiene la versión N, solo responde { version, sin_cambios: true }
 *   GET /api/delegaciones/cercana?lat=&lon=   la delegación activa más cercana a un punto
 *
 * La app guarda el directorio en el teléfono para usarlo sin internet. La versión sale de
 * `directorio_meta`, que los disparadores de `delegacion` suben con cada alta, cambio o baja.
 * Ninguna ruta pide el dispositivo: el directorio es público (son los teléfonos del CECOM).
 */

const consultaCercana = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lon: z.coerce.number().min(-180).max(180),
});

export function rutasDelegaciones(pool) {
  const router = Router();

  router.get('/', async (req, res) => {
    const [[meta]] = await pool.query('SELECT version FROM directorio_meta WHERE id = 1');
    const version = meta?.version ?? 0;
    res.set('Cache-Control', 'no-cache');

    if (req.query.version !== undefined && Number(req.query.version) === version) {
      return res.json({ version, sin_cambios: true });
    }

    // direccion y referencia llegan con db/12_cursos_y_centros.sql; sin ese script se omiten.
    const consulta = (extra) => pool.query(
      `SELECT id, nombre, telefono_cecom AS telefono,
              CAST(latitud AS DOUBLE) AS latitud, CAST(longitud AS DOUBLE) AS longitud, estado ${extra}
         FROM delegacion
        WHERE activa = 1
        ORDER BY nombre`
    );
    let filas;
    try {
      [filas] = await consulta(', direccion, referencia');
    } catch (error) {
      if (error.code !== 'ER_BAD_FIELD_ERROR') throw error;
      [filas] = await consulta('');
    }
    res.json({ version, delegaciones: filas });
  });

  router.get('/cercana', async (req, res) => {
    const consulta = consultaCercana.safeParse(req.query);
    if (!consulta.success) throw new ErrorHttp(400, 'coordenadas no válidas');
    const filas = await llamar(pool, 'CALL delegacion_mas_cercana(?, ?)', [consulta.data.lat, consulta.data.lon]);
    if (filas.length === 0) throw new ErrorHttp(404, 'no hay delegaciones activas');
    const { id, nombre, telefono_cecom: telefono, distancia_km } = filas[0];
    res.json({ id, nombre, telefono, distancia_km: Math.round(distancia_km * 10) / 10 });
  });

  return router;
}
