import { Router } from 'express';

/**
 * Pantalla 6 — Productos con causa (RF28).   Dueño: Sebastián
 *   GET /api/productos   catálogo público (no pide sesión)
 */
export function rutasProductos(pool) {
  const router = Router();

  router.get('/', async (_req, res) => {
    try {
      const [filas] = await pool.query(
        `SELECT id, nombre, precio_mxn, causa, imagen_url, enlace_compra
           FROM producto
          WHERE activo = 1
          ORDER BY id`
      );
      // La compra ocurre fuera de la app: solo se entregan enlaces https.
      const productos = filas.filter((p) => p.enlace_compra.startsWith('https://'));
      res.set('Cache-Control', 'public, max-age=60');
      res.json({ productos });
    } catch (error) {
      console.error('GET /api/productos falló:', error.code ?? error.message); // el detalle se queda en el servidor
      res.status(500).json({ error: 'No se pudo consultar el catálogo' });
    }
  });

  return router;
}
