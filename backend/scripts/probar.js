// Prueba rápida y de SOLO LECTURA de la API que está corriendo (no escribe nada en la base).
//   npm run probar                       -> prueba http://localhost:3000
//   npm run probar -- http://192.168.1.20:3000
const base = (process.argv[2] ?? 'http://localhost:3000').replace(/\/$/, '');

// Próximo día entre semana, en fecha local y con la zona horaria de esta computadora.
const dia = new Date();
do { dia.setDate(dia.getDate() + 1); } while ([0, 6].includes(dia.getDay()));
const dosDigitos = (n) => String(n).padStart(2, '0');
const fecha = `${dia.getFullYear()}-${dosDigitos(dia.getMonth() + 1)}-${dosDigitos(dia.getDate())}`;
const minutos = -dia.getTimezoneOffset();
const zona = `${minutos < 0 ? '-' : '+'}${dosDigitos(Math.floor(Math.abs(minutos) / 60))}:${dosDigitos(Math.abs(minutos) % 60)}`;

const pruebas = [
  ['Servidor y base de datos', '/salud', (j) => j.ok === true, () => ''],
  ['Pantalla 6 · Productos con causa', '/api/productos', (j) => Array.isArray(j.productos),
    (j) => `${j.productos.length} productos`],
  ['Pantalla 5 · Horarios de citas',
    `/api/citas/horarios?delegacion_id=2&servicio=nutricion&fecha=${fecha}&zona=${encodeURIComponent(zona)}`,
    (j) => Array.isArray(j), (j) => `${j.length} horarios el ${fecha}`],
];

let fallos = 0;
for (const [nombre, ruta, valido, detalle] of pruebas) {
  try {
    const r = await fetch(base + ruta);
    const j = await r.json().catch(() => ({}));
    if (r.ok && valido(j)) console.log(`✅ ${nombre}  ${detalle(j)}`);
    else { fallos++; console.log(`❌ ${nombre}  (HTTP ${r.status}) ${JSON.stringify(j).slice(0, 120)}`); }
  } catch (e) {
    fallos++; console.log(`❌ ${nombre}  no se pudo conectar a ${base}  (${e.cause?.code ?? e.message})`);
  }
}
process.exit(fallos ? 1 : 0);
