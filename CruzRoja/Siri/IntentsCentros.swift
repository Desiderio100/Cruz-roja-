import AppIntents
import Foundation

struct CentrosCercanosIntent: AppIntent {
    static var title: LocalizedStringResource { "Centros cercanos" }
    static var description = IntentDescription("Te dice cuáles son los centros de Cruz Roja más cercanos a ti.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let punto = DatosSiri.ubicacionActual() else {
            let nombres = Centro.todos.prefix(3).map { $0.nombre }.joined(separator: ", ")
            if nombres.isEmpty { return .result(dialog: "No hay centros registrados.") }
            return .result(dialog: "No sé dónde estás, así que no puedo decirte cuál es el más cercano. Abre la app de Cruz Roja una vez y permite la ubicación. Algunos centros son: \(nombres).")
        }

        let cercanos = Array(Centro.ordenados(desde: punto).prefix(3))
        guard let primero = cercanos.first else {
            return .result(dialog: "No hay centros registrados.")
        }

        var texto = "El centro más cercano es \(primero.centro.nombre), a \(DatosSiri.distanciaHablada(primero.metros)), en \(primero.centro.direccion). Su teléfono es \(primero.centro.telefonoParaMostrar)."
        let otros = cercanos.dropFirst().map { "\($0.centro.nombre), a \(DatosSiri.distanciaHablada($0.metros))" }
        if !otros.isEmpty {
            texto += " Después están \(otros.joined(separator: ", y "))."
        }
        texto += " Calculé la distancia desde tu última ubicación conocida."
        return .result(dialog: "\(texto)")
    }
}

struct RutaCentroIntent: AppIntent {
    static var title: LocalizedStringResource { "Ruta al centro más cercano" }
    static var description = IntentDescription("Abre la ruta al centro de Cruz Roja más cercano en la aplicación de mapas que elijas.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Aplicación de mapas", requestValueDialog: IntentDialog("¿Con qué aplicación quieres ir? Apple Maps, Google Maps o Waze."))
    var aplicacion: AppMapaSiri

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let punto = DatosSiri.ubicacionActual(), let centro = Centro.masCercano(a: punto) else {
            return .result(dialog: "No sé dónde estás, así que no puedo buscar la ruta. Permite la ubicación en la app de Cruz Roja y vuelve a intentarlo.")
        }
        let destino = aplicacion.aplicacion
        await DatosSiri.esperarAppActiva()
        await DatosSiri.abrirRuta(a: centro, con: destino)
        return .result(dialog: "Abrí la ruta a \(centro.nombre) en \(destino.nombre).")
    }
}
