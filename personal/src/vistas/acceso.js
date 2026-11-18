import { esc } from './util.js';
import { layoutAcceso } from './layout.js';

export function paginaAcceso({ error = null, segundosBloqueo = 0, token }) {
  const cuerpo = `<main class="pagina pagina-acceso">
  <section class="panel acceso" aria-labelledby="titulo-acceso">
    <div class="panel-cabecera">
      <h1 id="titulo-acceso">Entrar</h1>
      <p>Escriba su matrícula para continuar.</p>
    </div>
    <form class="panel-cuerpo" id="acceso" method="post" action="/Acceso" novalidate data-segundos="${segundosBloqueo}">
      <input type="hidden" name="_token" value="${esc(token)}">
      <div class="campo">
        <div class="campo-cabecera">
          <label for="matricula">Matrícula</label>
          <button type="button" class="boton boton-enlace" id="mostrar" aria-controls="matricula" aria-pressed="false">Mostrar</button>
        </div>
        <input
          id="matricula"
          name="matricula"
          type="password"
          maxlength="25"
          autocomplete="current-password"
          autocapitalize="off"
          spellcheck="false"
          required
          aria-describedby="error-matricula"${error ? '\n          aria-invalid="true"' : ''}>
        <p class="campo-error" id="error-matricula" role="alert">${esc(error)}</p>
      </div>
      <button type="submit" class="boton boton-primario boton-ancho" id="entrar">Entrar</button>
    </form>
  </section>
</main>`;
  return layoutAcceso({ titulo: 'Entrar', cuerpo, scripts: ['/js/acceso.js'] });
}
