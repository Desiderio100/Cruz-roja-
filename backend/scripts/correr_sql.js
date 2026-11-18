// Corre un script de db/ en la base del .env con una cuenta que SÍ puede cambiar tablas.
//   npm run db:correr -- ../db/12_cursos_y_centros.sql
//
// La cuenta del .env (cruzroja_app) no puede agregar columnas a propósito, así que el script
// pide otro usuario (avnadmin o tu usuario dev) y su contraseña. La contraseña no se muestra al
// escribirla, no se guarda y no se imprime. Usa el mismo servidor, base y certificado del .env.
// Sirve para scripts sin DELIMITER (sin procedimientos ni disparadores).
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import mysql from 'mysql2/promise';

function preguntar(texto) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolver) => rl.question(texto, (r) => { rl.close(); resolver(r.trim()); }));
}

/** Lee la contraseña sin mostrarla en pantalla. */
function preguntarOculto(texto) {
  return new Promise((resolver) => {
    const entrada = process.stdin;
    process.stdout.write(texto);
    entrada.setRawMode(true);
    entrada.resume();
    entrada.setEncoding('utf8');
    let valor = '';
    const terminar = () => {
      entrada.setRawMode(false);
      entrada.pause();
      entrada.off('data', alTeclear);
      process.stdout.write('\n');
    };
    function alTeclear(trozo) {
      for (const letra of trozo) {
        if (letra === '\r' || letra === '\n') { terminar(); return resolver(valor); }
        if (letra === '\u0003') { terminar(); process.exit(130); }        // Ctrl+C
        if (letra === '\u007f' || letra === '\b') { valor = valor.slice(0, -1); continue; }
        valor += letra;
      }
    }
    entrada.on('data', alTeclear);
  });
}

const archivo = process.argv[2];
if (!archivo || !fs.existsSync(archivo)) {
  console.error('Uso: npm run db:correr -- ../db/<archivo>.sql');
  process.exit(1);
}
if (!process.stdin.isTTY) {
  console.error('Córrelo en una Terminal: necesita preguntarte la contraseña.');
  process.exit(1);
}
const sql = fs.readFileSync(archivo, 'utf8');
if (/^\s*DELIMITER\b/im.test(sql)) {
  console.error('Este script usa DELIMITER (procedimientos o disparadores): córrelo en MySQL Workbench.');
  process.exit(1);
}

console.log(`Script: ${path.basename(archivo)}  ·  servidor: ${process.env.DB_HOST}`);
const usuario = await preguntar('Usuario que puede cambiar tablas (avnadmin o tu dev_…): ');
const contrasena = await preguntarOculto(`Contraseña de ${usuario}: `);

let conexion;
try {
  conexion = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT ?? 3306),
    user: usuario,
    password: contrasena,
    database: process.env.DB_NAME ?? 'cruzroja',
    ssl: process.env.DB_CA_PATH
      ? { ca: fs.readFileSync(process.env.DB_CA_PATH), rejectUnauthorized: true }
      : undefined,
    multipleStatements: true,
    timezone: 'Z',
    dateStrings: true,
  });
  const [resultados] = await conexion.query(sql);
  // Muestra las tablas que el script deja al final para revisar el resultado.
  const tablas = (Array.isArray(resultados) ? resultados : [resultados]).filter((r) => Array.isArray(r));
  for (const tabla of tablas) console.table(tabla);
  console.log('Listo.');
} catch (error) {
  console.error('No se pudo correr el script:', error.sqlMessage ?? error.message);
  process.exitCode = 1;
} finally {
  await conexion?.end();
}
