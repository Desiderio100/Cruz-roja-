# App Cruz Roja · Equipo El Rebaño

App para iPhone (SwiftUI, iOS 17+) para Cruz Roja Mexicana · Monterrey.

## Abrir y correr

1. Doble clic en **`CruzRoja.xcodeproj`**.
2. Arriba elige un iPhone del simulador.
3. **⌘R**.

Eso es todo: no hay paquetes ni módulos. Todo el código está en `CruzRoja/`.

## Cómo está organizado

```
CruzRoja/
├── App/
│   ├── CruzRojaApp.swift      ← arranque; crea lo compartido (ubicación, cursos)
│   ├── PantallaPrincipal.swift← no hace falta tocarlo
│   ├── Maqueta.swift          ← Emergencia y Donar: SOLO diseño, sin función (se quita después)
│   └── Secciones.swift        ← ⭐ AQUÍ agregas tu pantalla (una entrada)
├── Comun/                     ← lo que puede usar cualquiera
│   ├── Ubicacion.swift        ← GPS y permiso de ubicación (uno para toda la app)
│   ├── Permisos.swift         ← aviso listo para pedir permiso de ubicación
│   ├── AvisoSinInternet.swift ← franja "Sin internet · …" para cualquier pantalla
│   ├── Internet.swift         ← ¿hay conexión? (uno para toda la app)
│   ├── Telefono.swift         ← para hacer llamadas
│   └── Estilo.swift           ← rojo Cruz Roja, BotonRojo, .tarjeta()
├── CentroCercano/             ← Centro más cercano (Desiderio)
└── Capacitacion/              ← Capacitación: cursos + "Aprende" (Desiderio)
                               (el logo va en Assets.xcassets › LogoCruzRoja)
```

## Agregar tu función (3 pasos)

1. Crea tu carpeta: `CruzRoja/MiFuncion/` y adentro tu vista, p. ej. `MiFuncionView.swift`.
   Xcode la agrega sola (la carpeta está sincronizada), no hay que tocar el proyecto.
2. Abre `App/Secciones.swift` y copia el bloque comentado:
   ```swift
   Seccion("Mi función",
           detalle: "Qué hace, en una línea",
           icono: "star.fill",
           responsable: "Tu nombre") {
       MiFuncionView()
   },
   ```
3. ⌘R. Tu tarjeta ya aparece en la pantalla principal.

Cada quien edita **solo su carpeta y su entrada en `Secciones.swift`**, así casi no
hay conflictos en Git.

## Usar lo compartido

**Ubicación** (no crees tu propio `CLLocationManager`):
```swift
@Environment(Ubicacion.self) private var ubicacion

ubicacion.coordenada     // CLLocationCoordinate2D? — dónde está el usuario
ubicacion.tienePermiso   // Bool
ubicacion.pedirPermiso() // muestra la alerta de iOS
```

**Pedir permiso con un aviso ya hecho** (botón "Permitir" o "Abrir Ajustes"):
```swift
AvisoPermisoUbicacion(motivo: "para enviar tu ubicación al operador")
```

**Centro más cercano y su número** (p. ej. para el botón de emergencia):
```swift
if let punto = ubicacion.coordenada, let centro = Centro.masCercano(a: punto) {
    centro.telefono
}
```

**Llamar:**
```swift
Link("Llamar", destination: Telefono.url(numero))
```

**Estilo:** `.buttonStyle(BotonRojo())` (principal), `.buttonStyle(BotonBorde())` (secundario), `.tarjeta()`, `Color.rojoCruzRoja`.

**Otro permiso** (cámara, notificaciones…): agrega el texto en el target `CruzRoja` ›
Info y, si varios lo van a usar, ponlo en `Comun/` igual que `Ubicacion.swift`.

## Qué hace cada función

**Centro más cercano** — mapa satelital con todos los centros (el más cercano en
rojo); tu centro más cercano con dirección, referencia ("Sobre Av. …"), una
**flecha con km y sentido** ("a 2.3 km · adelante a la derecha") y si **te estás
acercando o alejando**; *Cómo llegar* (Apple Maps, Google Maps o Waze); y la lista
de todos los centros del más cercano al más lejano.

Sin internet: la lista, los km, la flecha y la referencia siguen funcionando (solo
GPS y brújula). El mapa se ve gris pero con pines. Para rutas por calles sin
internet, la app explica cómo descargar el mapa de Monterrey en Apple/Google Maps
(*¿Rutas sin internet?*). En carro la flecha usa la dirección del GPS, no la brújula.

Para presentar: el interruptor **Simular recorrido por Monterrey** mueve tu
ubicación poco a poco, como en carro. Para probar sin internet en el simulador,
apaga el Wi-Fi de la Mac. El botón de llamar irá en la página principal
(`Telefono.url(centro.telefono)`).

**Capacitación** — dos pestañas:
- *Cursos*: **Mis inscripciones** (con folio) arriba y los próximos cursos con fecha y
  lugares. Inscripción con folio de confirmación; si está lleno no deja inscribirse.
  Cursos de ejemplo por ahora (`Curso.ejemplos`); el lugar para conectar el backend
  está marcado en `CapacitacionModelo.swift`.
- *Aprende*: lo básico que todos deberíamos saber (pedir ayuda, RCP, atragantamiento,
  hemorragias, posición lateral, quemaduras) con los pasos siempre abiertos y un
  video de YouTube por tema. Para cambiar un video, edita `videoID` en `Tema.swift`.

| Capacitación | Con internet | Sin internet |
|---|---|---|
| Ver cursos | ✅ | ✅ con aviso "los lugares pueden haber cambiado" |
| Inscribirse | ✅ | ❌ botón apagado (el cupo vive en el servidor) |
| Mis inscripciones | ✅ | ✅ guardadas en el teléfono |
| Pasos de Aprende | ✅ | ✅ texto dentro de la app |
| Videos | ✅ | ❌ aviso "Necesitas internet" |

## ⚠️ Datos de prueba

`centros.json` trae **nombres, coordenadas y teléfonos inventados**. Cambiarlos por
el directorio oficial de Cruz Roja antes de probar con usuarios. No marquen esos
números desde un iPhone real.
