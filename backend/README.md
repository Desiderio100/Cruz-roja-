# Backend de la app Cruz Roja (Node)

API única: una carpeta de rutas por pantalla (`src/rutas/`). La app de iPhone nunca habla con MySQL, solo con esta API.

| Ruta | Pantalla | Archivo |
|---|---|---|
| `GET /api/productos` | Productos con causa | `src/rutas/productos.js` |
| `GET /api/pedidos/condiciones`, `POST /api/pedidos`, `GET /api/pedidos/:id`, `POST /api/pedidos/:id/cancelar` | Compra con pago (Stripe) | `src/rutas/pedidos.js`, `src/stripe.js` |
| `POST /stripe/webhook` | Avisos de Stripe: pago exitoso, pago cancelado y reembolso (lo llama Stripe, no la app) | `src/rutas/stripeWebhook.js` |
| `/admin/` (página) y `/admin/api/…` | Sitio de administración de pedidos para el personal (sesión por persona) | `publico/admin/`, `src/admin/` |
| `GET/POST /api/citas…` | Agenda de citas | `src/rutas/citas.js` |
| `GET /api/cursos`, `GET /api/cursos/inscripciones`, `POST /api/cursos/:id/inscripciones` | Capacitación: cursos e inscripciones (HU14) | `src/rutas/cursos.js` |
| `POST /api/dispositivos` | Registro del dispositivo | `src/rutas/dispositivos.js` |
| `POST/PATCH /api/llamadas…`, `POST /api/llamadas/:id/transcripcion` | Emergencia, llamada y transcripción (HU09) | `src/rutas/llamadas.js` |
| `POST /api/registro/codigo`, `POST /api/registro/verificar` | Registro con SMS (HU01) | `src/rutas/registro.js`, `src/sms.js` |
| `POST /api/consentimientos` | Permisos (HU01) | `src/rutas/consentimientos.js` |
| `GET /salud`, `GET /img/…` | Revisión y fotos de productos | `src/server.js` |

## Correrlo en tu Mac (primera vez)

Necesitas Node.js 20.6 o superior (`node -v` en la Terminal de VS Code).

1. Abre la carpeta `backend` en VS Code (*File › Open Folder…*) y abre la terminal (*Terminal › New Terminal*).
2. `npm install` (solo la primera vez).
3. `cp .env.example .env`
4. Abre el archivo `.env` y llena **tus** datos:
   - `DB_USER` → tu usuario (`dev_tunombre`).
   - `DB_PASSWORD` → tu contraseña. Te la da quien administra Aiven, **en privado** (nunca por un chat de grupo).
   - Descarga `ca.pem` desde la consola de Aiven (el servicio → *Connection information* → *CA certificate*), ponlo en esta carpeta, y que `DB_CA_PATH` apunte a él (por defecto `./ca.pem`).
5. `npm run dev` → debe decir **API escuchando en el puerto 3000**. Déjala abierta.
6. En otra terminal (botón **+**), dentro de `backend`: `npm run probar` → todas las pruebas deben salir bien. Solo lee, no escribe en la base.

El simulador de Xcode usa `http://localhost:3000`, así que Xcode y este servidor deben estar en el mismo Mac.

## SMS del registro (HU01)

Antes era un servidor aparte en Python (`sms_backend.py`, puerto 8000). Ahora vive aquí, en la
misma API. `SMS_MODO` en `.env` elige cómo se manda el código:

| `SMS_MODO` | Qué hace |
|---|---|
| `consola` (por defecto) | **No manda SMS.** El código sale en esta terminal: `[SMS a +52...] Tu código de Cruz Roja es 123456`. Es el modo para desarrollar y presentar. |
| `twilio` | Manda SMS con Twilio. Llena `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` y `TWILIO_FROM` (o `TWILIO_VERIFY_SID` para Twilio Verify). La cuenta de prueba de Twilio no envía a celulares de México. |
| `mensajes` | Con la app Mensajes de la Mac donde corre el backend (solo macOS, sin comprobar). |

