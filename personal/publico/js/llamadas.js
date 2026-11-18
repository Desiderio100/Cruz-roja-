const intervaloLlamada = 2000;
const intervaloPerdidas = 10000;

const camposDeLaFicha = [
  { clave: "nombre", etiqueta: "Nombre", tipo: "text", autocompletar: "off", sinCorrector: true },
  {
    clave: "celular",
    etiqueta: "Celular",
    tipo: "tel",
    autocompletar: "off",
    ancho: "medio",
    sinCorrector: true,
    validar: (valor) => {
      const digitos = valor.replace(/[\s-]/g, "").replace(/^\+/, "");
      if (valor !== "" && !/^\d{10,15}$/.test(digitos)) return "Escriba el celular con 10 dígitos, por ejemplo 55 5501 0142";
      return "";
    }
  },
  { clave: "motivo", etiqueta: "Motivo de la emergencia", tipo: "textarea" },
  {
    clave: "lesionados",
    etiqueta: "Número de lesionados",
    tipo: "text",
    modoNumerico: true,
    ancho: "corto",
    sinCorrector: true,
    validar: (valor) => (valor !== "" && !/^\d{1,5}$/.test(valor) ? "Escriba solo dígitos, por ejemplo 2" : "")
  },
  { clave: "lesionPrincipal", etiqueta: "Lesión principal", tipo: "text" },
  { clave: "lugar", etiqueta: "Lugar", tipo: "text" },
  { clave: "ubicacion", etiqueta: "Ubicación", tipo: "text", sinCorrector: true },
  { clave: "comentarios", etiqueta: "Comentarios", tipo: "textarea" }
];

const el = (id) => document.getElementById(id);

let actual = null;
let ultimaLinea = 0;
let sinGuardar = false;
let celularCrudo = "";
const tocados = new Set();

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

async function pedir(url, cuerpo) {
  const opciones = { headers: { "X-Requested-With": "fetch", RequestVerificationToken: token() } };
  if (cuerpo !== undefined) {
    opciones.method = "POST";
    opciones.headers["Content-Type"] = "application/json";
    opciones.body = JSON.stringify(cuerpo);
  }
  const respuesta = await fetch(url, opciones);
  if (respuesta.status === 401 || respuesta.status === 403) {
    location.href = "/Acceso";
    throw new Error("sesion");
  }
  const datos = await respuesta.json().catch(() => ({}));
  return { ok: respuesta.ok, datos };
}

function formatearTelefono(telefono) {
  const digitos = (telefono || "").replace(/\D/g, "");
  if (digitos.length < 10) return telefono || "";
  const diez = digitos.slice(-10);
  return `${diez.slice(0, 2)} ${diez.slice(2, 6)} ${diez.slice(6)}`;
}

function formatearDuracion(milisegundos) {
  const total = Math.max(0, Math.floor(milisegundos / 1000));
  const minutos = String(Math.floor(total / 60)).padStart(2, "0");
  const segundos = String(total % 60).padStart(2, "0");
  return `${minutos}:${segundos}`;
}

function mostrar(vista) {
  el("sin-llamada").hidden = vista !== "sin";
  el("con-llamada").hidden = vista !== "con";
  el("acciones").hidden = vista !== "con";
}

function escribirEstado(texto) {
  el("estado-guardado").textContent = texto;
}

function dato(nombre) {
  return document.querySelector(`#franja [data-clave="${nombre}"]`);
}

function pintarFranja(datos) {
  const franja = el("franja");
  if (!franja.children.length) {
    for (const nombre of ["Estado", "Duración", "Delegación", "Canal", "Número"]) {
      franja.append(crear("div", {}, crear("dt", {}, nombre), crear("dd", { "data-clave": nombre })));
    }
  }
  dato("Delegación").textContent = datos.delegacion;
  dato("Canal").textContent = datos.canal === "internet" ? "Internet" : "Telefónico";
  dato("Número").textContent = datos.telefono
    ? `${formatearTelefono(datos.telefono)}${datos.telefonoVerificado ? ", verificado" : ", sin verificar"}`
    : "Sin número";
  dato("Estado").textContent = actual && actual.terminada ? "Terminada" : "En curso";
  actualizarDuracion();
}

