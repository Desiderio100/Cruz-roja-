# Pagos con Stripe · Productos con causa

Con esto, la persona **compra dentro de la app**: elige cantidad, escribe su dirección, paga con tarjeta en la hoja de Stripe y recibe un folio. El pedido se envía **a domicilio**. Ya no se manda a nadie a otro sitio para comprar.

Y el personal de Cruz Roja tiene un **sitio web de administración** (`/admin`) donde ve y filtra todos los pedidos, marca el estado del envío y hace reembolsos por Stripe. Cada persona entra con su propio usuario y contraseña. Ver la sección 3.

> Todo está pensado para **modo de prueba** (no se cobra dinero real). Para cobrar de verdad hace falta la cuenta de Stripe **de Cruz Roja**, verificada. Ver la sección 8.

---

## 1. Cómo funciona (en 30 segundos)

```
 iPhone (app)                     Tu servidor (Node)                         Stripe
 ────────────                     ──────────────────                         ──────
 1. "Pagar $399" ───────────────▶ 2. Lee el PRECIO de MySQL (nunca de la app),
                                     guarda el pedido "pendiente" y
                                     le pide a Stripe un cobro ───────────▶ crea el cobro
 4. Abre la hoja de pago  ◀────── 3. Responde con client_secret + llave publicable
 5. La persona escribe su tarjeta ─────────────────────────────────────────▶ cobra
    (la tarjeta va DIRECTO a Stripe: ni la app ni tu servidor la ven)
                                  6. Stripe avisa por WEBHOOK  ◀───────────── "pago exitoso"
                                     (se comprueba la firma, el monto y la moneda)
                                     y recién ahí el pedido pasa a "pagado"
 7. La app pregunta "¿ya está pagado?" ──▶ el servidor contesta ──▶ "¡Gracias! Folio PC-000012"
```

Tres reglas que no se rompen:

1. **El precio lo pone el servidor.** La app solo manda qué producto y cuántos. Si alguien manda un precio falso, se ignora.
2. **"Pagado" solo lo dice Stripe** (por el webhook firmado). Que la app diga "ya pagué" no cambia nada.
3. **La tarjeta nunca pasa por nosotros.** Solo la ve la hoja de Stripe.

### Qué cambió en el proyecto

| Parte | Archivo | Qué hace |
|---|---|---|
| Base de datos | `db/08_pedidos.sql` | Tablas `pedido` (compra + dirección) y `evento_stripe` (avisos ya procesados) |
| Base de datos | `db/09_pedidos_admin.sql` | Agrega a `pedido` el estado de envío, la guía, el reembolso y sus reglas (para el sitio de administración) |
| Base de datos | `db/03_permisos_app.sql` | Le da a `cruzroja_app` permiso sobre las tablas nuevas (sin DELETE) |
| Servidor | `backend/src/stripe.js` | Lee las llaves del `.env` y crea el cliente de Stripe |
| Servidor | `backend/src/rutas/pedidos.js` | `POST /api/pedidos`, `GET /api/pedidos/:id`, `POST /api/pedidos/:id/cancelar`, `GET /api/pedidos/condiciones` |
| Servidor | `backend/src/rutas/stripeWebhook.js` | `POST /stripe/webhook`: recibe los avisos de Stripe (pago exitoso, pago cancelado y reembolso) |
| Servidor | `backend/src/admin/sesion.js`, `rutas.js` | Inicio de sesión del personal y la API del sitio de administración (`/admin/api/...`) |
| Servidor | `backend/publico/admin/` | El sitio de administración: `index.html`, `admin.css`, `admin.js` (se abre en `/admin/`) |
| Servidor | `backend/scripts/crear_personal.js` | Genera el `INSERT` para dar de alta a una persona del personal (`npm run crear:personal`) |
| Servidor | `backend/test/pagos.test.js`, `admin.test.js` | 17 + 34 pruebas automáticas (`npm run probar:todo`) |
| App | `CruzRoja/Ventas/CompraView.swift` | La hoja "Comprar": cantidad, dirección, total, botón Pagar, pantalla de gracias |
| App | `CruzRoja/Ventas/PagoViewModel.swift` | Toda la lógica y los estados de la compra |
| App | `CruzRoja/Ventas/PagoStripe.swift` | Único archivo que conoce el SDK de Stripe (abre la hoja de pago) |
| App | `CruzRoja/Ventas/Pedido.swift`, `PedidosRepositorio.swift`, `ClienteAPI+Pedidos.swift` | Modelos y llamadas al servidor |
| App | `CruzRoja/Ventas/ProductosCausaView.swift` | El botón **Comprar** ahora abre la hoja de compra (antes abría el navegador). Si la compra no está disponible, muestra un aviso con **Reintentar**; ya no manda a ningún otro sitio |
| App | `CruzRoja/App/CruzRojaApp.swift`, `CruzRoja-Info.plist` | Regreso a la app cuando el banco pide confirmar fuera de ella |
| App | `CruzRojaTests/PagosTests.swift` | Pruebas unitarias (⌘U) |

