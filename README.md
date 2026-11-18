# App Cruz Roja · Equipo El Rebaño

App para iPhone (SwiftUI, iOS 17+) para Cruz Roja Mexicana · Monterrey, con su backend (Node) y su base de datos (MySQL en Aiven).

```
CruzRoja.xcodeproj    proyecto de Xcode
CruzRoja/             la app (carpeta sincronizada: lo que pongas aquí, Xcode lo incluye solo)
CruzRoja-Info.plist   permiso para hablar por http con el backend en tu red (solo desarrollo)
Simulacion/           recorrido GPS de prueba por Monterrey (.gpx)
backend/              API ÚNICA en Node: una ruta por pantalla (incluye el registro con SMS)
db/                   scripts SQL de la base (ver db/LEEME.md)
docs/                 diagramas de diseño y documentos de pruebas del sprint
personal/             panel web del personal (llamadas y citas, entrada con matrícula), servidor aparte en el puerto 4000
```

La app **nunca** se conecta a MySQL: habla con el backend (`/api/...`) y el backend habla con la base.

## Abrir y correr

**Solo la app** (sin servidor): doble clic en `CruzRoja.xcodeproj`, elige un iPhone del simulador y ⌘R.
En *Crea tu cuenta* toca **Omitir por ahora** dos veces y entras. Centro más cercano, la pestaña
*Aprende* de Capacitación y el respaldo de Emergencia funcionan sin servidor.

**Con todo** (registro con SMS, Emergencia, Agenda de citas, cursos de Capacitación, Productos con causa) necesitas además el backend corriendo en el mismo Mac:

1. Node.js 20.6 o superior (`node -v` en Terminal).
2. En Terminal (o en la terminal de VS Code):
   ```bash
   cd backend
   npm install
   ```
3. Revisa que existan `backend/.env` (llaves de Aiven y Twilio) y `backend/ca.pem` (certificado de Aiven).
   En Mac el `.env` no se ve en Finder; ábrelo desde VS Code. **Ninguno de los dos se sube a GitHub.**
   Si no los tienes: `cp .env.example .env`, llena tu `DB_USER` (`dev_tunombre`) y `DB_PASSWORD` (te la da quien
   administra Aiven, **en privado**), y descarga `ca.pem` de la consola de Aiven (el servicio → *Connection
   information* → *CA certificate*).
4. `npm run dev` → debe decir *API escuchando en el puerto 3000*. Déjalo abierto.
5. En otra Terminal, dentro de `backend/`: `npm run probar` → todas las pruebas deben salir bien (solo lee, no escribe).
6. En Xcode, ⌘R. El simulador usa `http://localhost:3000` (`CruzRoja/Comun/Configuracion.swift`).

**Registro con SMS:** con `SMS_MODO=twilio` el backend manda el SMS con Twilio. Si Twilio no puede
(la cuenta de prueba no envía a celulares de México sin verificar), con `SMS_RESPALDO_CONSOLA=si` el código
sale en la terminal de `npm run dev` (línea `[SMS a +52...] Tu código de Cruz Roja es 123456`) y lo escribes
en la app. Con `SMS_MODO=consola` nunca se manda SMS. Ver `backend/README.md`.

Para el botón de **Emergencia** en el simulador necesitas una ubicación: menú *Features › Location › Custom Location…* (o el interruptor *Simular recorrido por Monterrey* de Centro más cercano), y aceptar el permiso de ubicación. Sin backend, el botón abre el **respaldo telefónico**.

Para un iPhone real: en `Configuracion.swift` cambia `localhost` por la IP de tu Mac (misma red Wi-Fi) y en *Signing & Capabilities* elige tu equipo.

**Para probar el registro otra vez:** botón de la persona (arriba a la derecha) → *Reiniciar configuración inicial*.

**Pruebas unitarias:** en Xcode, ⌘U corre el target `CruzRojaTests` (Swift Testing). No necesita internet ni el backend.

**Pagos con Stripe:** para comprar de verdad en modo de prueba hace falta una cuenta de Stripe, llenar tres variables en `backend/.env`, correr `stripe listen` y agregar el paquete de Stripe en Xcode (una vez). Todo paso a paso en [`PAGOS_STRIPE.md`](PAGOS_STRIPE.md). Sin eso la app y el servidor funcionan igual; solo que *Comprar* avisa que la compra no está disponible por ahora y ofrece *Reintentar* (no manda a ningún otro sitio).

