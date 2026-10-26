import fs from 'node:fs';
import mysql from 'mysql2/promise';

function requerida(nombre) {
  const valor = process.env[nombre];
  if (!valor) throw new Error(`Falta la variable de entorno ${nombre} (revisa tu archivo .env)`);
  return valor;
}

/**
 * Pool de conexiones a MySQL. UNO SOLO para toda la API: cada pantalla recibe este mismo
 * pool desde server.js y no abre conexiones propias.
 * En producción debe usar la cuenta restringida cruzroja_app, nunca avnadmin ni una dev_*.
 */
export function crearPool() {
  const rutaCa = process.env.DB_CA_PATH;
  if (!rutaCa && process.env.NODE_ENV === 'production') {
    throw new Error('En producción la conexión a la base debe usar TLS: define DB_CA_PATH');
  }

  return mysql.createPool({
    host: requerida('DB_HOST'),
    port: Number(process.env.DB_PORT ?? 3306),
    user: requerida('DB_USER'),
    password: requerida('DB_PASSWORD'),
    database: process.env.DB_NAME ?? 'cruzroja',
    ssl: rutaCa ? { ca: fs.readFileSync(rutaCa), rejectUnauthorized: true } : undefined,
    connectionLimit: 10,     // el plan gratuito de Aiven permite 76 conexiones en total
    connectTimeout: 10_000,
    timezone: 'Z',           // las fechas se guardan en UTC y se entregan como ISO con "Z"
    decimalNumbers: true,    // DECIMAL llega como número (precio_mxn), no como texto
  });
}

/**
 * Llama a un procedimiento almacenado (CALL ...) y devuelve las filas de su primer SELECT.
 * Si el procedimiento no devuelve filas (por ejemplo, cancelar), regresa [].
 */
export async function llamar(pool, sql, parametros) {
  const [resultado] = await pool.query(sql, parametros);
  return Array.isArray(resultado[0]) ? resultado[0] : [];
}