function actualizarDuracion() {
  if (!actual) return;
  const fin = actual.terminada ? actual.fin : Date.now();
  dato("Duración").textContent = formatearDuracion(fin - actual.inicio.getTime());
}

function pintarUbicacion(datos) {
  const lista = el("datos-ubicacion");
  const enlace = el("enlace-mapa");
  if (datos.latitud == null || datos.longitud == null) {
    lista.replaceChildren(crear("dt", {}, "Coordenadas"), crear("dd", {}, "Sin ubicación"));
    enlace.hidden = true;
    return;
  }
  const latitud = Number(datos.latitud);
  const longitud = Number(datos.longitud);
  lista.replaceChildren(
    crear("dt", {}, "Coordenadas"),
    crear("dd", {}, `${latitud.toFixed(4)}, ${longitud.toFixed(4)}`),
    crear("dt", {}, "Precisión"),
    crear("dd", {}, datos.precisionM == null ? "Sin dato" : `${Number(datos.precisionM)} m`)
  );
  enlace.href = `https://www.openstreetmap.org/?mlat=${latitud}&mlon=${longitud}#map=17/${latitud}/${longitud}`;
  enlace.hidden = false;
}

function valorMostrado(clave, valor) {
  if (valor == null) return "";
  return clave === "celular" ? formatearTelefono(valor) : valor;
}

function crearCampo(definicion) {
  const id = `campo-${definicion.clave}`;
  const idError = `error-${definicion.clave}`;

  const entrada =
    definicion.tipo === "textarea"
      ? crear("textarea", { id, name: definicion.clave, rows: 2 })
      : crear("input", {
          id,
          name: definicion.clave,
          type: definicion.tipo,
          inputmode: definicion.modoNumerico ? "numeric" : null,
          autocomplete: definicion.autocompletar || "off"
        });
  if (definicion.sinCorrector) entrada.setAttribute("spellcheck", "false");
  entrada.setAttribute("aria-describedby", idError);

  const etiqueta = crear("span", { class: "origen origen-ia", id: `ia-${definicion.clave}`, hidden: true }, "IA");
  const error = crear("p", { class: "campo-error", id: idError });

  entrada.addEventListener("input", () => {
    tocados.add(definicion.clave);
    etiqueta.hidden = true;
    error.textContent = "";
    entrada.removeAttribute("aria-invalid");
    sinGuardar = true;
    escribirEstado(actual && actual.terminada ? "La llamada terminó. Guarde la ficha." : "Hay cambios sin guardar.");
  });

  const clase = definicion.ancho ? `campo campo-${definicion.ancho}` : "campo";
  return crear(
    "div",
    { class: clase },
    crear("div", { class: "campo-cabecera" }, crear("label", { for: id }, definicion.etiqueta), etiqueta),
    entrada,
    error
  );
}

function pintarFicha(datos) {
  const formulario = el("ficha");
  if (!formulario.children.length) formulario.replaceChildren(...camposDeLaFicha.map(crearCampo));
  celularCrudo = datos.ficha.celular || "";
  for (const definicion of camposDeLaFicha) {
    const entrada = formulario.elements[definicion.clave];
    if (!tocados.has(definicion.clave)) {
      const nuevo = valorMostrado(definicion.clave, datos.ficha[definicion.clave]);
      if (entrada.value !== nuevo) entrada.value = nuevo;
    }
    el(`ia-${definicion.clave}`).hidden = tocados.has(definicion.clave) || !(datos.ia || []).includes(definicion.clave);
  }
}

