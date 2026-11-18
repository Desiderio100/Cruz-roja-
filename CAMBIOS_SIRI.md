# Siri: centros y citas sin abrir la app

La persona le habla a Siri y Siri hace lo mismo que Bot-iquin en Centros y Citas. Funciona con App Intents, que existen desde iOS 16. No necesita Apple Intelligence ni iOS 26.

## Qué se puede decir

| Frase (siempre lleva el nombre de la app) | Qué hace |
|---|---|
| "Centro más cercano de Cruz Roja" | Dice los 3 centros más cercanos, con distancia, dirección y teléfono del primero |
| "Llévame al centro más cercano de Cruz Roja" | Siri pregunta por voz "¿Con qué aplicación quieres ir? Apple Maps, Google Maps o Waze" y abre la ruta |
| "Mis citas en Cruz Roja" | Dice las citas y avisa cuáles están pospuestas |
| "Agendar una cita en Cruz Roja" | Pregunta servicio, día y hora, pide confirmación y agenda |
| "Cancelar mi cita en Cruz Roja" | Pregunta cuál cita, pide confirmación y cancela |
| "Reprogramar mi cita en Cruz Roja" | Solo citas pospuestas: pregunta cuál, día y hora, confirma y reprograma |

Siri exige el nombre de la app en cada frase. Es una regla de Apple, no se puede quitar.

## Cómo funciona cada pregunta

- La app de mapas se pide como opción del intent. Siri la pregunta por voz y no hay botones.
- El día se dice con palabras: hoy, mañana, un día de la semana o una fecha. Solo se agenda de lunes a viernes dentro de los próximos 5 días hábiles, igual que el chat.
- Los horarios libres los lee Siri en voz alta y la persona responde con la hora ("diez", "las 10", "3 de la tarde"). Si no se entiende, vuelve a preguntar dos veces.
- Agendar, cancelar y reprogramar siempre piden confirmación por voz. Nada cambia sin un "sí".
- Para agendar hace falta nombre y celular en Mi perfil, como en el chat.

## Decisiones que conviene revisar

- Citas pide desbloquear el teléfono antes de correr (contienen datos personales). Centros funciona con el teléfono bloqueado.
- Ruta al centro abre la app de Cruz Roja un instante antes de saltar al mapa. Es la forma más directa que encontré para que funcione también en iOS 17. Apple tiene una acción para abrir enlaces desde Siri sin mostrar la app, pero es de iOS 18 en adelante y mezclarla con iOS 17 en los atajos tiene un error documentado en los foros de Apple. Si el proyecto sube su versión mínima a iOS 18, se cambia por esa acción.
- La distancia se calcula desde la última ubicación conocida. Pedir ubicación nueva desde una acción de Siri que corre en segundo plano no es confiable (los foros de Apple lo reportan, sobre todo con el permiso "al usar la app"). Por eso `Comun/Ubicacion.swift` ahora guarda la última ubicación (una línea). Si la persona nunca ha abierto la app con ubicación, Siri se lo dice.
- Emergencia no está en Siri a propósito: un malentendido no debe iniciar una llamada de emergencia.
- El chat de Bot-iquin sigue igual, con sus tres botones para elegir app de mapas. La pregunta por voz es solo de Siri.

## Cómo probar

1. Correr la app una vez en el iPhone, permitir la ubicación y completar Mi perfil.
2. En Ajustes > Siri, el idioma de Siri debe ser español. Las frases están escritas en español.
3. Los atajos aparecen en la app Atajos, en la sección de Cruz Roja. Si no salen de inmediato, esperar unos minutos o reinstalar la app.
4. Probar con "Oye Siri" y cada frase de la tabla.

## Archivos

Carpeta nueva `CruzRoja/Siri/`: `AtajosCruzRoja.swift` (las frases), `IntentsCentros.swift`, `IntentsCitas.swift`, `OpcionesSiri.swift` (servicio, app de mapas y citas como opciones de Siri), `DatosSiri.swift` (lógica compartida, día y hora). Un cambio en `Comun/Ubicacion.swift`. El proyecto usa carpetas sincronizadas, así que Xcode los toma solo.

## Sin probar

No hay Xcode ni iPhone en el entorno de trabajo, así que nada se compiló. Las firmas se verificaron en la documentación de Apple. Falta confirmar en un iPhone:

1. Que compile. Un error de firma sería pequeño y local.
2. Que Siri entienda las frases en español y la respuesta de la app de mapas.
3. Que Siri entienda la hora dicha en voz ("diez", "tres de la tarde") y que al elegir cita por voz coincida con su descripción.
4. Que la ruta salte a Apple Maps, Google Maps y Waze después de abrir la app.
5. Que el desbloqueo de las acciones de citas se comporte bien con el teléfono bloqueado.