`SMS_RESPALDO_CONSOLA=si` (solo desarrollo): si el SMS falla, el código se imprime en la terminal y
la app sigue. Con `NODE_ENV=production` este respaldo se apaga solo.

Reglas: el código vence en 5 minutos, se puede pedir otro cada 60 s, 5 intentos fallidos lo
invalidan y cada código sirve una sola vez. El código **nunca** se devuelve en la respuesta.
Los códigos viven en memoria: si reinicias el servidor, pide otro.

## Pagos con Stripe (Productos con causa)

Guía completa, paso a paso: [`../PAGOS_STRIPE.md`](../PAGOS_STRIPE.md). Resumen:

| Variable (`.env`) | Qué es |
|---|---|
| `STRIPE_SECRET_KEY` | Llave secreta (`sk_test_...`). **Solo aquí**, nunca en la app ni en Git. Si está vacía, los pagos quedan apagados y lo demás sigue igual. |
| `STRIPE_PUBLISHABLE_KEY` | Llave publicable (`pk_test_...`). El servidor se la manda a la app con cada pedido. Debe ser del mismo modo que la secreta. |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...`. En desarrollo lo imprime `stripe listen --forward-to localhost:3000/stripe/webhook`. Sin él, ningún pedido pasa a «pagado». |
| `ENVIO_MXN` | Costo fijo del envío a domicilio, en pesos (por defecto 99; provisional). |

Reglas del servidor: el **precio sale de la tabla `producto`**, nunca de lo que mande la app; el pedido pasa a `pagado` **solo** cuando llega un aviso de Stripe con firma válida y con el mismo monto y moneda; un aviso repetido se ignora (tabla `evento_stripe`); `GET /api/pedidos/:id` solo lo ve el dispositivo que lo creó y no trae datos personales. Las tablas están en `../db/08_pedidos.sql` (corre después `03_permisos_app.sql` otra vez) y `../db/09_pedidos_admin.sql` (estado de envío y reembolso).

## Sitio de administración de pedidos

Para el personal de Cruz Roja: ver y filtrar pedidos, marcar el envío (por preparar → preparando → enviado → entregado) y reembolsar por Stripe. Guía completa: [`../PAGOS_STRIPE.md`](../PAGOS_STRIPE.md) (paso 8 y sección 3). Resumen:

| Variable (`.env`) | Qué es |
|---|---|
| `ADMIN_SESION_SECRETO` | Secreto con el que se firman las sesiones, **mínimo 32 caracteres** (genera uno con `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`). **Solo aquí**, nunca en Git. Si está vacío, el sitio queda apagado y lo demás sigue igual. |

- **Abrirlo:** `http://localhost:3000/admin/`.
- **Cuentas:** `npm run crear:personal` pregunta usuario, rol (`operador` o `administrativo`), delegación y contraseña, e imprime un `INSERT INTO personal …` que corres en Workbench. La contraseña no se guarda: solo su hash bcrypt. Para dar de baja: `UPDATE personal SET activo = 0 WHERE usuario = '…';` (pierde el acceso en el momento).
- **Roles:** `operador` ve pedidos y marca envíos; `administrativo` además reembolsa (solo reembolso total).
- **Seguridad:** sesión de 8 horas en cookie firmada `HttpOnly` y `SameSite=Strict` (`Secure` con `NODE_ENV=production`, por eso en producción necesita HTTPS); bloqueo de 15 minutos tras 5 contraseñas malas; los cambios exigen que la petición venga del mismo sitio; ver el detalle de un pedido (domicilio) y cada cambio quedan en `bitacora` con el nombre de quien los hizo.
- **Webhook:** además de `payment_intent.succeeded` y `payment_intent.canceled`, registra `charge.refunded` en el Dashboard de Stripe para que los reembolsos hechos allá también se reflejen (`stripe listen` ya reenvía todos).

## Panel del personal (llamadas y citas)

