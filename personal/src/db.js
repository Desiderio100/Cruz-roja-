import fs from 'node:fs';
import mysql from 'mysql2/promise';

function requerida(nombre) {
  const valor = process.env[nombre];
  if (!valor) throw new Error(`Falta la variable de entorno ${nombre} (revisa tu archivo .env)`);
  return valor;
}

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
    connectionLimit: 5,
    connectTimeout: 10_000,
    timezone: 'Z',
    decimalNumbers: true,
  });
}

export async function llamar(pool, procedimiento, parametros = []) {
  const marcas = parametros.map(() => '?').join(', ');
  const [resultado] = await pool.query(`CALL ${procedimiento}(${marcas})`, parametros);
  return Array.isArray(resultado) && Array.isArray(resultado[0]) ? resultado[0] : [];
}