**Sitio de administración de pedidos** (para el personal de Cruz Roja): el mismo servidor sirve una página web en `http://localhost:3000/admin/` donde cada persona entra con su usuario y contraseña, ve y filtra los pedidos, marca el envío y reembolsa por Stripe. Se enciende con `ADMIN_SESION_SECRETO` en `backend/.env`, las cuentas se crean con `npm run crear:personal` y la base necesita `db/09_pedidos_admin.sql`. Pasos y reglas en [`PAGOS_STRIPE.md`](PAGOS_STRIPE.md) (paso 8 y sección 3).

**Panel del personal: llamadas y citas** (RF31 a RF33, carpeta `personal/`): otro sitio web, aparte, para el CECOM. El **operador** ve la llamada entrante de su delegación con la ficha (editable), la ubicación, la transcripción y las llamadas perdidas; el **administrativo** ve las citas del día por especialista y puede posponerlas. Se entra con **matrícula** (25 letras y números; en la base solo se guarda su huella SHA-256). Usa la misma base de datos y no comparte código ni sesión con el backend:

```bash
cd personal
cp .env.example .env      # llena DB_USER / DB_PASSWORD (pueden ser los mismos de backend/.env) y SESION_SECRETO
cp ../backend/ca.pem .    # el mismo certificado de Aiven
npm install
npm run dev               # http://localhost:4000/
```

Las dos entradas conviven sobre la misma tabla `personal`: las cuentas con matrícula entran al panel de llamadas y citas; las de usuario y contraseña, al sitio de pedidos. Con `PANEL_PERSONAL_URL=http://localhost:4000/` en `backend/.env`, el sitio de pedidos muestra un enlace al panel. Lo que el panel necesita en la base está en `db/10_modo_personal.sql` (en Aiven ya está).

## Cómo está organizado

```
CruzRoja/
├── App/
│   ├── CruzRojaApp.swift       ← arranque; crea lo compartido y elige pantalla:
│   │                             Crea tu cuenta → Permisos → Pantalla principal
│   ├── PantallaPrincipal.swift ← no hace falta tocarlo
│   ├── BotonesInicio.swift     ← Emergencia y Donar
│   └── Secciones.swift         ← AQUÍ agregas tu pantalla (una entrada)
├── Comun/                      ← lo que puede usar cualquiera
│   ├── Estilo.swift            ← EL estilo de la app: rojo, botones, tarjetas, campos, logo
│   ├── ClienteAPI.swift        ← cliente del backend (id del dispositivo, errores, reintento)
│   ├── Configuracion.swift     ← dirección del backend y ajustes (UN solo lugar)
│   ├── Dispositivo.swift       ← id de este iPhone ante el servidor + Perfil (nombre/teléfono, en el Llavero)
│   ├── Ubicacion.swift         ← GPS y permiso de ubicación (uno para toda la app)
│   ├── AvisoPermisoUbicacion.swift ← aviso listo para pedir permiso de ubicación
│   ├── Internet.swift          ← ¿hay conexión? (uno para toda la app)
│   ├── AvisoSinInternet.swift  ← franja "Sin internet · …" para cualquier pantalla
│   └── Telefono.swift          ← para hacer llamadas
├── Registro/                   ← HU01: Crea tu cuenta, verificación SMS, Permisos, Mi perfil
├── CentroCercano/              ← Centro más cercano (Desiderio)
├── Capacitacion/               ← Capacitación: cursos e inscripciones (con el backend) + "Aprende" (Desiderio)
├── Citas/                      ← Agenda de citas, Mis citas, Cancelar (Luis)
├── Ventas/                     ← Productos con causa + compra con pago en la app (Sebastián)
└── Emergencia/                 ← Botón de emergencia, llamada y respaldo sin internet (Ayhan)
backend/
├── src/server.js               ← crea el servidor y monta las rutas de cada pantalla
├── src/db.js                   ← UN pool de MySQL + llamar() para procedimientos (CALL ...)
├── src/errores.js              ← ErrorHttp y manejador único de errores
├── src/sms.js                  ← envío de SMS (consola, Twilio o app Mensajes)
├── src/stripe.js               ← configuración de Stripe (llaves del .env)
├── src/admin/                  ← sitio de administración: inicio de sesión del personal y API (/admin/api)
├── src/rutas/                  ← productos, pedidos, stripeWebhook, citas, cursos, dispositivos, llamadas, registro, consentimientos
├── publico/admin/              ← el sitio de administración (HTML, CSS y JS; se abre en /admin/)
├── imagenes/                   ← fotos de productos (se sirven en /img/...)
├── test/                       ← pruebas automáticas de pagos, administración, citas, cursos y transcripción (`npm run probar:todo`)
└── scripts/                    ← `probar.js` (`npm run probar`) y `crear_personal.js` (`npm run crear:personal`)
```
(el logo va en Assets.xcassets › LogoCruzRoja; si no hay imagen, se dibuja la cruz)

