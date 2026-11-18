# Chat con Bot-iquin

Asistente en lenguaje natural con Foundation Models de Apple. Todo lo que ve la persona sale en español.

## Qué se agrega

Carpeta nueva `CruzRoja/Chat/`:

| Archivo | Qué hace |
|---|---|
| `BotonChat.swift` | Botón de la barra superior. Solo aparece si el dispositivo puede usar el chat. |
| `DisponibilidadChat.swift` | Revisa disponibilidad del modelo y soporte de español. Detector de idioma y textos fijos. |
| `ChatView.swift` | Pantalla del chat, burbujas, tarjeta de confirmación y barra para escribir. |
| `ChatModelo.swift` | Sesión del modelo, instrucciones en español, reintento si responde en otro idioma. |
| `HerramientasChat.swift` | Las 10 herramientas que el modelo puede usar. |
| `AccionesChat.swift` | Lo que hacen las herramientas: leen y llaman a `ClienteAPI`, `CapacitacionModelo` y `Centro`. |
| `BotIquinView.swift` | Mascota en sus dos estados. |

Además: dos imágenes en `Assets.xcassets` (`BotIquinReposo`, `BotIquinCargando`) y un cambio de 2 líneas en `App/PantallaPrincipal.swift` (el botón junto a Mi perfil).

## Cómo instalarlo

1. Copiar `CruzRoja/Chat/` y las dos carpetas `.imageset` dentro de `CruzRoja/`.
2. Reemplazar `CruzRoja/App/PantallaPrincipal.swift` (solo cambia el bloque del toolbar).
3. El proyecto usa carpetas sincronizadas, así que los archivos nuevos entran solos al target. Si Xcode no los muestra, agregarlos a mano.

Se necesita Xcode con el SDK de iOS 26 o más nuevo. Con un SDK anterior el proyecto compila sin el chat. El destino de despliegue sigue en iOS 17.

## Qué puede hacer el chat

- Centros: buscar los más cercanos y abrir la ruta en Apple Maps, Google Maps o Waze.
- Capacitación: listar cursos, dar detalle e inscribir.
- Citas: ver horarios, ver mis citas, agendar, cancelar y reprogramar.

Fuera del chat: Emergencia, Productos con causa, Registro y Mi perfil.

## Cómo se garantiza el español

- Instrucciones y descripciones de herramientas escritas en español.
- Todo texto de la interfaz sale de la app: confirmaciones, botones, errores y avisos.
- Si el modelo responde en otro idioma, se reintenta una vez con la instrucción reforzada. Si falla, se muestra un mensaje fijo.
- Los mensajes de error del servidor pasan por el detector de idioma. Si no están en español, se reemplazan por uno genérico.
- Ningún error del sistema se muestra tal cual.

## Reglas de seguridad

- Las herramientas que cambian algo (inscribir, abrir ruta, agendar, cancelar, reprogramar) no lo ejecutan: preparan la acción y la app muestra una tarjeta con Confirmar y Cancelar. Solo el botón ejecuta.
- Si el mensaje parece una emergencia (palabras como emergencia, ambulancia, infarto, no respira), el chat no usa el modelo y responde con un texto fijo que manda al botón de Emergencia y al 911.
- Para agendar o inscribir se necesitan nombre y celular en Mi perfil. Si faltan, el chat lo indica.

## Decisiones que conviene revisar

- Reprogramar solo aplica a citas pospuestas, igual que la pantalla de Mis citas. Una cita normal se cancela y se agenda otra.
- La inscripción a cursos sigue siendo local, con folio aleatorio, igual que hoy. Cuando exista el endpoint solo cambia `CapacitacionModelo.inscribir`.
- Si el teléfono del perfil trae más de 10 dígitos (por ejemplo +52), para inscribir se usan los últimos 10.
- Los horarios se piden por día (hoy, mañana, día de la semana o fecha) dentro de los 5 días hábiles que ya maneja la app.

## Sin probar

Este código se escribió sin poder compilarlo ni correrlo (no hay Xcode ni iPhone en el entorno de trabajo). Las firmas de Foundation Models se verificaron en la documentación de Apple. Falta probar en un iPhone real con Apple Intelligence activado:

1. Que compile sin errores. Cualquier error de firma será local y pequeño.
2. Calidad del español en las respuestas, con y sin las herramientas.
3. Que el modelo use el número correcto de la lista al agendar, cancelar o reprogramar.
4. Que el botón no aparezca en un dispositivo sin Apple Intelligence o con iOS menor a 26.
5. Conversaciones largas: el contexto es de unos 4,000 tokens y la sesión se reinicia sola si falla.
6. Los dos estados de Bot-iquin en la pantalla principal y en el chat.
