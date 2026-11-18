const ENTIDADES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export function esc(valor) {
  return String(valor ?? '').replace(/[&<>"']/g, (c) => ENTIDADES[c]);
}