| Pantalla | Dueño | App | Backend |
|---|---|---|---|
| Registro, SMS y permisos (HU01) | autor de HU01 | `Registro/` | `rutas/registro.js`, `rutas/consentimientos.js`, `sms.js` |
| Centro más cercano (HU11) | Desiderio | `CentroCercano/` | No usa (lee `centros.json`) |
| Capacitación (HU14) | Desiderio | `Capacitacion/` | `rutas/cursos.js` (cursos e inscripciones); *Aprende* no usa servidor |
| Agenda de citas | Luis | `Citas/` | `rutas/citas.js`, `rutas/dispositivos.js` |
| Productos con causa, compra con Stripe y sitio de administración de pedidos | Sebastián | `Ventas/` | `rutas/productos.js`, `rutas/pedidos.js`, `rutas/stripeWebhook.js`, `stripe.js`, `admin/`, `publico/admin/` |
| Emergencia y llamada | Ayhan Ben Halima Martinez · A01647593 | `Emergencia/` | `rutas/llamadas.js` |

## Agregar tu función

**App (3 pasos)**

1. Crea tu carpeta: `CruzRoja/MiFuncion/` y adentro tu vista, p. ej. `MiFuncionView.swift`.
   Xcode la agrega sola (la carpeta está sincronizada), no hay que tocar el proyecto.
   Ojo: **dos archivos no pueden llamarse igual** aunque estén en carpetas distintas.
2. Abre `App/Secciones.swift` y copia el bloque comentado:
   ```swift
   Seccion("Mi función",
           detalle: "Qué hace, en una línea",
           icono: "star.fill",
           responsable: "Tu nombre") {
       MiFuncionView()
   },
   ```
3. ⌘R. Tu fila ya aparece en *Accesos rápidos*.

Cada quien edita **solo su carpeta y su entrada en `Secciones.swift`**, así casi no hay conflictos en Git.
Tu pantalla **no** crea otro `NavigationStack` ni otro `@main`, y usa `.pantalla("Título")` (ver Estilo).

**Backend (si tu pantalla usa datos del servidor)**

1. Copia `backend/src/rutas/productos.js` como `backend/src/rutas/<tu-pantalla>.js` y cambia las rutas.
2. En `backend/src/server.js` impórtalo y móntalo en la sección `PANTALLAS`:
   `app.use('/api/<tu-pantalla>', rutas<TuPantalla>(pool));`
3. Usa el `pool` que recibes (no abras otra conexión). Para procedimientos almacenados: `llamar(pool, 'CALL ...', [..])` de `src/db.js`. Errores esperados: `throw new ErrorHttp(400, 'mensaje en español')` (ver `src/errores.js`).
4. En la app, agrega tus llamadas en tu carpeta con `extension ClienteAPI { ... }` (como `Citas/ClienteAPI+Citas.swift`): ya trae el id del dispositivo y los mensajes de error.
5. Si necesitas tablas o procedimientos nuevos, guárdalos como un script numerado en `db/` (p. ej. `13_...sql`; ya existen hasta el `12`) para que todos puedan reproducirlos.

## Estilo (todas las pantallas se ven igual)

Todo sale de `Comun/Estilo.swift`. **No crees colores ni botones propios.**

