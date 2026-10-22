// Si tu función necesita algo compartido (p. ej. la sesión del usuario),
// créalo aquí con @State y agrégalo con otro .environment(...).

import SwiftUI

@main
struct CruzRojaApp: App {
    @State private var ubicacion = Ubicacion()
    @State private var capacitacion = CapacitacionModelo()
    @State private var internet = Internet()

    var body: some Scene {
        WindowGroup {
            PantallaPrincipal()
                .environment(ubicacion)
                .environment(capacitacion)
                .environment(internet)
        }
    }
}
