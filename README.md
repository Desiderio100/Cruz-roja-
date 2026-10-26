# App Cruz Roja · Equipo El Rebaño

App para iPhone (SwiftUI, iOS 17+) para Cruz Roja Mexicana · Monterrey, con su backend (Node) y su base de datos (MySQL en Aiven).

```
CruzRoja.xcodeproj    proyecto de Xcode
CruzRoja/             la app (carpeta sincronizada: lo que pongas aquí, Xcode lo incluye solo)
CruzRoja-Info.plist   permiso para hablar por http con el backend en tu red (solo desarrollo)
Simulacion/           recorrido GPS de prueba por Monterrey (.gpx)
backend/              API ÚNICA en Node: una ruta por pantalla (incluye el registro con SMS)
db/                   scripts SQL de la base (ver db/LEEME.md)
```

La app **nunca** se conecta a MySQL: habla con el backend (`/api/...`) y el backend habla con la base.

## Abrir y correr

**Solo la app** (sin servidor): doble clic en `CruzRoja.xcodeproj`, elige un iPhone del simulador y ⌘R.
En *Crea tu cuenta* toca **Omitir por ahora** dos veces y entras. Centro más cercano, Capacitación
y el respaldo de Emergencia funcionan sin servidor.

**Con todo** (registro con SMS, Emergencia, Agenda de citas, Productos con causa) necesitas además el backend corriendo en el mismo Mac:

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
├── Capacitacion/               ← Capacitación: cursos + "Aprende" (Desiderio)
├── Citas/                      ← Agenda de citas, Mis citas, Cancelar (Luis)
├── Ventas/                     ← Productos con causa (Sebastián)
└── Emergencia/                 ← Botón de emergencia, llamada y respaldo sin internet (a2)
backend/
├── src/server.js               ← crea el servidor y monta las rutas de cada pantalla
├── src/db.js                   ← UN pool de MySQL + llamar() para procedimientos (CALL ...)
├── src/errores.js              ← ErrorHttp y manejador único de errores
├── src/sms.js                  ← envío de SMS (consola, Twilio o app Mensajes)
├── src/rutas/                  ← productos, citas, dispositivos, llamadas, registro, consentimientos
├── imagenes/                   ← fotos de productos (se sirven en /img/...)
└── scripts/probar.js           ← `npm run probar`
```
(el logo va en Assets.xcassets › LogoCruzRoja; si no hay imagen, se dibuja la cruz)

| Pantalla | Dueño | App | Backend |
|---|---|---|---|
| Registro, SMS y permisos (HU01) | autor de HU01 | `Registro/` | `rutas/registro.js`, `rutas/consentimientos.js`, `sms.js` |
| Centro más cercano (HU11) | Desiderio | `CentroCercano/` | No usa (lee `centros.json`) |
| Capacitación (HU14) | Desiderio | `Capacitacion/` | No usa (cursos de ejemplo) |
| Agenda de citas | Luis | `Citas/` | `rutas/citas.js`, `rutas/dispositivos.js` |
| Productos con causa | Sebastián | `Ventas/` | `rutas/productos.js` |
| Emergencia y llamada | a2 | `Emergencia/` | `rutas/llamadas.js` |

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
5. Si necesitas tablas o procedimientos nuevos, guárdalos como un script numerado en `db/` (p. ej. `07_...sql`) para que todos puedan reproducirlos.

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
- *Cursos*: **Mis inscripciones** (con folio) arriba y los próximos cursos con fecha y lugares. Inscripción con folio de confirmación (nombre y celular ya vienen llenos si te registraste); si está lleno no deja inscribirse. Cursos de ejemplo por ahora (`Curso.ejemplos`); el lugar para conectar el backend está marcado en `CapacitacionModelo.swift`.
- *Aprende*: lo básico que todos deberíamos saber (pedir ayuda, RCP, atragantamiento, hemorragias, posición lateral, quemaduras) con los pasos siempre abiertos y un video de YouTube por tema. Para cambiar un video, edita `videoID` en `Tema.swift`.

| Capacitación | Con internet | Sin internet |
|---|---|---|
| Ver cursos | Sí | Sí, con aviso "los lugares pueden haber cambiado" |
| Inscribirse | Sí | No, botón apagado (el cupo vive en el servidor) |
| Mis inscripciones | Sí | Sí, guardadas en el teléfono |
| Pasos de Aprende | Sí | Sí, texto dentro de la app |
| Videos | Sí | No, aviso "Necesitas internet" |

**Agenda de citas**: nutrición y psicología: elegir día y horario libre, confirmar, ver *Mis citas*, cancelar y elegir nuevo horario cuando una cita queda pospuesta. Si la persona no se registró, la primera vez pide nombre y teléfono. Cada ruta del backend llama a un procedimiento almacenado de la base. Una cita solo la ve y la modifica el dispositivo que la creó (header `X-Dispositivo-Id`). Necesita internet y el backend.

**Productos con causa**: catálogo desde la tabla `producto` (solo activos, solo enlaces `https`), con foto. *Comprar* abre el canal oficial de Cruz Roja en el navegador; la app no procesa pagos. Necesita internet y el backend.

**Emergencia**: el botón rojo de la pantalla principal toma tu ubicación (`Ubicacion`), la manda al backend y este elige la delegación activa más cercana (función `distancia_km` de la base), crea la llamada y su ficha, y la app abre la pantalla de llamada. Si hay nombre y teléfono guardados (`Perfil`), también se envían. **La pantalla de llamada todavía es maqueta**: registra la llamada en la base, pero no hay audio ni video reales.

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

- Las rutinas SQL de citas y dispositivos (`dispositivo_registrar`, `citas_del_dispositivo`, `cita_agendar`, `cita_cancelar`, `cita_reprogramar`) existen en Aiven pero **no** están en `db/`. Luis debe exportarlas a `db/07_citas_rutinas.sql`.
- Los centros viven en dos lugares: `centros.json` (app) y la tabla `delegacion` (base). Citas usa una delegación fija (`Configuracion.delegacionId`) y Emergencia elige la más cercana en el servidor. Falta el endpoint de delegaciones para que la app use la misma fuente.
- Emergencia: nadie la protege contra llamadas falsas (solo el límite de 60 peticiones por minuto por IP). Es una decisión de seguridad pendiente.
- Registro: los códigos SMS viven en la memoria del servidor (si se reinicia, hay que pedir otro). Con Twilio de prueba no llegan SMS a celulares de México.
- Las fotos de productos se sirven por `http://localhost` (solo desarrollo): en producción deben estar en una dirección `https://`.
- `Configuracion.urlDonar` apunta al sitio general de Cruz Roja Mexicana; cambiarlo por la página de donativos que indique el socio formador.