| Para | Usa |
|---|---|
| El rojo | `Color.rojoCruzRoja` (#B0241A, de las maquetas; es el único rojo) |
| Título de la pantalla | `.pantalla("Título")` (o `.pantalla("Título", grande: false)` si hay un mapa arriba) |
| Botón principal | `.buttonStyle(BotonRojo())` |
| Botón secundario | `.buttonStyle(BotonBorde())` |
| Enlace ("Omitir por ahora") | `.buttonStyle(BotonTexto())` |
| Bloque de información | `.tarjeta()` (gris) |
| Elemento de una lista | `.tarjetaConBorde()` (blanca con borde) |
| Campo de texto | `Campo("Nombre") { TextField(...) }` |
| Opción para elegir | `.ficha(seleccionada:)` |
| Logo | `LogoCruzRoja()` |
| Márgenes y esquinas | `Medida.margen`, `Medida.radio` |

Las fuentes son las del sistema (`.headline`, `.subheadline`, `.footnote`…), no tamaños fijos: así crecen con el texto grande de Accesibilidad y la app funciona en modo oscuro.

## Usar lo compartido

**Ubicación** (no crees tu propio `CLLocationManager`):
```swift
@Environment(Ubicacion.self) private var ubicacion

ubicacion.coordenada     // CLLocationCoordinate2D?: dónde está el usuario
ubicacion.tienePermiso   // Bool
ubicacion.pedirPermiso() // muestra la alerta de iOS
```

**Pedir permiso con un aviso ya hecho** (botón "Permitir" o "Abrir Ajustes"):
```swift
AvisoPermisoUbicacion(motivo: "para enviar tu ubicación al operador")
```

**Centro más cercano y su número** (solo la copia de la app, `centros.json`):
```swift
if let punto = ubicacion.coordenada, let centro = Centro.masCercano(a: punto) {
    centro.telefono
}
```

**Llamar:**
```swift
Link("Llamar", destination: Telefono.url(numero))
```

**Datos de la persona:** `Perfil.nombre` y `Perfil.telefono` (los llena el registro; están en el Llavero). Para saber si verificó su número: `@Environment(SesionUsuario.self)` → `sesion.telefonoVerificado`.

**Hablar con el backend:** `ClienteAPI.compartido.pedir("GET", "/api/...")`. Para identificar a esta instalación usa `try await Dispositivo.compartido.id()` (el mismo id para Registro, Citas y Emergencia; no inventes otro).

**Otro permiso** (cámara, micrófono, notificaciones): ya se piden en la configuración inicial (`Registro/GestorPermisos.swift`). Los textos de las alertas están en el target `CruzRoja` › Build Settings › *Privacy - … Usage Description*.

## Qué hace cada función

**Configuración inicial (HU01)**. La primera vez que se abre la app:
1. *Crea tu cuenta*: nombre y celular → *Continuar* manda un código de 6 dígitos por SMS.
2. *Verifica tu número*: el código vence en 5 minutos; se puede reenviar cada 60 s; 5 intentos fallidos lo invalidan. Si es correcto, el servidor guarda el teléfono verificado en el dispositivo (tabla `dispositivo`).
3. *Permisos*: ubicación, micrófono, cámara y notificaciones. Cada respuesta se guarda en la tabla `consentimiento` con la versión vigente del aviso de privacidad.

Todo es opcional: *Omitir por ahora* entra sin cuenta y la emergencia funciona igual. El nombre se queda solo en el iPhone (en el Llavero). Si el servidor no responde, la app sigue.

**Centro más cercano**: mapa satelital con todos los centros (el más cercano en rojo); tu centro más cercano con dirección, referencia ("Sobre Av. …"), una **flecha con km y sentido** ("a 2.3 km · adelante a la derecha") y si **te estás acercando o alejando**; *Cómo llegar* (Apple Maps, Google Maps o Waze); y la lista de todos los centros del más cercano al más lejano.

Sin internet: la lista, los km, la flecha y la referencia siguen funcionando (solo GPS y brújula). El mapa se ve gris pero con pines. Para rutas por calles sin internet, la app explica cómo descargar el mapa de Monterrey en Apple/Google Maps (*¿Rutas sin internet?*). En carro la flecha usa la dirección del GPS, no la brújula.

Para presentar: el interruptor **Simular recorrido por Monterrey** mueve tu ubicación poco a poco, como en carro. Para probar sin internet en el simulador, apaga el Wi-Fi de la Mac.

**Capacitación**. Dos pestañas:
- *Cursos*: **Mis inscripciones** (con folio) arriba y los próximos cursos con fecha y lugares. Los cursos se descargan del backend (`GET /api/cursos`) al entrar y al jalar la lista hacia abajo. Inscripción con folio de confirmación (nombre y celular ya vienen llenos si te registraste): la app manda la inscripción a `POST /api/cursos/:id/inscripciones` y el **servidor** revisa el cupo dentro de una transacción, así dos personas no se quedan con el último lugar; si está lleno no deja inscribirse. La última lista descargada y las inscripciones se guardan en el teléfono para verlas sin internet. Para tener varios cursos de ejemplo (uno lleno) corre `db/11_cursos_demo.sql`.
- *Aprende*: lo básico que todos deberíamos saber (pedir ayuda, RCP, atragantamiento, hemorragias, posición lateral, quemaduras) con los pasos siempre abiertos y un video de YouTube por tema. Para cambiar un video, edita `videoID` en `Tema.swift`.

| Capacitación | Con internet | Sin internet |
|---|---|---|
| Ver cursos | Sí, descargados del backend | Sí, la última lista guardada, con aviso "los lugares pueden haber cambiado" |
| Inscribirse | Sí | No, botón apagado (el cupo vive en el servidor) |
| Mis inscripciones | Sí | Sí, guardadas en el teléfono |
| Pasos de Aprende | Sí | Sí, texto dentro de la app |
| Videos | Sí | No, aviso "Necesitas internet" |

**Agenda de citas**: nutrición y psicología: elegir día y horario libre, confirmar, ver *Mis citas*, cancelar y elegir nuevo horario cuando una cita queda pospuesta. Si la persona no se registró, la primera vez pide nombre y teléfono. Cada ruta del backend llama a un procedimiento almacenado de la base. Una cita solo la ve y la modifica el dispositivo que la creó (header `X-Dispositivo-Id`). Necesita internet y el backend.

**Productos con causa**: catálogo desde la tabla `producto` (solo activos, solo enlaces `https`), con foto. *Comprar* abre la hoja de compra: cantidad, datos de envío a domicilio, total (producto + envío) y pago con tarjeta en la hoja de Stripe; al terminar muestra un folio (`PC-000012`). El precio lo calcula el servidor y el pedido solo pasa a «pagado» cuando Stripe avisa por el webhook; la app no guarda datos de tarjeta. Si los pagos no están activos (sin llaves de Stripe o sin el paquete en Xcode) avisa que la compra no está disponible por ahora y ofrece *Reintentar*; ya no redirige a ningún sitio externo. Los pedidos los administra el personal en el sitio `/admin/` del backend (ver más arriba). Necesita internet y el backend. **Cómo activarlo, probarlo y qué decidir con Cruz Roja: [`PAGOS_STRIPE.md`](PAGOS_STRIPE.md).**

**Emergencia**: el botón rojo de la pantalla principal toma tu ubicación (`Ubicacion`), la manda al backend y este elige la delegación activa más cercana (función `distancia_km` de la base), crea la llamada y su ficha, y la app abre la pantalla de llamada. Si hay nombre y teléfono guardados (`Perfil`), también se envían. Durante la llamada, lo que dice la persona se convierte en texto **en el iPhone** (framework Speech, `Emergencia/TranscriptorLlamada.swift`) y cada frase se manda al panel del operador (`POST /api/llamadas/:id/transcripcion`); al servidor solo llega texto, nunca audio. Si el iPhone no puede transcribir sin mandar el audio fuera del teléfono, o la persona niega el permiso, la llamada sigue igual y el operador llena la ficha a mano. Silenciar el micrófono también pausa la transcripción. El audio y el video hacia el operador todavía no existen: la cámara solo se ve en el teléfono.

**Respaldo sin internet**: si no hay internet, el servidor no responde o la ubicación está negada, el botón de Emergencia abre *Llamada por teléfono*: el centro más cercano (de `centros.json`, dentro de la app), su número y tus coordenadas GPS para dictárselas al operador. Mientras `Configuracion.directorioDePrueba` sea `true`, el botón **Llamar no marca** (los números son inventados).

**Donar**: abre el sitio oficial de Cruz Roja Mexicana (`Configuracion.urlDonar`).

## Datos de prueba

`centros.json` trae **nombres, coordenadas y teléfonos inventados**. Cambiarlos por
el directorio oficial de Cruz Roja antes de probar con usuarios, y solo entonces poner
`Configuracion.directorioDePrueba = false`. No marquen esos números desde un iPhone real.
Lo mismo con los datos de `db/02_datos_prueba.sql` y los enlaces de compra (`tienda.ejemplo.invalid`).

## Reglas de seguridad

- **Nunca** subas a GitHub el `.env`, ningún `.pem` ni respaldos de la base (ya están en `.gitignore`; si `git status` los muestra, detente y avisa).
- **Nunca** pegues contraseñas ni claves de Twilio en chats, issues ni commits. Si una se filtró, se cambia (borrar el mensaje no basta).
- En desarrollo cada quien usa su usuario `dev_<nombre>`. En producción el backend usa `cruzroja_app` (permisos mínimos).
- Al mandarle código a alguien, comprime sin secretos: `zip -r pantalla.zip carpeta -x "*/node_modules/*" -x "*.env" -x "*.pem" -x "*/.venv/*"`.

## Subirlo al repo

Desde la carpeta del proyecto, en la terminal de VS Code:
```bash
git status                 # NO deben salir .env, .pem, node_modules ni xcuserdata
git checkout -b integracion
git add .
git commit -m "Integración: HU01 + módulos + estilo único + backend único"
git push -u origin integracion
```
Luego abre el pull request en GitHub y, cuando el equipo lo revise, se une a `main`.

## Pendientes conocidos

- Las rutinas SQL de citas y dispositivos (`dispositivo_registrar`, `citas_del_dispositivo`, `cita_agendar`, `cita_cancelar`, `cita_reprogramar`) ya están en `db/07_citas_rutinas.sql`, escritas a partir de lo que la API manda y la app lee. No reemplazan las de Aiven (`CREATE PROCEDURE IF NOT EXISTS`). Falta que Luis las compare con las de Aiven (`SHOW CREATE PROCEDURE cita_agendar;`) y, si hay diferencias, deje en el archivo la versión de Aiven.
- Capacitación: la tabla `curso` no guarda duración ni costo, así que la app no los muestra en los cursos del servidor. Si Cruz Roja los necesita, hay que agregar esas columnas y mandarlas en `GET /api/cursos`. Todavía no se puede cancelar una inscripción desde la app.
- Los centros viven en dos lugares: `centros.json` (app) y la tabla `delegacion` (base). Citas usa una delegación fija (`Configuracion.delegacionId`) y Emergencia elige la más cercana en el servidor. Falta el endpoint de delegaciones para que la app use la misma fuente.
- Transcripción (HU09): ya llega el texto al panel del operador, pero la ficha todavía no se llena sola a partir de ese texto (extraer nombre, motivo, lesionados, etc.). En el simulador se usa el reconocimiento de Apple por internet porque no trae el modelo en el teléfono; la prueba completa es en un iPhone real.
- Emergencia: nadie la protege contra llamadas falsas (solo el límite de 60 peticiones por minuto por IP). Es una decisión de seguridad pendiente.
- Registro: los códigos SMS viven en la memoria del servidor (si se reinicia, hay que pedir otro). Con Twilio de prueba no llegan SMS a celulares de México.
- Las fotos de productos se sirven por `http://localhost` (solo desarrollo): en producción deben estar en una dirección `https://`.
- Pagos con Stripe: solo probados en modo de prueba. Falta definir con Cruz Roja el costo de envío (`ENVIO_MXN`), quién del personal atiende los pedidos y quién puede reembolsar, el aviso de privacidad con el domicilio y la cuenta de Stripe de la institución para cobrar de verdad. El sitio de administración solo hace reembolsos totales, los pedidos no se separan por delegación y las cuentas del personal se crean desde la terminal; en producción exige HTTPS. Ver `PAGOS_STRIPE.md` secciones 7 y 8.
- `Configuracion.urlDonar` apunta al sitio general de Cruz Roja Mexicana; cambiarlo por la página de donativos que indique el socio formador.
