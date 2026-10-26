/** Error con código HTTP y un mensaje seguro para mostrar al usuario. */
export class ErrorHttp extends Error {
  constructor(estado, mensaje) {
    super(mensaje);
    this.estado = estado;
  }
}

/**
 * Manejador de errores único (se monta al final en server.js).
 * Los procedimientos de la base avisan con SIGNAL:
 *   22023 = datos inválidos (400)
 *   45000 = regla de negocio: "no existe" (404) o conflicto, como un horario ocupado (409)
 * Esos mensajes los escribimos nosotros y son seguros de mostrar. Cualquier otro error
 * (conexión caída, SQL mal escrito...) se queda en el log del servidor y el cliente solo
 * recibe un mensaje genérico.
 */
export function manejadorDeErrores(err, _req, res, _next) {
  if (err.estado) return res.status(err.estado).json({ error: err.message });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON no válido' });
  if (err.sqlState === '22023') return res.status(400).json({ error: err.sqlMessage });
  if (err.sqlState === '45000') {
    const estado = err.sqlMessage.includes('no existe') ? 404 : 409;
    return res.status(estado).json({ error: err.sqlMessage });
  }
  console.error('Error no controlado:', err.code ?? err.message);
  res.status(500).json({ error: 'error del servidor' });
}
