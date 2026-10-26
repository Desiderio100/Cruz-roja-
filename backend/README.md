# Backend de la app Cruz Roja (Node)

API única: una carpeta de rutas por pantalla (`src/rutas/`). La app de iPhone nunca habla con MySQL, solo con esta API.

| Ruta | Pantalla | Archivo |
|---|---|---|
| `GET /api/productos` | Productos con causa | `src/rutas/productos.js` |
| `GET/POST /api/citas…` | Agenda de citas | `src/rutas/citas.js` |
| `POST /api/dispositivos` | Registro del dispositivo | `src/rutas/dispositivos.js` |
| `POST/PATCH /api/llamadas…` | Emergencia y llamada | `src/rutas/llamadas.js` |
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

## Comandos

- `npm run dev` — servidor con tu `.env` y reinicio automático al guardar.
- `npm start` — servidor sin `.env` (producción: las variables las pone la plataforma).
- `npm run probar` — prueba rápida de solo lectura (`npm run probar -- http://192.168.1.20:3000` para otra dirección).

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