---

## 2. Ponerlo a funcionar en tu Mac

Hazlo en este orden. Son 8 pasos (el 8 es el sitio de administración).

### Paso 1 · Cuenta de Stripe en modo de prueba

1. Entra a <https://dashboard.stripe.com> y crea tu cuenta (correo y contraseña; **no** hace falta activar pagos reales).
2. Trabaja en un **entorno de prueba** (Stripe lo llama *sandbox* o *modo de prueba*): en el Dashboard debe verse la marca de prueba y las llaves empiezan con `pk_test_` / `sk_test_`. Si te ofrece crear un sandbox, créalo y úsalo.
3. Abre <https://dashboard.stripe.com/apikeys> (o *Desarrolladores › Claves de API*) y ten a la mano dos llaves:
   - **Llave publicable**: `pk_test_...` (esta sí puede ir en la app; el servidor se la manda).
   - **Llave secreta**: `sk_test_...` (botón *Crear clave secreta* si no la ves; solo se muestra una vez, **guárdala**).

> 🔒 La llave secreta es como una contraseña de tu dinero. **Nunca** en la app, en GitHub, en capturas de pantalla ni en un chat (tampoco conmigo). Solo va en el archivo `backend/.env`, que no se sube al repo.

### Paso 2 · Crear las tablas de pedidos

En MySQL Workbench, conectado como `avnadmin` (igual que en `db/LEEME.md`):

1. Corre `db/08_pedidos.sql` (File › Open SQL Script… › rayo amarillo solo). Todas las líneas deben salir con círculo verde.
2. Corre `db/09_pedidos_admin.sql` de la misma forma. Agrega a `pedido` lo que necesita el sitio de administración (estado de envío, guía, reembolso). Se puede repetir: si ya está aplicado, no hace nada.
3. Corre **otra vez** `db/03_permisos_app.sql`. Es lo que le da permiso a la app sobre las tablas nuevas (se puede repetir sin problema). El `09` no cambia permisos, así que si ya lo corriste después del `08`, no hace falta repetirlo.

El orden completo es **01, 02, 03, 08, 09** (el 03 otra vez después del 08).

Para comprobar: en Schemas › Refresh All debes ver `pedido` y `evento_stripe`, y en `pedido` las columnas `estado_envio`, `guia_envio` y `stripe_refund_id`.

### Paso 3 · Llenar `backend/.env`

Abre `backend/.env` con VS Code (en Mac no se ve en Finder). Si no tiene la sección de Stripe, copia estas líneas de `backend/.env.example` y llénalas:

```
STRIPE_SECRET_KEY=sk_test_...        ← tu llave secreta de prueba
STRIPE_PUBLISHABLE_KEY=pk_test_...   ← tu llave publicable de prueba
STRIPE_WEBHOOK_SECRET=               ← la llenas en el paso 4
ENVIO_MXN=99                         ← costo del envío en pesos (provisional)
ADMIN_SESION_SECRETO=                ← para el sitio de administración (paso 8)
```

Las dos llaves deben ser del **mismo modo** (las dos `_test_`). Si no, el servidor se niega a arrancar y dice por qué.

`ADMIN_SESION_SECRETO` lo llenas en el paso 8. Si lo dejas vacío, el sitio de administración queda apagado y todo lo demás funciona igual.

### Paso 4 · El webhook en tu Mac (Stripe CLI)

Stripe tiene que avisarle a tu servidor "ya se pagó". Como tu Mac no está en internet, el **Stripe CLI** hace de puente.

