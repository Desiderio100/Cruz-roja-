// Crea la línea de SQL para dar de alta a una persona de Cruz Roja en el sitio de administración.
//   npm run crear:personal
//
// Te pregunta usuario, rol y contraseña, calcula el hash (la contraseña NO se guarda ni se
// imprime) y escribe un INSERT para que lo corras en MySQL Workbench conectado como avnadmin
// o con tu usuario dev. No toca la base: la cuenta de la app no puede crear personal a propósito.
import bcrypt from 'bcryptjs';

// ── Lector de líneas propio: la contraseña no se muestra al escribirla ───────
const esTTY = Boolean(process.stdin.isTTY);
const cola = [];
let esperando = null;
let terminoLaEntrada = false;
let oculto = false;
let escrito = '';
let pendiente = '';

function entregar(linea) {
  if (esperando) { const r = esperando; esperando = null; r(linea); } else cola.push(linea);
}

if (esTTY) process.stdin.setRawMode(true);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (trozo) => {
  if (!esTTY) { // entrada canalizada (por ejemplo, desde un archivo): se lee por líneas
    pendiente += trozo;
    let i;
    while ((i = pendiente.indexOf('\n')) >= 0) {
      entregar(pendiente.slice(0, i).replace(/\r$/, ''));
      pendiente = pendiente.slice(i + 1);
    }
    return;
  }
  for (const c of trozo.replace(/\u001b\[[0-9;]*[A-Za-z]/g, '')) { // sin teclas de flecha
    if (c === '\u0003') { process.stdout.write('\n'); process.exit(130); } // Ctrl+C
    if (c === '\r' || c === '\n') { process.stdout.write('\n'); entregar(escrito); escrito = ''; }
    else if (c === '\u007f' || c === '\b') {
      if (escrito.length > 0) { escrito = escrito.slice(0, -1); if (!oculto) process.stdout.write('\b \b'); }
    } else if (c >= ' ') { escrito += c; if (!oculto) process.stdout.write(c); }
  }
});
process.stdin.on('end', () => {
  terminoLaEntrada = true;
  if (esperando) { const r = esperando; esperando = null; r(null); }
});
process.on('exit', () => { if (esTTY) { try { process.stdin.setRawMode(false); } catch { /* ya cerrado */ } } });

async function preguntar(texto, valorPorDefecto = '', { secreta = false } = {}) {
  process.stdout.write(valorPorDefecto ? `${texto} [${valorPorDefecto}]: ` : `${texto}: `);
  oculto = secreta;
  let linea;
  if (cola.length) linea = cola.shift();
  else if (terminoLaEntrada) linea = null;
  else linea = await new Promise((resolver) => { esperando = resolver; });
  oculto = false;
  if (linea === null) {
    console.log('\nSe cerró la entrada antes de terminar. No se creó nada.');
    process.exit(1);
  }
  return secreta ? linea : (linea.trim() || valorPorDefecto);
}

// ── Preguntas ────────────────────────────────────────────────────────────────
console.log('Alta de personal para el sitio de administración de pedidos.\n');

let usuario;
for (;;) {
  usuario = (await preguntar('Usuario (minúsculas, sin espacios; por ejemplo ana.lopez)')).toLowerCase();
  if (/^[a-z0-9._-]{3,60}$/.test(usuario)) break;
  console.log('  Usa de 3 a 60 caracteres: letras minúsculas, números, punto, guion o guion bajo.');
}

let rol;
for (;;) {
  rol = (await preguntar('Rol: "operador" (ve pedidos y avanza el envío) o "administrativo" (además reembolsa)', 'operador')).toLowerCase();
  if (['operador', 'administrativo'].includes(rol)) break;
  console.log('  Escribe operador o administrativo.');
}

let delegacion;
for (;;) {
  delegacion = await preguntar('Número (id) de la delegación a la que pertenece (en Workbench: SELECT id, nombre FROM delegacion;)', '1');
  if (/^[0-9]{1,9}$/.test(delegacion)) break;
  console.log('  Escribe solo el número.');
}

let contrasena;
for (;;) {
  contrasena = await preguntar('Contraseña (mínimo 12 caracteres)', '', { secreta: true });
  if (contrasena.length < 12) { console.log('  Muy corta: usa al menos 12 caracteres.'); continue; }
  if (Buffer.byteLength(contrasena) > 72) { console.log('  Muy larga: el máximo es 72 bytes.'); continue; }
  const otra = await preguntar('Repite la contraseña', '', { secreta: true });
  if (otra === contrasena) break;
  console.log('  No coinciden. Intenta de nuevo.');
}

const hash = await bcrypt.hash(contrasena, 12);

console.log(`
Copia y corre esto en MySQL Workbench (conectado como avnadmin o con tu usuario dev):

USE cruzroja;
INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
VALUES (${delegacion}, '${usuario}', '${hash}', '${rol}');

Después entra a /admin con el usuario "${usuario}" y la contraseña que acabas de escribir.
Para dar de baja a alguien:  UPDATE personal SET activo = 0 WHERE usuario = '${usuario}';
`);
process.stdin.pause();
