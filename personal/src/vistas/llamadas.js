import { layout } from './layout.js';

export function paginaLlamadas({ usuario, token, perdidasHoras }) {
  const cuerpo = `<main class="pagina">
  <div id="sin-llamada" hidden>
    <h1 class="titulo">Llamadas</h1>
    <section class="panel sin-llamada" aria-labelledby="titulo-vacio">
      <div class="panel-cabecera">
        <h2 id="titulo-vacio">No hay llamadas esperando</h2>
      </div>
      <div class="panel-cuerpo">
        <p>Esta pantalla busca llamadas nuevas cada 2 segundos. Cuando entre una, se abre sola con su ficha.</p>
        <p>Si la persona cuelga antes de que usted conteste, la llamada aparece en perdidas.</p>
      </div>
    </section>
  </div>

  <div id="con-llamada" hidden>
    <h1 class="titulo" id="titulo-llamada">Llamada en curso</h1>

    <dl class="franja" id="franja"></dl>

    <div class="rejilla">
      <section class="panel" aria-labelledby="titulo-ficha">
        <div class="panel-cabecera">
          <h2 id="titulo-ficha">Ficha de emergencia</h2>
          <p>La IA llena los campos mientras la persona habla. Revise cada dato antes de guardar.</p>
        </div>
        <form class="panel-cuerpo" id="ficha" novalidate></form>
      </section>

      <div class="columna">
        <section class="panel" aria-labelledby="titulo-mapa">
          <div class="panel-cabecera">
            <h2 id="titulo-mapa">Ubicación de la persona</h2>
          </div>
          <div class="panel-cuerpo">
            <dl class="datos" id="datos-ubicacion"></dl>
            <a class="enlace-mapa" id="enlace-mapa" href="#" target="_blank" rel="noopener" hidden>Abrir en el mapa</a>
          </div>
        </section>

        <section class="panel" aria-labelledby="titulo-transcripcion">
          <div class="panel-cabecera">
            <h2 id="titulo-transcripcion">Transcripción</h2>
            <p>Generada por IA en el teléfono de la persona.</p>
          </div>
          <div class="panel-cuerpo">
            <ol class="transcripcion" id="transcripcion" role="log" aria-live="polite"></ol>
          </div>
        </section>
      </div>
    </div>
  </div>

  <section class="panel bloque-perdidas" aria-labelledby="titulo-perdidas">
    <div class="panel-cabecera">
      <h2 id="titulo-perdidas">Llamadas perdidas</h2>
      <p>De las últimas ${perdidasHoras} horas en su delegación.</p>
    </div>
    <div id="perdidas"></div>
  </section>
</main>

<footer class="acciones" id="acciones" hidden>
  <div class="acciones-contenido">
    <p class="estado-guardado" id="estado-guardado" role="status">Sin cambios por guardar.</p>
    <a class="boton" id="devolver" href="#">Devolver llamada</a>
    <button type="button" class="boton" id="finalizar">Finalizar llamada</button>
    <button type="submit" class="boton boton-primario" form="ficha">Guardar ficha</button>
  </div>
</footer>

<dialog id="dialogo-finalizar" aria-labelledby="dialogo-finalizar-titulo">
  <form method="dialog">
    <div class="dialogo-cuerpo">
      <h2 id="dialogo-finalizar-titulo">Finalizar llamada</h2>
      <p>La llamada se cierra y esta pantalla pasa a la siguiente llamada en espera.</p>
      <p id="dialogo-finalizar-aviso"></p>
    </div>
    <div class="dialogo-pie">
      <button type="submit" class="boton" value="cancelar">Seguir en la llamada</button>
      <button type="submit" class="boton boton-primario" value="finalizar">Finalizar llamada</button>
    </div>
  </form>
</dialog>`;
  return layout({ titulo: 'Llamadas', seccion: 'Llamadas', usuario, token, cuerpo, scripts: ['/js/llamadas.js'] });
}
