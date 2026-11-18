export class ErrorHttp extends Error {
  constructor(estado, mensaje) {
    super(mensaje);
    this.estado = estado;
  }
}

export function manejadorDeErrores(err, req, res, _next) {
  const deScript = req.headers['x-requested-with'] !== undefined;
  let estado = 500;
  let mensaje = 'Error del servidor';

  if (err.estado) {
    estado = err.estado;
    mensaje = err.message;
  } else if (err.type === 'entity.parse.failed') {
    estado = 400;
    mensaje = 'JSON no válido';
  } else if (err.sqlState === '22023' || err.sqlState === '45000') {
    estado = 400;
    mensaje = err.sqlMessage;
  } else {
    console.error('Error no controlado:', err.code ?? err.message);
  }

  if (res.headersSent) return;
  if (deScript || req.method !== 'GET') return res.status(estado).json({ error: mensaje });
  res.status(estado).type('text/plain').send(mensaje);
}