Es otro sitio aparte, en `../personal` (tiene su propio `npm run dev`, puerto 4000). Este backend no lo sirve ni comparte su sesión. Dos cosas de aquí lo tocan:

- `PANEL_PERSONAL_URL` en `.env` (opcional): muestra el enlace «Llamadas y citas» en la barra de `/admin/`. Solo acepta `http://` o `https://`.
- Las cuentas que solo tienen matrícula (sin contraseña) no entran a `/admin/`: reciben el mismo «Usuario o contraseña incorrectos» y no se les cuenta como intento fallido.

## Comandos

- `npm run dev` — servidor con tu `.env` y reinicio automático al guardar.
- `npm start` — servidor sin `.env` (producción: las variables las pone la plataforma).
- `npm run probar` — prueba rápida de solo lectura (`npm run probar -- http://192.168.1.20:3000` para otra dirección).
- `npm run probar:pagos` — 17 pruebas de los pagos contra un MySQL **local** y un Stripe falso (no llaman a internet). Necesita `.env.local` (copia `.env.local.example`); se niega a correr contra Aiven porque crea y borra datos.
- `npm run probar:admin` — 34 pruebas del sitio de administración (sesión, roles, filtros, envío, reembolsos, webhook de reembolso). Mismas condiciones que la anterior; deja unas filas en `bitacora` y `personal` (cuentas `prueba.*.pagos`) porque la bitácora no se puede borrar.
- `npm run probar:citas` — 7 pruebas de la Agenda de citas: el recorrido completo de una cita (agendar, verla, reprogramar y cancelar), horarios llenos y que solo el dispositivo dueño la modifica. Usa las rutinas de `db/07_citas_rutinas.sql`.
- `npm run probar:cursos` — 10 pruebas de Capacitación (HU14): lista de cursos, inscripción con folio, curso lleno, dos inscripciones al mismo tiempo por el último lugar y datos no válidos.
- `npm run probar:llamadas` — 5 pruebas de la transcripción de la llamada (HU09): las frases se guardan en orden y el operador las lee, solo el teléfono de la llamada puede escribir, una llamada terminada no acepta texto y un envío se guarda completo o nada. Usa `db/10_modo_personal.sql` y `db/12_transcripcion_app.sql`.
- `npm run probar:todo` — las 73 pruebas juntas (antes corre `db/07_citas_rutinas.sql`, `db/10_modo_personal.sql` y `db/12_transcripcion_app.sql` en tu MySQL local).
- `npm run crear:personal` — da de alta a una persona del personal (imprime el `INSERT` para Workbench).

## Agregar la ruta de tu pantalla

1. Copia `src/rutas/productos.js` como `src/rutas/<tu-pantalla>.js` y cambia las rutas.
2. En `src/server.js` impórtalo y móntalo en la sección `PANTALLAS`:
   `app.use('/api/<tu-pantalla>', rutas<TuPantalla>(pool));`
3. Usa el `pool` que recibes (no abras otra conexión). Para procedimientos almacenados: `llamar(pool, 'CALL ...', [..])` de `src/db.js`.
4. Errores esperados: `throw new ErrorHttp(400, 'mensaje en español')` (ver `src/errores.js`). Cualquier otro error se queda en el log y el cliente solo recibe un mensaje genérico.
5. Valida siempre en el servidor y usa parámetros (`?`), nunca armes SQL con texto del usuario.

## Reglas

- **Nunca** subas a GitHub el `.env` ni ningún `.pem` (ya están en `.gitignore`). Si `git status` los muestra, detente.
- En desarrollo usa tu `dev_<nombre>`. En producción el backend usa `cruzroja_app` (permisos mínimos) y `DB_CA_PATH` es obligatorio.
- Las fotos de `imagenes/` se sirven por `http://localhost` solo para desarrollo; en producción las fotos van en una dirección `https://`.
- Las tablas y procedimientos de la base viven en `../db/` (ver `../db/LEEME.md`).
