// Sitio de administración de pedidos (Cruz Roja · Productos con causa).
// JavaScript simple, sin librerías. Reglas que se siguen en todo el archivo:
//   - Nada de innerHTML: todo el texto que viene del servidor (nombres, domicilios...) se pone con
//     textContent, así un nombre como "<img onerror=...>" se muestra como texto y no se ejecuta.
//   - La sesión vive en una cookie HttpOnly: este código nunca ve ni guarda la contraseña ni el token.
(() => {
  'use strict';

  // ───────── Utilidades ─────────
  const $ = (id) => document.getElementById(id);

  function el(etiqueta, atributos = {}, ...hijos) {
    const nodo = document.createElement(etiqueta);
    for (const [clave, valor] of Object.entries(atributos)) {
      if (valor === false || valor == null) continue;
      if (clave === 'clase') nodo.className = valor;
      else if (clave === 'texto') nodo.textContent = valor;
      else if (clave.startsWith('on') && typeof valor === 'function') nodo.addEventListener(clave.slice(2), valor);
      else nodo.setAttribute(clave, valor === true ? '' : valor);
    }
    for (const hijo of hijos.flat()) {
      if (hijo == null || hijo === false) continue;
      nodo.append(hijo instanceof Node ? hijo : document.createTextNode(String(hijo)));
    }
    return nodo;
  }

  const dinero = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });
  const fechaCorta = new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const fechaLarga = new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' });
  const formatear = (formato, iso) => (iso ? formato.format(new Date(iso)) : '—');

  const ENVIOS = ['por_preparar', 'preparando', 'enviado', 'entregado'];
  const ETIQUETA_ENVIO = { por_preparar: 'Por preparar', preparando: 'Preparando', enviado: 'Enviado', entregado: 'Entregado' };
  const ETIQUETA_PAGO = { pendiente: 'Pendiente de pago', pagado: 'Pagado', cancelado: 'Cancelado', reembolsado: 'Reembolsado' };
  const COLOR_PAGO = { pendiente: 'aviso', pagado: 'ok', cancelado: 'gris', reembolsado: 'rojo' };
  const COLOR_ENVIO = { por_preparar: 'gris', preparando: 'aviso', enviado: 'info', entregado: 'ok' };

  const insignia = (texto, color) => el('span', { clase: `insignia insignia--${color}`, texto });
  const insigniaPago = (estado) => insignia(ETIQUETA_PAGO[estado] ?? estado, COLOR_PAGO[estado] ?? 'gris');
  const insigniaEnvio = (pedido) => (pedido.estado === 'pagado'
    ? insignia(ETIQUETA_ENVIO[pedido.estado_envio], COLOR_ENVIO[pedido.estado_envio])
    : el('span', { clase: 'suave', texto: '—' }));

  // ───────── Llamadas al servidor ─────────
  async function api(metodo, ruta, cuerpo) {
    let r;
    try {
      r = await fetch(`/admin/api${ruta}`, {
        method: metodo,
        headers: cuerpo !== undefined ? { 'Content-Type': 'application/json' } : {},
        body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined,
        credentials: 'same-origin',
      });
    } catch {
      throw Object.assign(new Error('No hay conexión con el servidor. Revisa tu internet e intenta de nuevo.'), { estado: 0 });
    }
    if (r.status === 204) return null;
    const datos = await r.json().catch(() => ({}));
    if (!r.ok) {
      const mensaje = datos.error || (r.status === 429 ? 'Demasiadas peticiones. Espera un momento.' : 'Algo salió mal. Intenta de nuevo.');
      throw Object.assign(new Error(mensaje), { estado: r.status });
    }
    return datos;
  }

  // ───────── Estado de la pantalla ─────────
  const FILTROS = [
    { id: 'por_enviar', etiqueta: 'Por enviar', params: { estado: 'pagado', envio: 'por_preparar,preparando' }, conteo: 'por_enviar' },
    { id: 'enviados', etiqueta: 'Enviados', params: { estado: 'pagado', envio: 'enviado' }, conteo: 'enviado' },
    { id: 'entregados', etiqueta: 'Entregados', params: { estado: 'pagado', envio: 'entregado' }, conteo: 'entregado' },
    { id: 'pendientes', etiqueta: 'Pendientes de pago', params: { estado: 'pendiente' }, conteo: 'pendiente' },
    { id: 'cancelados', etiqueta: 'Cancelados', params: { estado: 'cancelado' }, conteo: 'cancelado' },
    { id: 'reembolsados', etiqueta: 'Reembolsados', params: { estado: 'reembolsado' }, conteo: 'reembolsado' },
    { id: 'todos', etiqueta: 'Todos', params: {}, conteo: null },
  ];

  const estado = {
    yo: null,
    filtro: 'por_enviar',
    q: '',
    pagina: 1,
    resumen: null,
    ultimaCarga: 0,
    peticion: 0,
    pedidoAbierto: null, // detalle que se está mostrando
  };

  // ───────── Avisos (toasts) ─────────
  function avisar(texto, { error = false } = {}) {
    const aviso = el('p', { clase: `aviso${error ? ' aviso--error' : ''}`, texto });
    $('avisos').append(aviso);
    setTimeout(() => aviso.remove(), error ? 8000 : 4500);
  }

  // ───────── Vistas: entrada y salida ─────────
  function mostrarLogin(mensaje = '') {
    cerrarDialogos();
    $('vista-app').hidden = true;
    $('vista-login').hidden = false;
    document.title = 'Entrar · Pedidos Cruz Roja';
    const error = $('login-error');
    error.textContent = mensaje;
    error.hidden = !mensaje;
    $('login-contrasena').value = '';
    (($('login-usuario').value) ? $('login-contrasena') : $('login-usuario')).focus();
  }

  function cerrarDialogos() {
    for (const id of ['dialogo-reembolso', 'dialogo-detalle']) {
      const d = $(id);
      if (d.open) d.close();
    }
    estado.pedidoAbierto = null;
  }

  function sesionTerminada() {
    estado.yo = null;
    mostrarLogin('Tu sesión terminó. Entra de nuevo.');
  }

  async function iniciarApp(yo) {
    estado.yo = yo;
    $('vista-login').hidden = true;
    $('vista-app').hidden = false;
    $('persona').textContent = `${yo.usuario} · ${yo.rol === 'administrativo' ? 'administrativo' : 'operador'}`;

    // Enlace al panel de llamadas y citas (otro sitio, con su propia entrada por matrícula).
    const enlacePanel = $('enlace-panel');
    if (yo.panel_personal) enlacePanel.href = yo.panel_personal;
    enlacePanel.hidden = !yo.panel_personal;

    const banner = $('banner');
    banner.classList.remove('banner--info');
    if (yo.pagos.modo === 'prueba') {
      banner.textContent = 'Stripe está en modo de prueba: los pedidos y reembolsos de aquí no mueven dinero real.';
      banner.hidden = false;
    } else if (!yo.pagos.disponible) {
      banner.textContent = 'Los pagos con Stripe están apagados en el servidor: puedes ver los pedidos, pero no hacer reembolsos.';
      banner.classList.add('banner--info');
      banner.hidden = false;
    } else {
      banner.hidden = true;
    }
    dibujarFiltros();
    await cargarLista();
  }

  // ───────── Lista ─────────
  function dibujarFiltros() {
    const caja = $('filtros');
    caja.replaceChildren(...FILTROS.map((f) => {
      const n = f.conteo && estado.resumen ? estado.resumen[f.conteo] : null;
      return el('button', {
        clase: 'chip', type: 'button', 'aria-pressed': String(estado.filtro === f.id),
        onclick: () => { estado.filtro = f.id; estado.pagina = 1; dibujarFiltros(); cargarLista(); },
      }, f.etiqueta, n != null ? el('span', { clase: 'chip__n', texto: String(n) }) : null);
    }));
  }

  function mensajeLista(texto, { error = false } = {}) {
    const p = $('estado-lista');
    p.textContent = texto;
    p.classList.toggle('estado-lista--error', error);
  }

  async function cargarLista() {
    const turno = ++estado.peticion;
    const filtro = FILTROS.find((f) => f.id === estado.filtro);
    const parametros = new URLSearchParams({ ...filtro.params, pagina: String(estado.pagina) });
    if (estado.q) parametros.set('q', estado.q);

    mensajeLista('Cargando pedidos…');
    try {
      const datos = await api('GET', `/pedidos?${parametros}`);
      if (turno !== estado.peticion) return; // llegó otra búsqueda después: esta ya no sirve
      estado.resumen = datos.resumen;
      estado.ultimaCarga = Date.now();
      document.title = `${datos.resumen.por_enviar > 0 ? `(${datos.resumen.por_enviar}) ` : ''}Pedidos · Cruz Roja`;
      dibujarFiltros();
      dibujarTabla(datos);
    } catch (error) {
      if (turno !== estado.peticion) return;
      if (error.estado === 401) return sesionTerminada();
      $('tabla').hidden = true;
      $('paginacion').hidden = true;
      mensajeLista(error.message, { error: true });
    }
  }

  function dibujarTabla(datos) {
    const { pedidos, total, pagina, paginas } = datos;
    const tabla = $('tabla');
    if (pedidos.length === 0) {
      tabla.hidden = true;
      $('paginacion').hidden = true;
      mensajeLista(estado.q ? 'Ningún pedido coincide con tu búsqueda.' : 'No hay pedidos en esta lista.');
      return;
    }
    mensajeLista('');
    tabla.hidden = false;
    $('cuerpo-tabla').replaceChildren(...pedidos.map((p) => {
      const abrir = () => abrirDetalle(p.id);
      return el('tr', { onclick: abrir },
        el('td', { 'data-etiqueta': 'Folio' },
          el('button', { clase: 'enlace-fila', type: 'button', 'aria-label': `Abrir pedido ${p.folio}`,
            onclick: (e) => { e.stopPropagation(); abrir(); } }, p.folio)),
        el('td', { 'data-etiqueta': 'Fecha', clase: 'suave' }, formatear(fechaCorta, p.creado_en)),
        el('td', { 'data-etiqueta': 'Cliente' }, p.nombre),
        el('td', { 'data-etiqueta': 'Producto' }, `${p.cantidad} × ${p.producto_nombre}`),
        el('td', { 'data-etiqueta': 'Total', clase: 'num' }, dinero.format(p.total_mxn)),
        el('td', { 'data-etiqueta': 'Pago' }, insigniaPago(p.estado)),
        el('td', { 'data-etiqueta': 'Envío' }, insigniaEnvio(p)));
    }));

    const desde = (pagina - 1) * 25 + 1;
    $('paginacion-texto').textContent = `Mostrando ${desde}–${desde + pedidos.length - 1} de ${total}`;
    $('pagina-anterior').disabled = pagina <= 1;
    $('pagina-siguiente').disabled = pagina >= paginas;
    $('paginacion').hidden = paginas <= 1 && total <= 25;
  }

  // ───────── Detalle de un pedido ─────────
  async function abrirDetalle(id) {
    const dialogo = $('dialogo-detalle');
    $('detalle-contenido').replaceChildren(el('p', { clase: 'panel__cargando', texto: 'Cargando pedido…' }));
    if (!dialogo.open) dialogo.showModal();
    try {
      const pedido = await api('GET', `/pedidos/${encodeURIComponent(id)}`);
      dibujarDetalle(pedido);
    } catch (error) {
      if (error.estado === 401) return sesionTerminada();
      dialogo.close();
      avisar(error.message, { error: true });
    }
  }

  function seccion(titulo, ...contenido) {
    return el('section', { clase: 'seccion' }, el('h3', { texto: titulo }), ...contenido);
  }

  function datos(...pares) {
    const dl = el('dl', { clase: 'datos' });
    for (const [etiqueta, valor, clase] of pares) {
      if (valor == null || valor === '') continue;
      dl.append(el('dt', { texto: etiqueta }), el('dd', { clase }, valor));
    }
    return dl;
  }

  function descripcionHistorial(h) {
    const quien = h.usuario ?? 'Stripe';
    const d = h.detalle || {};
    if (h.accion === 'actualizar_envio') {
      const de = ETIQUETA_ENVIO[d.de] ?? d.de;
      const a = ETIQUETA_ENVIO[d.a] ?? d.a;
      const guia = d.guia ? ` · guía ${d.guia}` : '';
      return d.de === d.a ? `${quien} cambió la guía de envío${guia}` : `${quien} cambió el envío de «${de}» a «${a}»${guia}`;
    }
    if (h.accion === 'reembolsar_pedido') {
      const monto = typeof d.total_mxn === 'number' ? ` ${dinero.format(d.total_mxn)}` : '';
      return `${quien} reembolsó${monto}${d.motivo ? ` · ${d.motivo}` : ''}`;
    }
    if (h.accion === 'reembolso_confirmado_stripe') return 'Stripe avisó de un reembolso hecho fuera de este sitio';
    return `${quien}: ${h.accion}`;
  }

  function dibujarDetalle(p) {
    estado.pedidoAbierto = p;
    const modo = estado.yo.pagos.modo;
    const pagado = p.estado === 'pagado';

    // Encabezado
    const encabezado = el('header', { clase: 'panel__encabezado' },
      el('div', {},
        el('h2', { id: 'detalle-titulo', texto: `Pedido ${p.folio}` }),
        el('div', { clase: 'panel__insignias' }, insigniaPago(p.estado), pagado ? insigniaEnvio(p) : null)),
      el('button', { clase: 'boton boton--texto', type: 'button', 'aria-label': 'Cerrar el pedido',
        onclick: () => $('dialogo-detalle').close() }, 'Cerrar ✕'));

    // Resumen
    const resumen = seccion('Pedido', datos(
      ['Producto', p.producto_nombre],
      ['Cantidad', String(p.cantidad)],
      ['Precio por pieza', dinero.format(p.precio_unitario_mxn)],
      ['Envío a domicilio', dinero.format(p.envio_mxn)],
      ['Total', dinero.format(p.total_mxn), 'total'],
      ['Creado', formatear(fechaLarga, p.creado_en)]));

    // Cliente y entrega
    const domicilio = [
      p.calle_numero, `Col. ${p.colonia}`, `${p.ciudad}, ${p.entidad}, C.P. ${p.codigo_postal}`,
    ].join('\n');
    const telefonoValido = /^[+]?[0-9]{10,15}$/.test(p.telefono);
    const copiar = el('button', { clase: 'boton boton--chico', type: 'button', onclick: async () => {
      try {
        await navigator.clipboard.writeText(`${p.nombre}\n${domicilio}\nTel. ${p.telefono}${p.referencias ? `\nRef.: ${p.referencias}` : ''}`);
        avisar('Datos de entrega copiados');
      } catch {
        avisar('No se pudo copiar. Selecciona el texto y cópialo a mano.', { error: true });
      }
    } }, 'Copiar datos de entrega');
    const entrega = seccion('Cliente y entrega', datos(
      ['Nombre', p.nombre],
      ['Teléfono', telefonoValido ? el('a', { clase: 'enlace', href: `tel:${p.telefono}` }, p.telefono) : p.telefono],
      ['Domicilio', domicilio, 'domicilio'],
      ['Referencias', p.referencias]), el('div', {}, copiar));

    // Envío
    const envio = seccion('Envío', ...bloqueEnvio(p));

    // Pago
    const intento = p.stripe_payment_intent_id;
    const enlaceStripe = intento && /^pi_[A-Za-z0-9_]+$/.test(intento) && modo !== 'apagado'
      ? el('a', { clase: 'enlace', href: `https://dashboard.stripe.com/${modo === 'prueba' ? 'test/' : ''}payments/${intento}`,
        target: '_blank', rel: 'noopener noreferrer' }, 'Abrir en Stripe')
      : null;
    const pago = seccion('Pago', datos(
      ['Estado', ETIQUETA_PAGO[p.estado]],
      ['Pagado', p.pagado_en ? formatear(fechaLarga, p.pagado_en) : null],
      ['Cobro en Stripe', intento ? el('span', {}, el('code', { clase: 'codigo', texto: intento }), enlaceStripe ? ' · ' : '', enlaceStripe) : null],
      ['Reembolsado', p.reembolsado_en ? formatear(fechaLarga, p.reembolsado_en) : null],
      ['Motivo del reembolso', p.reembolso_motivo],
      ['Reembolso en Stripe', p.stripe_refund_id ? el('code', { clase: 'codigo', texto: p.stripe_refund_id }) : null]));

    // Reembolso
    const secciones = [resumen, entrega, envio, pago];
    if (p.puede_reembolsar) {
      secciones.push(seccion('Reembolso',
        el('p', { clase: 'nota', texto: 'Devuelve el total del pedido (incluido el envío) a la tarjeta del cliente.' }),
        el('div', {}, el('button', { id: 'boton-reembolsar', clase: 'boton boton--peligro', type: 'button',
          onclick: () => pedirReembolso(p) }, 'Reembolsar pedido…'))));
    } else if (pagado) {
      const razon = estado.yo.rol !== 'administrativo'
        ? 'Solo una cuenta administrativa puede hacer reembolsos.'
        : 'Los pagos con Stripe están apagados en el servidor, por eso no se puede reembolsar.';
      secciones.push(seccion('Reembolso', el('p', { clase: 'nota', texto: razon })));
    }

    // Historial
    if (p.historial.length > 0) {
      secciones.push(seccion('Historial', el('ul', { clase: 'historial' }, p.historial.map((h) =>
        el('li', {}, el('span', { texto: descripcionHistorial(h) }), el('time', { datetime: h.fecha, texto: formatear(fechaLarga, h.fecha) }))))));
    }

    $('detalle-contenido').replaceChildren(encabezado, el('div', { clase: 'panel__cuerpo' }, secciones));
    $('dialogo-detalle').setAttribute('aria-labelledby', 'detalle-titulo');
  }

  function bloqueEnvio(p) {
    const actual = ENVIOS.indexOf(p.estado_envio);
    const pasos = el('ol', { clase: 'pasos', 'aria-label': 'Avance del envío' }, ENVIOS.map((e, i) =>
      el('li', { clase: `paso${i <= actual && p.estado !== 'pendiente' ? ' paso--hecho' : ''}`,
        'aria-current': i === actual ? 'step' : false },
        ETIQUETA_ENVIO[e],
        i === actual ? el('span', { clase: 'solo-lector', texto: ' (estado actual)' }) : null)));

    const fechas = datos(
      ['Guía', p.guia_envio],
      ['Enviado', p.enviado_en ? formatear(fechaLarga, p.enviado_en) : null],
      ['Entregado', p.entregado_en ? formatear(fechaLarga, p.entregado_en) : null]);

    if (p.estado === 'reembolsado') return [pasos, fechas, el('p', { clase: 'nota', texto: 'El pedido fue reembolsado: ya no se puede cambiar su envío.' })];
    if (p.estado !== 'pagado') return [el('p', { clase: 'nota', texto: 'El envío se maneja cuando el pedido ya está pagado.' })];

    const siguientes = ['preparando', 'enviado', 'entregado'].filter((e) => ENVIOS.indexOf(e) > actual);
    if (siguientes.length === 0) return [pasos, fechas, el('p', { clase: 'nota', texto: 'El pedido ya fue entregado.' })];

    const select = el('select', { id: 'envio-estado', name: 'estado_envio' },
      siguientes.map((e) => el('option', { value: e, texto: ETIQUETA_ENVIO[e] })));
    const guia = el('input', { id: 'envio-guia', name: 'guia', type: 'text', maxlength: '40', autocomplete: 'off',
      placeholder: 'Opcional', value: p.guia_envio ?? '' });
    const boton = el('button', { id: 'envio-guardar', clase: 'boton boton--primario', type: 'submit' }, 'Guardar envío');
    const error = el('p', { id: 'envio-error', clase: 'mensaje-error', role: 'alert', hidden: true });
    const formulario = el('form', { clase: 'formulario-envio', novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      error.hidden = true;
      boton.disabled = true;
      boton.textContent = 'Guardando…';
      try {
        const cuerpo = { estado_envio: select.value };
        if (guia.value.trim()) cuerpo.guia = guia.value.trim();
        const nuevo = await api('POST', `/pedidos/${encodeURIComponent(p.id)}/envio`, cuerpo);
        dibujarDetalle(nuevo);
        avisar(`Envío actualizado: ${ETIQUETA_ENVIO[nuevo.estado_envio]}`);
        cargarLista();
      } catch (err) {
        if (err.estado === 401) return sesionTerminada();
        error.textContent = err.message;
        error.hidden = false;
        boton.disabled = false;
        boton.textContent = 'Guardar envío';
      }
    } },
    el('label', { clase: 'campo', for: 'envio-estado' }, 'Nuevo estado', select),
    el('label', { clase: 'campo', for: 'envio-guia' }, 'Número de guía', guia),
    boton);

    // Estando "enviado", además de «Entregado» solo tiene sentido corregir la guía.
    let ayudaGuia = null;
    if (p.estado_envio === 'enviado') {
      select.append(el('option', { value: 'enviado', texto: 'Enviado (corregir guía)' }));
      ayudaGuia = el('p', { clase: 'nota', texto: 'Para corregir la guía, elige «Enviado (corregir guía)» y escribe la nueva.' });
    }
    return [pasos, fechas, formulario, error, ayudaGuia];
  }

  // ───────── Reembolso ─────────
  function pedirReembolso(p) {
    $('reembolso-texto').textContent =
      `Se devolverán ${dinero.format(p.total_mxn)} MXN del pedido ${p.folio} (${p.nombre}) a su tarjeta, `
      + 'envío incluido. Esta acción no se puede deshacer.';
    $('reembolso-motivo').value = '';
    $('reembolso-error').hidden = true;
    $('reembolso-confirmar').disabled = false;
    $('reembolso-confirmar').textContent = 'Sí, reembolsar';
    $('reembolso-cancelar').disabled = false;
    $('dialogo-reembolso').showModal();
    $('reembolso-cancelar').focus(); // el foco empieza en la opción segura
  }

  async function confirmarReembolso(evento) {
    evento.preventDefault();
    const p = estado.pedidoAbierto;
    if (!p) return;
    const boton = $('reembolso-confirmar');
    const error = $('reembolso-error');
    error.hidden = true;
    boton.disabled = true;
    $('reembolso-cancelar').disabled = true;
    boton.textContent = 'Reembolsando…';
    try {
      const motivo = $('reembolso-motivo').value.trim();
      const nuevo = await api('POST', `/pedidos/${encodeURIComponent(p.id)}/reembolso`, motivo ? { motivo } : {});
      $('dialogo-reembolso').close();
      dibujarDetalle(nuevo);
      avisar(`Reembolso hecho: ${dinero.format(nuevo.total_mxn)}`);
      cargarLista();
    } catch (err) {
      if (err.estado === 401) return sesionTerminada();
      error.textContent = err.message;
      error.hidden = false;
      boton.disabled = false;
      boton.textContent = 'Sí, reembolsar';
      $('reembolso-cancelar').disabled = false;
    }
  }

  // ───────── Eventos de la página ─────────
  $('form-login').addEventListener('submit', async (e) => {
    e.preventDefault();
    const boton = $('login-boton');
    const error = $('login-error');
    error.hidden = true;
    const usuario = $('login-usuario').value.trim();
    const contrasena = $('login-contrasena').value;
    if (!usuario || !contrasena) {
      error.textContent = 'Escribe tu usuario y tu contraseña';
      error.hidden = false;
      return;
    }
    boton.disabled = true;
    boton.textContent = 'Entrando…';
    try {
      await api('POST', '/sesion', { usuario, contrasena });
      $('login-contrasena').value = '';
      await iniciarApp(await api('GET', '/yo'));
    } catch (err) {
      error.textContent = err.message;
      error.hidden = false;
      $('login-contrasena').select();
    } finally {
      boton.disabled = false;
      boton.textContent = 'Entrar';
    }
  });

  $('boton-salir').addEventListener('click', async () => {
    try { await api('DELETE', '/sesion'); } catch { /* aunque falle, se sale de la pantalla */ }
    estado.yo = null;
    mostrarLogin();
  });

  $('boton-actualizar').addEventListener('click', cargarLista);
  $('pagina-anterior').addEventListener('click', () => { estado.pagina = Math.max(1, estado.pagina - 1); cargarLista(); });
  $('pagina-siguiente').addEventListener('click', () => { estado.pagina += 1; cargarLista(); });

  let esperaBusqueda;
  $('busqueda').addEventListener('input', (e) => {
    clearTimeout(esperaBusqueda);
    esperaBusqueda = setTimeout(() => { estado.q = e.target.value.trim(); estado.pagina = 1; cargarLista(); }, 300);
  });

  // Cerrar el panel al hacer clic en el fondo oscuro.
  $('dialogo-detalle').addEventListener('click', (e) => { if (e.target === e.currentTarget) e.currentTarget.close(); });
  $('dialogo-detalle').addEventListener('close', () => { estado.pedidoAbierto = null; });
  $('form-reembolso').addEventListener('submit', confirmarReembolso);
  $('reembolso-cancelar').addEventListener('click', () => $('dialogo-reembolso').close());

  // Al volver a la pestaña, si la lista tiene más de medio minuto, se actualiza sola.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && estado.yo && Date.now() - estado.ultimaCarga > 30_000) cargarLista();
  });

  // ───────── Arranque: ¿ya hay sesión? ─────────
  (async () => {
    try {
      await iniciarApp(await api('GET', '/yo'));
    } catch (error) {
      mostrarLogin(error.estado === 401 || error.estado == null ? '' : error.message);
    }
  })();
})();