function construirLlamada(datos) {
  actual = { id: datos.id, inicio: new Date(datos.inicio), terminada: false, fin: 0 };
  ultimaLinea = 0;
  sinGuardar = false;
  tocados.clear();
  el("ficha").replaceChildren();
  el("transcripcion").replaceChildren();
  el("titulo-llamada").textContent = "Llamada en curso";
  escribirEstado("Sin cambios por guardar.");
  const devolver = el("devolver");
  if (datos.telefono) {
    devolver.href = `tel:${datos.telefono}`;
    devolver.hidden = false;
  } else {
    devolver.hidden = true;
  }
  mostrar("con");
  actualizarLlamada(datos);
  window.voz.conectar(datos.id);
}

function actualizarLlamada(datos) {
  pintarFranja(datos);
  pintarUbicacion(datos);
  pintarFicha(datos);
}

function marcarTerminada() {
  actual.terminada = true;
  actual.fin = Date.now();
  window.voz.desconectar("La persona terminó la llamada.");
  dato("Estado").textContent = "Terminada";
  actualizarDuracion();
  el("titulo-llamada").textContent = "Llamada terminada";
  escribirEstado(
    sinGuardar
      ? "La persona terminó la llamada. Guarde la ficha y finalice."
      : "La persona terminó la llamada. Revise la ficha y presione Finalizar llamada."
  );
}

function procesarActual(datos) {
  if (actual && !actual.terminada) {
    if (datos.hay && datos.id === actual.id) {
      actualizarLlamada(datos);
      return;
    }
    marcarTerminada();
  }
  if (actual) return;
  if (datos.hay) construirLlamada(datos);
  else mostrar("sin");
}

async function traerTranscripcion() {
  if (!actual) return;
  const id = actual.id;
  const { ok, datos } = await pedir(`/Llamadas/Transcripcion?llamada=${encodeURIComponent(id)}&desde=${ultimaLinea}`);
  if (!ok || !actual || actual.id !== id || !datos.length) return;
  const lista = el("transcripcion");
  const alFinal = lista.scrollHeight - lista.scrollTop - lista.clientHeight < 40;
  for (const linea of datos) {
    ultimaLinea = Math.max(ultimaLinea, linea.id);
    const minutos = String(Math.floor(linea.momento / 60)).padStart(2, "0");
    const segundos = String(linea.momento % 60).padStart(2, "0");
    lista.append(
      crear(
        "li",
        {},
        crear("time", {}, `${minutos}:${segundos}`),
        crear("div", {}, crear("strong", {}, linea.hablante === "operador" ? "Operador" : "Solicitante"), linea.texto)
      )
    );
  }
  if (alFinal) lista.scrollTop = lista.scrollHeight;
}

async function ciclo() {
  try {
    const { ok, datos } = await pedir("/Llamadas/Actual");
    if (ok) procesarActual(datos);
    await traerTranscripcion();
  } catch (error) {
    if (error.message === "sesion") return;
  }
  setTimeout(ciclo, intervaloLlamada);
}

async function cargarPerdidas() {
  try {
    const { ok, datos } = await pedir("/Llamadas/Perdidas");
    if (!ok) return;
    const contenedor = el("perdidas");
    if (!datos.length) {
      contenedor.replaceChildren(crear("p", { class: "vacio" }, "No hay llamadas perdidas en las últimas 24 horas."));
      return;
    }
    const filas = datos.map((llamada) =>
      crear(
        "tr",
        {},
        crear("td", { class: "numero" }, llamada.cuando),
        crear("td", {}, llamada.nombre || "Sin nombre"),
        crear("td", { class: "numero" }, llamada.telefono ? formatearTelefono(llamada.telefono) : "Sin número"),
        crear(
          "td",
          { class: "accion" },
          llamada.telefono
            ? crear("a", { class: "boton boton-chico", href: `tel:${llamada.telefono}` }, "Devolver llamada")
            : ""
        )
      )
    );
    contenedor.replaceChildren(
      crear(
        "div",
        { class: "contenedor-tabla" },
        crear(
          "table",
          {},
          crear("caption", {}, "Llamadas perdidas"),
          crear(
            "colgroup",
            {},
            crear("col", { class: "col-folio" }),
            crear("col"),
            crear("col", { class: "col-telefono" }),
            crear("col", { class: "col-accion" })
          ),
          crear(
            "thead",
            {},
            crear(
              "tr",
              {},
              crear("th", { scope: "col" }, "Cuándo"),
              crear("th", { scope: "col" }, "Persona"),
              crear("th", { scope: "col" }, "Teléfono"),
              crear("th", { scope: "col", class: "accion" }, "Acción")
            )
          ),
          crear("tbody", {}, ...filas)
        )
      )
    );
  } catch (error) {
    if (error.message === "sesion") return;
  }
}

