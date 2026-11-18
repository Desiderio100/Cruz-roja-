const controles = {
  fecha: document.getElementById("fecha"),
  servicio: document.getElementById("servicio"),
  estado: document.getElementById("estado"),
  agenda: document.getElementById("agenda"),
  resumen: document.getElementById("resumen"),
  mensaje: document.getElementById("mensaje"),
  dialogo: document.getElementById("dialogo"),
  detalle: document.getElementById("dialogo-detalle")
};

const intervaloRefresco = 3 * 60 * 1000;
let citaPorPosponer = null;

function token() {
  return document.querySelector('meta[name="token"]').content;
}

function crear(etiqueta, atributos, ...hijos) {
  const nodo = document.createElement(etiqueta);
  for (const [nombre, valor] of Object.entries(atributos || {})) {
    if (valor === true) nodo.setAttribute(nombre, "");
    else if (valor !== false && valor != null) nodo.setAttribute(nombre, valor);
  }
  for (const hijo of hijos) nodo.append(hijo);
  return nodo;
}

function aTextoDeFecha(fecha) {
  const anio = fecha.getFullYear();
  const mes = String(fecha.getMonth() + 1).padStart(2, "0");
  const dia = String(fecha.getDate()).padStart(2, "0");
  return `${anio}-${mes}-${dia}`;
}

function mostrarMensaje(texto, esError) {
  controles.mensaje.textContent = texto;
  controles.mensaje.classList.toggle("mensaje-error", Boolean(esError));
}

function aplicarFiltros() {
  const contenido = document.getElementById("agenda-contenido");
  if (!contenido) return;
  const servicio = controles.servicio.value;
  const estado = controles.estado.value;
  let visibles = 0;
  let confirmadas = 0;

  for (const bloque of contenido.querySelectorAll(".bloque")) {
    const servicioValido = servicio === "todos" || bloque.dataset.servicio === servicio;
    let cuenta = 0;
    for (const fila of bloque.querySelectorAll("tbody tr")) {
      const visible = servicioValido && (estado === "todos" || fila.dataset.estado === estado);
      fila.hidden = !visible;
      if (visible) {
        cuenta += 1;
        if (fila.dataset.estado === "confirmada") confirmadas += 1;
      }
    }
    bloque.hidden = cuenta === 0;
    bloque.querySelector("[data-contador]").textContent = cuenta === 1 ? "1 cita" : `${cuenta} citas`;
    visibles += cuenta;
  }

  document.getElementById("vacio")?.remove();
  const texto = contenido.dataset.fechaTexto || "";
  const fecha = texto.charAt(0).toUpperCase() + texto.slice(1);
  if (visibles === 0) {
    controles.agenda.append(
      crear("p", { class: "panel vacio", id: "vacio" }, "No hay citas con estos filtros. Cambie el día, el servicio o el estado.")
    );
    controles.resumen.textContent = `${fecha}: sin citas.`;
    return;
  }
  controles.resumen.textContent = `${fecha}: ${visibles} ${visibles === 1 ? "cita" : "citas"}, ${confirmadas} ${
    confirmadas === 1 ? "confirmada" : "confirmadas"
  }.`;
}

async function pedir(url, opciones) {
  const respuesta = await fetch(url, {
    ...opciones,
    headers: { "X-Requested-With": "fetch", RequestVerificationToken: token(), ...(opciones && opciones.headers) }
  });
  if (respuesta.status === 401 || respuesta.status === 403) {
    location.href = "/Acceso";
    throw new Error("sesion");
  }
  return respuesta;
}

async function cargarAgenda() {
  try {
    const respuesta = await pedir(`/Citas/Agenda?fecha=${controles.fecha.value}`);
    if (!respuesta.ok) {
      mostrarMensaje("No se pudo actualizar la agenda. Se intentará de nuevo en unos minutos.", true);
      return;
    }
    controles.agenda.innerHTML = await respuesta.text();
    aplicarFiltros();
  } catch (error) {
    if (error.message !== "sesion") mostrarMensaje("No se pudo actualizar la agenda. Revise la conexión.", true);
  }
}

controles.agenda.addEventListener("click", (evento) => {
  const boton = evento.target.closest("[data-posponer]");
  if (!boton) return;
  citaPorPosponer = { folio: boton.dataset.folio, nombre: boton.dataset.nombre, hora: boton.dataset.hora };
  controles.detalle.textContent = `Cita ${citaPorPosponer.folio} de ${citaPorPosponer.nombre}, ${citaPorPosponer.hora}.`;
  controles.dialogo.showModal();
});

controles.dialogo.addEventListener("close", async () => {
  const cita = citaPorPosponer;
  const decision = controles.dialogo.returnValue;
  citaPorPosponer = null;
  controles.dialogo.returnValue = "";
  if (decision !== "posponer" || !cita) return;

  try {
    const respuesta = await pedir("/Citas/Posponer", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ folio: cita.folio })
    });
    if (respuesta.ok) {
      mostrarMensaje(`Cita ${cita.folio} pospuesta. La persona verá el cambio en su app.`, false);
    } else {
      const datos = await respuesta.json().catch(() => ({}));
      mostrarMensaje(datos.error || "No se pudo posponer la cita.", true);
    }
  } catch (error) {
    if (error.message !== "sesion") mostrarMensaje("No se pudo posponer la cita. Revise la conexión.", true);
  }
  await cargarAgenda();
});

function moverDia(delta) {
  const [anio, mes, dia] = controles.fecha.value.split("-").map(Number);
  controles.fecha.value = aTextoDeFecha(new Date(anio, mes - 1, dia + delta));
  cambiarDia();
}

function cambiarDia() {
  mostrarMensaje("", false);
  history.replaceState(null, "", `/Citas?fecha=${controles.fecha.value}`);
  cargarAgenda();
}

document.getElementById("anterior").addEventListener("click", () => moverDia(-1));
document.getElementById("siguiente").addEventListener("click", () => moverDia(1));
controles.fecha.addEventListener("change", () => {
  if (controles.fecha.value) cambiarDia();
});
for (const control of [controles.servicio, controles.estado]) {
  control.addEventListener("change", () => {
    mostrarMensaje("", false);
    aplicarFiltros();
  });
}

setInterval(() => {
  if (!controles.dialogo.open && !document.hidden) cargarAgenda();
}, intervaloRefresco);

aplicarFiltros();