1. Instálalo. En la terminal de VS Code: `brew install stripe/stripe-cli/stripe`. (Si no tienes Homebrew, mira las otras opciones en <https://docs.stripe.com/stripe-cli/install>.)
2. `stripe login` → te abre el navegador; confirma. **Tiene que ser la misma cuenta** de las llaves del paso 1.
3. En una terminal **nueva** (botón **+**) y déjala abierta todo el tiempo que pruebes:
   ```bash
   stripe listen --forward-to localhost:3000/stripe/webhook
   ```
4. Te imprime algo como `Your webhook signing secret is whsec_...`. Copia ese `whsec_...` en `STRIPE_WEBHOOK_SECRET` del `.env`.

> Si cierras `stripe listen`, los pedidos se quedan en "Estamos confirmando tu pago" porque nadie avisa al servidor. Es lo primero que hay que revisar si algo no cierra.

### Paso 5 · Arrancar el servidor

En `backend/`: `npm install` (instala `stripe`) y luego `npm run dev`. Debe decir:

```
API escuchando en el puerto 3000
Pagos con Stripe en modo prueba, envío $99 MXN.
```

- Si dice *Pagos con Stripe APAGADOS* → falta `STRIPE_SECRET_KEY`.
- Si dice *AVISO: falta STRIPE_WEBHOOK_SECRET* → falta el paso 4.

### Paso 6 · Agregar el paquete de Stripe a Xcode (una sola vez)

Sin este paso la app **compila y funciona**, pero al tocar Comprar dice «La compra dentro de la app no está disponible por ahora» y ofrece **Reintentar**. No hay otro camino para comprar: sin este paquete no se puede pagar.

1. En Xcode: menú **File › Add Package Dependencies…**
2. Arriba a la derecha, en el buscador, pega: `https://github.com/stripe/stripe-ios-spm` y Enter.
3. Deja la regla que propone (*Up to Next Major Version*, con la versión más reciente) y pulsa **Add Package**. Tarda un poco en descargar.
4. En la lista de productos marca **StripePaymentSheet**, con *Add to Target* = **CruzRoja**, y pulsa **Add Package**.
5. ⌘B para compilar (la primera vez tarda varios minutos).
6. Se crea un archivo `Package.resolved` dentro de `CruzRoja.xcodeproj`. **Súbelo al repo** con el resto, para que todos usen la misma versión.

Fuente: documentación de Stripe para iOS (PaymentSheet).

### Paso 7 · Probar

1. En Xcode ⌘R. *Productos con causa* › **Comprar** en un producto.
2. Llena nombre, teléfono, dirección (el botón te dice qué falta) y toca **Pagar**.
3. En la hoja de Stripe usa una **tarjeta de prueba** (tabla de abajo): fecha cualquiera futura (por ejemplo `12/34`) y CVC cualquiera de 3 dígitos.
4. Debes ver **¡Gracias por tu compra!** con un folio `PC-000001`.
5. Comprueba por tres lados que cuadra:
   - En el Dashboard de Stripe (modo de prueba) › *Pagos*: aparece el pago.
   - En la terminal de `stripe listen`: ves los eventos con `200`.
   - En MySQL: `SELECT folio, estado, total_mxn, pagado_en FROM pedido ORDER BY creado_en DESC LIMIT 5;` → `pagado`.

**Tarjetas de prueba** (solo funcionan en modo de prueba; fuente: <https://docs.stripe.com/testing>):

| Para probar | Número |
|---|---|
| Pago exitoso | `4242 4242 4242 4242` |
| Tarjeta rechazada (genérica) | `4000 0000 0000 0002` |
| Rechazada por fondos insuficientes | `4000 0000 0000 9995` |
| Pide verificación 3D Secure | `4000 0027 6000 3184` |

En un **iPhone real**, la app habla con tu Mac por la IP de `Configuracion.swift` (como ya hacían las demás pantallas). El webhook no cambia: Stripe → CLI → `localhost` de tu Mac.

### Paso 8 · Encender el sitio de administración y crear cuentas

1. **Inventa el secreto de sesiones.** Sirve para firmar las sesiones del sitio; nadie lo escribe nunca. En la terminal, dentro de `backend/`:
   ```bash
   node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"
   ```
   Copia el texto que imprime en `ADMIN_SESION_SECRETO=` de `backend/.env`. Debe tener **al menos 32 caracteres** (el que genera ese comando tiene 43). Es secreto igual que las llaves de Stripe: no va a GitHub ni a un chat. Si lo cambias, todas las sesiones abiertas se cierran.
2. **Crea la cuenta de la primera persona.** En `backend/`: `npm run crear:personal`. Te pregunta, una por una:
   - *Usuario*: minúsculas, números, punto, guion o guion bajo, de 3 a 60 caracteres (por ejemplo `ana.lopez`).
   - *Rol*: `operador` o `administrativo` (ver la tabla de la sección 3).
   - *Delegación*: el número (`id`) de su delegación. Para verlo, en Workbench: `SELECT id, nombre FROM delegacion;`. Es solo para ubicar a la persona; los pedidos los ven todos.
   - *Contraseña* (mínimo 12 caracteres) y repetirla. **No se ve al escribirla.**
3. Al final imprime un `INSERT INTO personal (...) VALUES (...);`. **Cópialo y córrelo en Workbench** (con `avnadmin` o con tu usuario de desarrollo). Lo que lleva el `INSERT` no es la contraseña sino su «huella» (hash bcrypt); la contraseña no se guarda en ningún lado, así que **no se puede recuperar**. Si alguien la olvida, corre `npm run crear:personal` otra vez, copia solo el valor entre comillas de `hash_contrasena` (empieza con `$2b$12$`) y en Workbench: `UPDATE personal SET hash_contrasena = '<el hash>' WHERE usuario = 'ana.lopez';`.
4. Reinicia el servidor (`npm run dev`). Debe decir `Sitio de administración en http://localhost:3000/admin/`. Si dice *APAGADO*, falta `ADMIN_SESION_SECRETO`. Si el servidor no arranca y habla de `ADMIN_SESION_SECRETO`, tiene menos de 32 caracteres.
5. Abre <http://localhost:3000/admin/> en el navegador de tu Mac y entra con el usuario y la contraseña del paso 3.

> Para probarlo con datos: haz una compra de prueba (paso 7) y debe aparecer en la lista como **Por enviar**. Desde un celular de la misma red: `http://<IP-de-tu-Mac>:3000/admin/`. Eso es solo para desarrollo; en producción el sitio exige HTTPS (sección 8).

---

## 3. Sitio de administración (para el personal de Cruz Roja)

Es una página web que sirve el mismo servidor, en la dirección `/admin/`. No hay nada que instalar ni compilar. Se ve bien en computadora y en celular, y tiene modo oscuro.

**Qué se puede hacer**

| Función | Qué hace |
|---|---|
| Entrar | Usuario y contraseña **de cada persona**. No hay una cuenta compartida: todo queda a nombre de quien lo hizo. |
| Ver pedidos | Lista con folio, fecha, cliente, producto, total, estado de pago y estado de envío. 25 por página. |
| Filtrar | Por **Por enviar**, **Enviados**, **Entregados**, **Pendientes de pago**, **Cancelados**, **Reembolsados** o **Todos** (cada uno muestra cuántos hay). |
| Buscar | Por folio, nombre, teléfono o producto. Lo que se escriba se busca tal cual; los comodines (`%`, `_`) no hacen nada especial. |
| Ver un pedido | Panel con el producto, el cliente, el domicilio completo (con botón para copiarlo y teléfono que se puede llamar), el pago (con enlace al pago en el Dashboard de Stripe) y el **historial**: quién hizo qué y cuándo. |
| Marcar el envío | **Por preparar → Preparando → Enviado → Entregado**. Solo avanza (no se puede regresar), y se puede saltar un paso. Al marcar *Enviado* se puede escribir la guía de rastreo (3 a 40 letras, números, espacios o guiones); mientras esté en *Enviado* se puede corregir la guía. |
| Reembolsar | Devuelve **el total** del pedido al cliente por Stripe, con un motivo que se guarda. Pide confirmación y muestra el monto y el cliente. |

**Quién puede qué**

| Rol | Ver y filtrar | Ver domicilio | Marcar envío | Reembolsar |
|---|---|---|---|---|
| `operador` | Sí | Sí | Sí | **No** |
| `administrativo` | Sí | Sí | Sí | Sí |

**Estados de un pedido**

- *Pago*: `pendiente` (la persona está pagando o abandonó) → `pagado` (Stripe avisó) → `reembolsado`. También puede quedar `cancelado`.
- *Envío* (solo cuenta si está `pagado`): `por_preparar` → `preparando` → `enviado` → `entregado`. Un pedido `reembolsado` ya no se puede enviar.

**Reglas que conviene saber**

- El **reembolso es total**, no parcial. Si hace falta uno parcial, se hace desde el Dashboard de Stripe; el sitio no lo detecta (el webhook ignora los parciales a propósito).
- Si das clic dos veces en *Reembolsar*, o se cae la conexión justo ahí, **no se devuelve dos veces**: Stripe recibe siempre la misma clave de idempotencia (`reembolso-<id>`) y, si ya estaba reembolsado, el sitio lo reconoce y se sincroniza.
- Si alguien reembolsa el pedido **completo** desde el Dashboard de Stripe, el webhook (`charge.refunded`) también lo marca como `reembolsado` en el sitio.
- Los pedidos son **de toda Cruz Roja**: no se separan por delegación.
- Ver el detalle de un pedido (donde está el domicilio) **queda registrado** en la bitácora con el nombre de quien lo vio. Si por alguna falla no se puede registrar, el dato no se muestra.

**Cómo está protegido**

- La contraseña se guarda como hash bcrypt; no se puede leer ni recuperar.
- La sesión dura 8 horas, vive en una cookie firmada que el navegador no deja leer a ningún script (`HttpOnly`), solo se manda al propio sitio (`SameSite=Strict`) y en producción solo por HTTPS (`Secure`).
- A cada petición se vuelve a consultar la cuenta: si la persona se da de baja (`activo = 0`) o se bloquea, **pierde el acceso en el momento**, no hasta que venza su sesión.
- Con 5 contraseñas malas seguidas la cuenta se bloquea **15 minutos** (mientras tanto el sitio dice «Demasiados intentos fallidos. Espera unos minutos e intenta de nuevo.»). Además hay un tope de 10 intentos de inicio de sesión cada 15 minutos por dirección de internet. Ante un usuario o contraseña incorrectos, el mensaje es siempre el mismo («Usuario o contraseña incorrectos»), exista o no el usuario.
- Cualquier cambio exige que la petición venga del mismo sitio (protección contra páginas ajenas que intenten actuar en nombre de la persona).
- Los datos que escribe el cliente (nombre, dirección) se muestran siempre **como texto**, nunca como código de la página.
- Todo lo importante se anota en la bitácora, que no se puede borrar ni editar: `login_ok`, `login_fallido`, `ver_pedido`, `actualizar_envio`, `reembolsar_pedido` y `reembolso_confirmado_stripe`.

**Dar de baja a alguien:** `UPDATE personal SET activo = 0 WHERE usuario = 'ana.lopez';` en Workbench. Pierde acceso de inmediato. (No se borra la fila porque la bitácora la referencia.)

---

## 4. Cómo se prueba sin gastar nada

| Qué | Cómo | Qué comprueba |
|---|---|---|
| Servidor (pagos) | En `backend/`: `npm run probar:pagos` | 17 pruebas con un MySQL **local** y un Stripe falso: precio de la base, validaciones, pedido de otro dispositivo, firma del webhook, monto distinto, aviso repetido, falla de la base… |
| Servidor (administración) | En `backend/`: `npm run probar:admin` | 34 pruebas: inicio de sesión (también que una cuenta solo con matrícula no entre), bloqueo, baja inmediata, permisos por rol, filtros y búsqueda, envío (qué cambios se permiten y cuáles no), reembolsos (doble clic, ya reembolsado, falla de Stripe, pagos apagados) y el aviso `charge.refunded` |
| Todas juntas | `npm run probar:todo` | Las 51 (17 de pagos + 34 de administración) |
| App | En Xcode ⌘U | Datos de envío, totales, estados de la compra, qué pasa si Stripe cancela o falla, lectura de lo que manda el servidor |

Estas pruebas necesitan un MySQL en tu compu y `backend/.env.local` (copia `backend/.env.local.example`). Se niegan a correr contra Aiven porque crean y borran datos de prueba. Antes hay que haber corrido en ese MySQL local los scripts `01`, `02`, `08` y `09`.

> Las pruebas de administración dejan unas filas en `bitacora` y en `personal` (cuentas `prueba.*.pagos`). Es a propósito: la bitácora no se puede borrar. Por eso solo se corren en tu MySQL local, nunca en Aiven.

> Lo que **no** cubren: el cobro real contra Stripe (ni un reembolso real) y la hoja de pago. Eso se prueba a mano con los pasos 7 y 8 (casos CP-A01 a CP-A07 de abajo).

---

## 5. Casos de prueba nuevos (para tu Excel)

Cambian dos de los que ya tenías:

| Caso | Antes | Ahora |
|---|---|---|
| **CP-06** Botón Comprar | Abre el canal oficial en el navegador | Abre la hoja de compra dentro de la app. Ya no hay ningún botón que mande a otro sitio |
| **CP-08** Aviso de pagos | «…La app no procesa pagos.» | «Pagas con tarjeta dentro de la app y te lo enviamos a domicilio. El pago lo procesa Stripe: la app no guarda los datos de tu tarjeta.» |

Y estos son nuevos:

| ID | Caso | Cómo | Resultado esperado | Automatizado |
|---|---|---|---|---|
| CP-P01 | Compra exitosa | Comprar › datos válidos › tarjeta `4242…` | «¡Gracias por tu compra!» con folio; el pedido queda `pagado` | Parcial (servidor y lógica sí; la hoja de Stripe es manual) |
| CP-P02 | El precio lo decide el servidor | Mandar `POST /api/pedidos` con `precio_mxn: 1` | El pedido se cobra con el precio de la base | Sí (`probar:pagos`) |
| CP-P03 | Tarjeta rechazada | Tarjeta `4000 0000 0000 0002` | Stripe muestra el error en su hoja; el pedido **no** queda pagado | Manual |
| CP-P04 | Cerrar la hoja sin pagar | Tocar la X de la hoja de Stripe | Regresa al formulario, sin error; el pedido queda `cancelado` | Sí (⌘U) + manual |
| CP-P05 | Datos de envío incompletos | Dejar vacío el código postal | El botón Pagar está apagado y dice «Falta el código postal.» | Sí (⌘U) |
| CP-P06 | Total correcto | 2 piezas de $150 + envío $99 | Total `$399 MXN` | Sí (⌘U y `probar:pagos`) |
| CP-P07 | Pagos apagados | Vaciar `STRIPE_SECRET_KEY` y reiniciar | La hoja dice «La compra dentro de la app no está disponible por ahora» y ofrece **Reintentar** (no manda a otro sitio) | Sí (⌘U y `probar:pagos`) |
| CP-P08 | Aviso falso de pago | Mandar al webhook un evento sin firma válida | Responde 400 y el pedido no cambia | Sí (`probar:pagos`) |
| CP-P09 | Webhook que no llega | Cerrar `stripe listen` y pagar | «Estamos confirmando tu pago» con el folio; no deja pagar de nuevo | Sí (⌘U) + manual |
| CP-P10 | Un pedido es privado | Consultar un pedido con el id de otro dispositivo | 404 | Sí (`probar:pagos`) |
| CP-A01 | Entrar al sitio de administración | `/admin/` › usuario y contraseña correctos | Se ve la lista de pedidos y arriba el usuario y su rol | Sí (`probar:admin`) + manual |
| CP-A02 | Contraseña incorrecta | Escribir una contraseña mala | «Usuario o contraseña incorrectos» (igual si el usuario no existe); no entra | Sí (`probar:admin`) |
| CP-A03 | Bloqueo por intentos | 5 contraseñas malas seguidas, luego la buena | «Demasiados intentos fallidos…»; no entra durante 15 minutos | Sí (`probar:admin`) |
| CP-A04 | Baja inmediata | Con la sesión abierta, `UPDATE personal SET activo = 0 …` y tocar *Actualizar* | Vuelve al inicio de sesión («Tu sesión terminó») | Sí (`probar:admin`) |
| CP-A05 | Una compra aparece en el sitio | Comprar con `4242…` (paso 7) y abrir *Por enviar* | El pedido está con su folio, cliente y total; el detalle trae el domicilio | Manual |
| CP-A06 | Marcar el envío | Detalle › *Enviado* con guía `DHL 123-456` | Queda *Enviado* con la guía y el historial dice quién lo hizo; no se puede regresar a *Preparando* | Sí (`probar:admin`) + manual |
| CP-A07 | Reembolso | Con cuenta `administrativo`: detalle › *Reembolsar* › motivo › confirmar | El pedido pasa a *Reembolsado*; en el Dashboard de Stripe el pago aparece reembolsado | Lógica sí (`probar:admin`); el reembolso real es manual |
| CP-A08 | El operador no reembolsa | Entrar con cuenta `operador` | No hay botón *Reembolsar*; llamarlo a mano a la API da 403 | Sí (`probar:admin`) |
| CP-A09 | Doble clic en *Reembolsar* | Confirmar dos veces seguidas | Un solo reembolso en Stripe | Sí (`probar:admin`) |
| CP-A10 | Reembolso hecho en Stripe | Reembolsar el pago completo desde el Dashboard (con `stripe listen` abierto) | El pedido pasa a *Reembolsado* solo | Sí (`probar:admin`) + manual |
| CP-A11 | Datos con código | Comprar con el nombre `<b>hola</b>` | En el sitio se ve el texto tal cual, sin negritas ni nada ejecutado | Manual (al construirlo se comprobó en un navegador) |
| CP-A12 | Quién vio el domicilio | Abrir un detalle y revisar `SELECT b.accion, p.usuario, b.creada_en FROM bitacora b LEFT JOIN personal p ON p.id = b.personal_id ORDER BY b.id DESC LIMIT 5;` | Hay una fila `ver_pedido` con tu usuario | Sí (`probar:admin`) |

---

## 6. Si algo falla

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Al tocar Comprar dice «La compra dentro de la app no está disponible por ahora» | Falta el paquete de Stripe en Xcode (paso 6), o `STRIPE_SECRET_KEY` está vacía | Paso 6 / paso 3 y reiniciar `npm run dev`; luego **Reintentar** |
| «No hay conexión con el servidor» | El backend no está corriendo | `npm run dev` |
| Pagas y se queda en «Estamos confirmando tu pago» | El webhook no llega | ¿Sigue abierto `stripe listen`? ¿`STRIPE_WEBHOOK_SECRET` es el `whsec_` que imprimió? Reinicia el servidor después de cambiarlo |
| En la terminal de `stripe listen` los avisos salen con `[400]` | El `whsec_` del `.env` no coincide con el de `stripe listen` (el servidor responde «firma no válida») | Copia el `whsec_` que imprime `stripe listen` ahora, ponlo en el `.env` y reinicia `npm run dev` |
| «No pudimos iniciar el pago. Intenta de nuevo.» | La llave secreta es incorrecta, o Stripe no respondió | Mira la terminal del servidor (ahí está el detalle) y revisa `STRIPE_SECRET_KEY` |
| «El total es menor al mínimo que se puede cobrar ($10)» | Stripe no cobra menos de 10 pesos mexicanos | Es normal; con envío de $99 no debería pasar |
| El servidor no arranca y habla de `STRIPE_PUBLISHABLE_KEY` | Una llave es de prueba y la otra real, o falta | Las dos `_test_` |
| No aparece la tabla `pedido` / error de permisos | Falta el paso 2 | Corre `08`, `09` y luego `03` |
| `/admin/` dice «No encontrado» y la terminal dice *Sitio de administración APAGADO* | Falta `ADMIN_SESION_SECRETO` en el `.env` | Paso 8 y reiniciar `npm run dev` |
| El servidor no arranca y habla de `ADMIN_SESION_SECRETO` | Tiene menos de 32 caracteres | Genera uno con el comando del paso 8 |
| «Usuario o contraseña incorrectos» con la contraseña buena | No corriste el `INSERT` en la base de la que lee el servidor, o la cuenta está dada de baja (`activo = 0`) | `SELECT usuario, rol, activo FROM personal;` |
| Entras, pero la lista se queda vacía o marca error | Falta correr `09_pedidos_admin.sql`, o `cruzroja_app` no tiene permisos | Corre `09` y luego `03` otra vez |
| Al dar *Reembolsar* sale «Los pagos con Stripe no están activos en el servidor» | `STRIPE_SECRET_KEY` vacía | Paso 3 y reiniciar. (Los pedidos se pueden ver y enviar aunque Stripe esté apagado; solo el reembolso lo necesita) |
| Al dar *Reembolsar* sale «Stripe no pudo hacer el reembolso…» | Llave incorrecta, Stripe sin respuesta o el pago no se puede devolver | Mira la terminal del servidor y el pago en el Dashboard de Stripe antes de reintentar. Si ya estaba reembolsado allá, vuelve a intentar: el sitio lo reconoce y se pone al día |
| Sale «El reembolso se hizo en Stripe, pero no se pudo anotar aquí» | Se devolvió el dinero pero falló la base justo después | No repitas nada: cuando Stripe mande `charge.refunded` el pedido se pone al día solo. Avisa al equipo técnico |
| Reembolsas en el Dashboard de Stripe y el sitio sigue en *Pagado* | Los reembolsos **parciales** no se reflejan; o `stripe listen` está cerrado / el endpoint del webhook no tiene el evento `charge.refunded` | Reembolso total + `stripe listen` abierto; en producción, agrega el evento (sección 8) |
| Entras desde el celular por la IP y se cierra la sesión sola | El navegador no guarda la cookie si `NODE_ENV=production` y no hay HTTPS | En desarrollo no uses `NODE_ENV=production`; en producción usa HTTPS |

---

## 7. Qué decidir con Cruz Roja

- **Costo de envío.** `ENVIO_MXN=99` es un número de ejemplo. Cruz Roja define si es fijo, por zona, o gratis arriba de cierto monto (eso último habría que programarlo).
- **Quién surte los pedidos.** Los pedidos pagados aparecen en el sitio de administración (sección 3) con el domicilio. Hay que acordar **quién** del personal entra, con qué rol (`operador` o `administrativo`) y cada cuánto revisa *Por enviar*. Hoy los pedidos son de toda Cruz Roja, no por delegación: si cada delegación debe ver solo los suyos, hay que programarlo.
- **Quién reembolsa.** Solo el rol `administrativo`. Hay que acordar quién es y en qué casos se devuelve (producto dañado, no llegó, etc.). Solo hay reembolso **total**; uno parcial se hace desde el Dashboard de Stripe.
- **Cuentas del personal.** Hoy se crean con `npm run crear:personal` y un `INSERT` en Workbench; no hay pantalla para crearlas ni para cambiar contraseñas. Alguien con acceso a la base tiene que hacerlo.
- **Aviso de privacidad.** Ahora la app guarda nombre, teléfono y **domicilio**. Hay que actualizar el aviso de privacidad (y su versión en `consentimiento`) para decir qué datos son y para qué se usan (entregar el pedido). El domicilio solo lo ve el personal autorizado: la API nunca lo devuelve a la app.
- **Pedidos que quedan «pendientes».** Si alguien cierra la app justo en la hoja de pago, el pedido queda `pendiente`. No molesta, pero conviene una limpieza periódica (por ejemplo, pasar a `cancelado` los pendientes de más de 24 horas).

---

## 8. Para cobrar dinero de verdad

1. Cruz Roja Mexicana abre y **verifica** su cuenta de Stripe (datos del negocio y cuenta bancaria). No se puede con una cuenta personal de estudiante.
2. Se usan las llaves `pk_live_...` / `sk_live_...` (en el servidor de producción, **no** en el repo).
3. En el Dashboard › *Webhooks* se registra el endpoint público `https://<dominio-del-backend>/stripe/webhook` con **tres** eventos: `payment_intent.succeeded`, `payment_intent.canceled` y `charge.refunded` (este último es el que avisa de un reembolso; sin él, los reembolsos hechos desde el Dashboard de Stripe no se reflejan en el sitio). Su `whsec_` va en el `.env` de producción. (`stripe listen`, en tu Mac, reenvía todos los eventos; por eso allá no hay que elegirlos.)
4. El backend debe estar en `https` (en `Configuracion.swift` ya está marcado dónde va el dominio). **El sitio de administración lo exige**: con `NODE_ENV=production` la cookie de sesión es `Secure` y el navegador no la guarda en `http`, así que nadie podría entrar. Hay que poner `NODE_ENV=production` y `ADMIN_SESION_SECRETO` (uno **nuevo**, distinto al de desarrollo) en el servidor.
5. Antes de publicar, repasar la lista de Stripe para salir a producción: <https://docs.stripe.com/get-started/checklist/go-live>.
6. Apple: como son **productos físicos**, se puede cobrar con Stripe. Si algún día se vendiera algo digital, habría que usar las compras dentro de la app de Apple.
7. Corre `db/09_pedidos_admin.sql` en la base de producción **antes** de publicar la nueva versión del servidor (la lista de pedidos lee las columnas nuevas).
8. Crea las cuentas reales del personal con `npm run crear:personal` y quita o da de baja las cuentas de prueba.

**Todavía no incluido** (se puede agregar después): Apple Pay (necesita un *Merchant ID* de Apple), pago en OXXO o transferencia SPEI, pantalla «Mis pedidos» (que la persona vea en la app si su pedido ya salió), correo de confirmación o de envío al cliente, reembolsos parciales, exportar pedidos a Excel/CSV, cuentas por delegación y una pantalla para crear cuentas o cambiar contraseñas del personal.

---

## 9. Seguridad, en una lista

- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` y `ADMIN_SESION_SECRETO` viven solo en `backend/.env` (ya ignorado por Git). Si alguna de Stripe se filtra: *Dashboard › API keys › Rotate key*. Si se filtra `ADMIN_SESION_SECRETO`, cámbiala por otra: se cierran todas las sesiones.
- El sitio de administración solo funciona con cuenta de persona (nada de usuario compartido), con contraseña en hash bcrypt, y cada consulta de domicilio y cada cambio queda en la bitácora con el nombre de quien lo hizo (sección 3).
- Un pedido tiene **domicilio y teléfono de una persona**: solo lo ve el personal con sesión. La API pública de la app (`/api/pedidos`) nunca los devuelve.
- La llave publicable sí viaja a la app, pero la manda el servidor con cada pedido (no está escrita en el código de Swift).
- El webhook comprueba la **firma** de Stripe, y además que **el monto y la moneda** coincidan con el pedido; un aviso repetido se ignora.
- La respuesta de `GET /api/pedidos/:id` no incluye nombre, teléfono ni dirección, y solo la ve el dispositivo que hizo el pedido.
- Los errores de Stripe no se muestran tal cual a la persona; el detalle queda en la terminal del servidor.
- `cruzroja_app` puede crear y actualizar pedidos, pero **no borrarlos**.

---

## 10. Subirlo al repo del equipo

Esta carpeta es una copia del repo del equipo (partió de `main`, commit `9454ca4`, y trae su historial de Git). Los archivos `backend/.env`, `backend/ca.pem` y `node_modules` **no vienen** a propósito: copia tu `.env` y tu `ca.pem` de tu carpeta `backend` de siempre y corre `npm install` dentro de `backend`.

Cuando ya probaste (⌘U en Xcode, `npm run probar:pagos` y una compra de prueba), en la terminal de VS Code, dentro de esta carpeta:

```bash
git status                 # deben salir los archivos de pagos; NO .env, .pem ni node_modules
git checkout -b pagos-stripe
git add .
git commit -m "Pago con Stripe y envío a domicilio en Productos con causa"
git push -u origin pagos-stripe
```

Después abre el *pull request* en GitHub para que el equipo lo revise antes de unirlo a `main`. Si alguien subió cambios mientras tanto, GitHub te avisa y se resuelve ahí.
