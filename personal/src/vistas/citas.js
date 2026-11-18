import { layout } from './layout.js';
import { esc } from './util.js';

const ETIQUETAS = { confirmada: 'Confirmada', pospuesta: 'Pospuesta' };

export function agenda(modelo) {
  const grupos = modelo.grupos
    .map((grupo) => {
      const filas = grupo.citas
        .map((cita) => {
          const accion =
            cita.estado === 'confirmada'
              ? `<button type="button" class="boton boton-chico" data-posponer data-folio="${esc(cita.folio)}" data-nombre="${esc(cita.nombre)}" data-hora="${esc(cita.hora)}" aria-label="Posponer la cita ${esc(cita.folio)} de ${esc(cita.nombre)}">Posponer</button>`
              : '';
          return `            <tr data-estado="${esc(cita.estado)}"${cita.estado === 'cancelada' ? ' class="fila-cancelada"' : ''}>
                <td class="numero">${esc(cita.hora)}</td>
                <td class="numero">${esc(cita.folio)}</td>
                <td>${esc(cita.nombre)}</td>
                <td class="numero">${esc(cita.telefono)}</td>
                <td><span class="estado estado-${esc(cita.estado)}">${ETIQUETAS[cita.estado] ?? 'Cancelada'}</span></td>
                <td class="accion">${accion}</td>
              </tr>`;
        })
        .join('\n');
      return `    <section class="panel bloque" data-servicio="${esc(grupo.servicio)}">
      <div class="bloque-cabecera">
        <h2>${esc(grupo.nombre)}</h2>
        <span data-contador></span>
      </div>
      <div class="contenedor-tabla">
        <table>
          <caption>Citas de ${esc(grupo.nombre)}</caption>
          <colgroup>
            <col class="col-hora">
            <col class="col-folio">
            <col>
            <col class="col-telefono">
            <col class="col-estado">
            <col class="col-accion">
          </colgroup>
          <thead>
            <tr>
              <th scope="col" class="numero">Hora</th>
              <th scope="col">Folio</th>
              <th scope="col">Persona</th>
              <th scope="col">Teléfono</th>
              <th scope="col">Estado</th>
              <th scope="col" class="accion">Acción</th>
            </tr>
          </thead>
          <tbody>
${filas}
          </tbody>
        </table>
      </div>
    </section>`;
    })
    .join('\n');
  return `<div id="agenda-contenido" data-fecha="${esc(modelo.fecha)}" data-fecha-texto="${esc(modelo.fechaTexto)}">
${grupos}
</div>`;
}

export function paginaCitas({ usuario, token, modelo }) {
  const cuerpo = `<main class="pagina">
  <h1 class="titulo">Citas del día</h1>

  <div class="herramientas">
    <div class="herramienta">
      <label for="fecha">Día</label>
      <div class="selector-dia">
        <button type="button" class="boton" id="anterior" aria-label="Día anterior">Anterior</button>
        <input type="date" id="fecha" value="${esc(modelo.fecha)}">
        <button type="button" class="boton" id="siguiente" aria-label="Día siguiente">Siguiente</button>
      </div>
    </div>
    <div class="herramienta">
      <label for="servicio">Servicio</label>
      <select id="servicio">
        <option value="todos">Todos</option>
        <option value="nutricion">Nutrición</option>
        <option value="psicologia">Psicología</option>
      </select>
    </div>
    <div class="herramienta">
      <label for="estado">Estado</label>
      <select id="estado">
        <option value="todos">Todos</option>
        <option value="confirmada">Confirmadas</option>
        <option value="pospuesta">Pospuestas</option>
        <option value="cancelada">Canceladas</option>
      </select>
    </div>
  </div>

  <p class="resumen" id="resumen" role="status"></p>
  <p class="mensaje" id="mensaje" role="status"></p>

  <div id="agenda">
${agenda(modelo)}
  </div>
</main>

<dialog id="dialogo" aria-labelledby="dialogo-titulo">
  <form method="dialog">
    <div class="dialogo-cuerpo">
      <h2 id="dialogo-titulo">Posponer cita</h2>
      <p id="dialogo-detalle"></p>
      <p>La persona verá la cita como pospuesta en su app y podrá elegir otro horario.</p>
    </div>
    <div class="dialogo-pie">
      <button type="submit" class="boton" value="cancelar">Conservar cita</button>
      <button type="submit" class="boton boton-primario" value="posponer">Posponer cita</button>
    </div>
  </form>
</dialog>`;
  return layout({ titulo: 'Citas del día', seccion: 'Citas', usuario, token, cuerpo, scripts: ['/js/citas.js'] });
}
