// Arranque de la app: crea lo compartido (una sola vez) y decide qué pantalla mostrar.
// Si tu función necesita algo compartido, créalo aquí con @State y agrégalo con otro .environment(...).

import SwiftUI

@main
struct CruzRojaApp: App {
    @State private var sesion = SesionUsuario()
    @State private var permisos = GestorPermisos()
    @State private var ubicacion = Ubicacion()
    @State private var capacitacion = CapacitacionModelo()
    @State private var internet = Internet()

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(sesion)
                .environment(permisos)
                .environment(ubicacion)
                .environment(capacitacion)
                .environment(internet)
                .tint(Color.rojoCruzRoja)
        }
    }
}

/// Primera vez: Crea tu cuenta → Permisos → app. Después, directo a la pantalla principal.
struct RaizView: View {
    @Environment(SesionUsuario.self) private var sesion

    var body: some View {
        Group {
            if !sesion.registroListo {
                RegistroView()
            } else if !sesion.permisosListos {
                PermisosView()
            } else {
                PantallaPrincipal()
            }
        }
        .animation(.default, value: sesion.registroListo)
        .animation(.default, value: sesion.permisosListos)
    }
}
