(function () {
  const { Room, RoomEvent, Track } = window.LivekitClient;
  const el = (id) => document.getElementById(id);
  const esperaCamara = 30000;

  let sala = null;
  let llamadaId = null;
  let intento = 0;
  let microfonoActivo = true;
  let camara = "apagada";
  let temporizador = null;

  function token() {
    return document.querySelector('meta[name="token"]').content;
  }

  function estado(texto) {
    el("voz-estado").textContent = texto;
  }

  function personaPresente() {
    return Boolean(sala) && sala.remoteParticipants.size > 0;
  }

  function pintarSonido() {
    el("voz-sonido").hidden = !sala || sala.canPlaybackAudio || el("voz-audio").children.length === 0;
  }

  function pintarCamara() {
    const boton = el("voz-camara");
    const mensaje = el("camara-estado");
    const conectado = Boolean(sala) && sala.state === "connected" && personaPresente();
    boton.disabled = !conectado || camara === "esperando";
    boton.classList.toggle("boton-primario", camara !== "activa");
    if (camara === "activa") boton.textContent = "Detener cámara";
    else if (camara === "esperando") boton.textContent = "Esperando respuesta";
    else boton.textContent = "Pedir cámara";
    const textos = {
      apagada: "La cámara de la persona está apagada.",
      esperando: "Se le pidió a la persona que active su cámara. Está esperando su respuesta.",
      activa: "La persona activó su cámara.",
      rechazada: "La persona no aceptó compartir su cámara.",
      sinpermiso: "La persona aceptó, pero su teléfono no dio acceso a la cámara.",
      sinrespuesta: "La persona no respondió a la solicitud de cámara.",
      detenida: "La cámara de la persona se apagó."
    };
    mensaje.textContent = textos[camara] || "";
    el("video-persona").hidden = camara !== "activa";
    el("video-vacio").hidden = camara === "activa";
  }

  function cambiarCamara(valor) {
    camara = valor;
    clearTimeout(temporizador);
    temporizador = null;
    pintarCamara();
  }

  function pintarEstadoDeLaLlamada() {
    if (!sala || sala.state !== "connected") return;
    estado(personaPresente() ? "Conectado. Puede hablar con la persona." : "Esperando a que la persona se conecte.");
    pintarCamara();
  }

  async function enviar(mensaje) {
    if (!sala || sala.state !== "connected") return;
    const datos = new TextEncoder().encode(JSON.stringify(mensaje));
    await sala.localParticipant.publishData(datos, { reliable: true, topic: "llamada" });
  }

  function alRecibir(payload, participante, tipoEnvio, tema) {
    if (tema !== "llamada") return;
    let mensaje;
    try {
      mensaje = JSON.parse(new TextDecoder().decode(payload));
    } catch (error) {
      return;
    }
    if (mensaje.tipo !== "camara") return;
    const mapa = { aceptada: "activa", rechazada: "rechazada", sin_permiso: "sinpermiso", apagada: "detenida" };
    if (mapa[mensaje.estado]) cambiarCamara(mapa[mensaje.estado]);
  }

  async function conectar(id) {
    if (llamadaId === id && sala) return;
    await desconectar();
    llamadaId = id;
    const mi = ++intento;
    estado("Conectando la voz.");
    pintarCamara();

    let datos;
    try {
      const respuesta = await fetch("/Llamadas/Sala", {
        method: "POST",
        headers: { "Content-Type": "application/json", RequestVerificationToken: token(), "X-Requested-With": "fetch" },
        body: JSON.stringify({ llamada: id })
      });
      datos = await respuesta.json();
      if (!respuesta.ok) throw new Error(datos.error || "error");
    } catch (error) {
      if (mi === intento) estado(error.message && error.message !== "error" ? error.message : "No se pudo conectar la voz.");
      return;
    }
    if (mi !== intento) return;

    const nueva = new Room({ adaptiveStream: true, dynacast: true });
    sala = nueva;
    nueva.on(RoomEvent.ParticipantConnected, pintarEstadoDeLaLlamada);
    nueva.on(RoomEvent.ParticipantDisconnected, () => {
      if (!personaPresente()) cambiarCamara("apagada");
      pintarEstadoDeLaLlamada();
    });
    nueva.on(RoomEvent.TrackSubscribed, (pista) => {
      if (pista.kind === Track.Kind.Audio) {
        el("voz-audio").append(pista.attach());
        setTimeout(pintarSonido, 400);
      } else if (pista.kind === Track.Kind.Video) {
        pista.attach(el("video-persona"));
        cambiarCamara("activa");
      }
    });
    nueva.on(RoomEvent.TrackUnsubscribed, (pista) => {
      if (pista.kind === Track.Kind.Video) {
        pista.detach();
        if (camara === "activa") cambiarCamara("detenida");
      } else {
        pista.detach().forEach((nodo) => nodo.remove());
      }
    });
    nueva.on(RoomEvent.DataReceived, alRecibir);
    nueva.on(RoomEvent.AudioPlaybackStatusChanged, pintarSonido);
    nueva.on(RoomEvent.Disconnected, () => {
      if (sala === nueva) estado("La voz se desconectó.");
      pintarCamara();
    });

    try {
      await nueva.connect(datos.url, datos.token);
    } catch (error) {
      if (mi === intento) estado("No se pudo conectar la voz.");
      return;
    }
    if (mi !== intento) {
      nueva.disconnect();
      return;
    }
    pintarSonido();
    pintarEstadoDeLaLlamada();
    try {
      await nueva.localParticipant.setMicrophoneEnabled(true);
      microfonoActivo = true;
    } catch (error) {
      microfonoActivo = false;
      estado("No se pudo usar su micrófono. Permítalo en el navegador y recargue la página.");
    }
    pintarMicrofono();
  }

  function pintarMicrofono() {
    el("voz-microfono").textContent = microfonoActivo ? "Silenciar micrófono" : "Activar micrófono";
  }

  async function desconectar(mensaje) {
    intento += 1;
    const anterior = sala;
    sala = null;
    llamadaId = null;
    clearTimeout(temporizador);
    temporizador = null;
    camara = "apagada";
    if (anterior) anterior.disconnect();
    el("voz-audio").replaceChildren();
    el("video-persona").srcObject = null;
    el("voz-sonido").hidden = true;
    estado(mensaje || "Sin llamada.");
    pintarCamara();
  }

  async function finalizar() {
    try {
      await enviar({ tipo: "fin" });
    } catch (error) {
      return desconectar();
    }
    await new Promise((resolver) => setTimeout(resolver, 150));
    await desconectar();
  }

  el("voz-camara").addEventListener("click", async () => {
    if (!sala) return;
    if (camara === "activa") {
      await enviar({ tipo: "detener_camara" });
      cambiarCamara("detenida");
      return;
    }
    await enviar({ tipo: "pedir_camara" });
    cambiarCamara("esperando");
    temporizador = setTimeout(() => cambiarCamara("sinrespuesta"), esperaCamara);
  });

  el("voz-microfono").addEventListener("click", async () => {
    if (!sala) return;
    try {
      await sala.localParticipant.setMicrophoneEnabled(!microfonoActivo);
      microfonoActivo = !microfonoActivo;
    } catch (error) {
      estado("No se pudo usar su micrófono.");
    }
    pintarMicrofono();
  });

  el("voz-sonido").addEventListener("click", async () => {
    if (sala) await sala.startAudio();
    pintarSonido();
  });

  window.addEventListener("beforeunload", () => {
    if (sala) sala.disconnect();
  });

  window.voz = { conectar, desconectar, finalizar };
})();
