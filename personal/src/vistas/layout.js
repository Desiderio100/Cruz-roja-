import { esc } from './util.js';

export function layout({ titulo, seccion, usuario, token, cuerpo, scripts = [] }) {
  const rol = usuario.rol === 'operador' ? 'Operador' : 'Personal administrativo';
  return `<!doctype html>
<html lang="es-MX">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="token" content="${esc(token)}">
  <title>${esc(titulo)} - Cruz Roja Mexicana</title>
  <link rel="stylesheet" href="/css/estilos.css">
</head>
<body>
  <header class="barra">
    <div class="marca">Cruz Roja Mexicana <span>${esc(seccion)}</span></div>
    <div class="usuario">
      <span>${esc(rol)}, ${esc(usuario.delegacion)}</span>
      <form action="/Acceso/Salir" method="post">
        <input type="hidden" name="_token" value="${esc(token)}">
        <button type="submit" class="boton boton-chico">Cerrar sesión</button>
      </form>
    </div>
  </header>

${cuerpo}

${scripts.map((s) => `  <script src="${esc(s)}"></script>`).join('\n')}
</body>
</html>
`;
}

export function layoutAcceso({ titulo, cuerpo, scripts = [] }) {
  return `<!doctype html>
<html lang="es-MX">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(titulo)} - Cruz Roja Mexicana</title>
  <link rel="stylesheet" href="/css/estilos.css">
</head>
<body>
  <header class="barra">
    <div class="marca">Cruz Roja Mexicana <span>Personal</span></div>
  </header>

${cuerpo}

${scripts.map((s) => `  <script src="${esc(s)}"></script>`).join('\n')}
</body>
</html>
`;
}
