const ZONA = process.env.ZONA_HORARIA || 'America/Mexico_City';

const formato = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONA,
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

function partes(instante) {
  const p = {};
  for (const { type, value } of formato.formatToParts(instante)) p[type] = value;
  return p;
}

function aTexto(anio, mes, dia) {
  return `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

export function hoy() {
  const p = partes(new Date());
  return aTexto(p.year, p.month, p.day);
}

export function ayer() {
  const [a, m, d] = hoy().split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d - 1));
  return aTexto(f.getUTCFullYear(), f.getUTCMonth() + 1, f.getUTCDate());
}

export function aLocal(fecha) {
  const p = partes(fecha);
  return { dia: aTexto(p.year, p.month, p.day), hora: `${p.hour}:${p.minute}`, diaMes: `${p.day}/${p.month}` };
}

export function desfase(fechaTexto) {
  const [a, m, d] = fechaTexto.split('-').map(Number);
  const mediodia = Date.UTC(a, m - 1, d, 12);
  const p = partes(new Date(mediodia));
  const local = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const minutos = Math.round((local - mediodia) / 60000);
  const signo = minutos < 0 ? '-' : '+';
  const abs = Math.abs(minutos);
  return `${signo}${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
}

export function fechaValida(texto) {
  if (typeof texto !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(texto)) return false;
  const [a, m, d] = texto.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d));
  return f.getUTCFullYear() === a && f.getUTCMonth() === m - 1 && f.getUTCDate() === d;
}

export function fechaEnPalabras(fechaTexto) {
  const [a, m, d] = fechaTexto.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d, 12));
  const diaSemana = new Intl.DateTimeFormat('es-MX', { timeZone: 'UTC', weekday: 'long' }).format(f);
  const mes = new Intl.DateTimeFormat('es-MX', { timeZone: 'UTC', month: 'long' }).format(f);
  return `${diaSemana}, ${d} de ${mes}`;
}