function validarFicha(formulario) {
  let primero = null;
  for (const definicion of camposDeLaFicha) {
    if (!definicion.validar) continue;
    const entrada = formulario.elements[definicion.clave];
    const mensaje = definicion.validar(entrada.value.trim());
    mostrarErrorDeCampo(definicion.clave, mensaje);
    if (mensaje) primero = primero || entrada;
  }
  return primero;
}

function mostrarErrorDeCampo(clave, mensaje) {
  const entrada = el("ficha").elements[clave];
  el(`error-${clave}`).textContent = mensaje;
  if (mensaje) entrada.setAttribute("aria-invalid", "true");
  else entrada.removeAttribute("aria-invalid");
}

el("ficha").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  if (!actual) return;
  const formulario = el("ficha");
  const invalido = validarFicha(formulario);
  if (invalido) {
    escribirEstado("Corrija los campos marcados para guardar.");
    invalido.focus();
    return;
  }
  const cuerpo = { llamada: actual.id };
  for (const definicion of camposDeLaFicha) {
    cuerpo[definicion.clave] = formulario.elements[definicion.clave].value.trim();
  }
  if (!tocados.has("celular")) cuerpo.celular = celularCrudo;

  try {
    const { ok, datos } = await pedir("/Llamadas/Guardar", cuerpo);
    if (!ok) {
      if (datos.campo) {
        mostrarErrorDeCampo(datos.campo, datos.error);
        formulario.elements[datos.campo].focus();
      }
      escribirEstado(datos.campo ? "Corrija los campos marcados para guardar." : datos.error || "No se pudo guardar la ficha.");
      return;
    }
    const hora = new Date().toLocaleTimeString("es-MX", { hour: "2-digit", minute: "2-digit", hour12: false });
    tocados.clear();
    sinGuardar = false;
    escribirEstado(`Ficha guardada a las ${hora}.`);
  } catch (error) {
    if (error.message !== "sesion") escribirEstado("No se pudo guardar la ficha. Revise la conexión.");
  }
});

el("finalizar").addEventListener("click", () => {
  el("dialogo-finalizar-aviso").textContent = sinGuardar ? "Hay cambios sin guardar. Si finaliza ahora, se perderán." : "";
  el("dialogo-finalizar").showModal();
});

el("dialogo-finalizar").addEventListener("close", async () => {
  const decision = el("dialogo-finalizar").returnValue;
  el("dialogo-finalizar").returnValue = "";
  if (decision !== "finalizar" || !actual) return;
  try {
    await window.voz.finalizar();
    const { ok, datos } = await pedir("/Llamadas/Finalizar", { llamada: actual.id });
    if (!ok) {
      escribirEstado(datos.error || "No se pudo finalizar la llamada.");
      return;
    }
    actual = null;
    sinGuardar = false;
    tocados.clear();
    el("franja").replaceChildren();
    mostrar("sin");
    cargarPerdidas();
  } catch (error) {
    if (error.message !== "sesion") escribirEstado("No se pudo finalizar la llamada. Revise la conexión.");
  }
});

window.addEventListener("beforeunload", (evento) => {
  if (sinGuardar) evento.preventDefault();
});

setInterval(actualizarDuracion, 1000);
setInterval(cargarPerdidas, intervaloPerdidas);
cargarPerdidas();
ciclo();
