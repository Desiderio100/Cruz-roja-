# Llamada en vivo: audio, cámara bajo petición y ficha con IA

## Qué hace

- La persona y el operador se hablan de verdad (audio en las dos direcciones) desde el botón de Emergencia.
- El operador no muestra su cámara. Solo puede pedir la de la persona. La persona ve una alerta y decide si acepta. El operador puede detenerla cuando quiera, y la persona también.
- El teléfono transcribe lo que dice la persona con la IA de Apple (en el propio teléfono) y las frases aparecen en la pantalla del operador.
- Con el modelo de Apple, el teléfono también llena motivo, lesionados, lesión principal, lugar y comentarios de la ficha. Esos campos salen con la etiqueta "IA". Si el operador guarda la ficha, la IA deja de escribir para no pisar su trabajo.
- Si el teléfono no tiene iOS 26, Apple Intelligence o español disponible, la llamada funciona igual (audio y cámara) y el operador llena la ficha a mano.

## Cómo viaja todo

```
iPhone  <-- audio y video -->  LiveKit Cloud  <-- audio -->  Navegador del operador
   |                                                              |
   | frases y campos (API)                                        | pide o detiene cámara (mensaje)
   v                                                              v
 backend/ -> MySQL (transcripcion, ficha)  <-- cada 2 s --  personal/ (sitio del operador)
```

- La sala se llama igual que el id de la llamada.
- El token del teléfono permite micrófono y cámara. El token del operador solo permite micrófono: aunque alguien lo intente, el operador no puede publicar video.
- Mensajes de control (tema `llamada`): del operador `pedir_camara`, `detener_camara`, `fin`; del teléfono `camara` con estado `aceptada`, `rechazada`, `sin_permiso` o `apagada`.
- Nada se graba. LiveKit solo transporta el audio y el video en vivo.

## Para ponerlo a funcionar

Ya viene integrado en este proyecto: el paquete LiveKit ya está enlazado en `CruzRoja.xcodeproj`, la dependencia nueva ya está en `backend/package.json` y `personal/package.json`, y `CamaraLlamada.swift` se eliminó.

1. Las claves de LiveKit están en `backend/livekit.env` y `personal/livekit.env`. Esos archivos no se suben a GitHub (el `.gitignore` ignora `*.env`). Copia sus tres líneas al final del `.env` de cada carpeta. Si no tienes `.env` todavía, copia `.env.example` a `.env` y pega las líneas ahí.
2. En `backend/` y en `personal/`: `npm install`.
3. En Aiven, como administrador, correr `db/11_llamada_en_vivo.sql` (devuelve a `cruzroja_app` el permiso de escribir transcripción; hay que correrlo otra vez si alguien vuelve a correr el 03).
4. Abrir `CruzRoja.xcodeproj` en Xcode 16.3 o más nuevo. La primera vez descarga el paquete LiveKit (File > Packages > Resolve Package Versions si no arranca solo).
5. El sitio del operador debe abrirse con HTTPS en producción (el navegador solo da micrófono en HTTPS o en localhost).
6. Cambiar el secret de LiveKit en LiveKit Cloud antes de producción, porque se compartió por chat.

## Qué cambió en la app

- `EmergenciaInicio.swift`: el botón ya no abre la llamada de muestra. Ahora llama a `iniciarLlamada()`, que crea la llamada real en el servidor (si falla, usa el respaldo telefónico como estaba pensado). También descarga el modelo de voz de Apple en segundo plano cuando hay internet, para no hacerlo en plena emergencia.
- `EmergencyCallView.swift`: se quitó la alerta de cámara a los 3 segundos. Ahora la alerta sale cuando el operador la pide. Muestra "Conectando la llamada", "Esperando al operador" u "Operador en la llamada". Si el operador finaliza, la pantalla se cierra.
- `EmergencyAPI.swift`: tres llamadas nuevas (sala, transcripción, ficha).
- Archivos nuevos: `LlamadaEnVivo.swift` (audio, cámara, mensajes), `TranscripcionLlamada.swift` (SpeechAnalyzer), `AsistenteLlamada.swift` (modelo de Apple que llena la ficha).
- `CamaraLlamada.swift` se eliminó (LiveKit maneja la cámara).

## Qué se probó y qué no

Probado (antes de integrarlo a este proyecto) con un servidor LiveKit local, MySQL local y navegadores automatizados (uno como operador y otro como teléfono):
- El teléfono solo obtiene token de su propia llamada. Otro dispositivo recibe error.
- Audio en las dos direcciones. El operador solo publica audio.
- "Pedir cámara": el operador ve el video solo después de que el teléfono acepta; "Detener cámara" lo apaga; si la persona rechaza, el operador lo ve.
- Transcripción y campos de IA llegan a la pantalla, con etiqueta "IA". Después de guardar el operador, la IA ya no cambia los campos.
- "Finalizar llamada" avisa al teléfono y deja la llamada en `finalizada`.
- Sin errores en la consola del navegador.

No probado (no hay Xcode ni iPhone en este entorno):
- La app de iPhone nunca se compiló. Puede haber errores de compilación pequeños al integrarla.
- La transcripción con SpeechAnalyzer y la extracción con el modelo de Apple en español, en un iPhone real. Hay que revisar la calidad de lo que escribe en la ficha.
- LiveKit Cloud real y datos móviles (el servidor de pruebas fue local).
- Eco con la bocina del iPhone encendida.
- El botón "Activar sonido" del operador en Safari (se muestra solo si el navegador bloquea el audio automático).

## Pendientes de documentación

- Aviso de privacidad y requisitos: ahora se guarda la transcripción de lo que dice la persona y se usa un servicio externo (LiveKit) para transportar audio y video en vivo.
- Enlace del paquete LiveKit en `project.pbxproj`: se editó a mano copiando el formato del paquete de Stripe; si Xcode se queja al abrir, agregar el paquete desde File > Add Package Dependencies (`https://github.com/livekit/client-sdk-swift`, desde 2.19.0, producto `LiveKit`).
