export function telefono(texto) {
  const digitos = String(texto ?? '').replace(/\D/g, '');
  if (digitos.length < 10) return texto;
  const ultimos = digitos.slice(-10);
  return `${ultimos.slice(0, 2)} ${ultimos.slice(2, 6)} ${ultimos.slice(6)}`;
}

export function entero(valor) {
  return valor === null || valor === undefined ? null : Number(valor);
}

export function texto(valor) {
  return valor === null || valor === undefined ? null : String(valor);
}

export function booleano(valor) {
  return valor !== null && valor !== undefined && Number(valor) !== 0;
}

export function numero(valor) {
  return valor === null || valor === undefined ? null : Number(valor);
}
