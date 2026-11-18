import SwiftUI

struct BotonChat: View {
    @Environment(\.scenePhase) private var fase
    @State private var disponible = DisponibilidadChat.estaDisponible
    @State private var abierto = false

    var body: some View {
        Group {
            if disponible {
                Button("Asistente", systemImage: "message") { abierto = true }
                    .labelStyle(.iconOnly)
            }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { disponible = DisponibilidadChat.estaDisponible }
        }
        #if canImport(FoundationModels)
        .sheet(isPresented: $abierto) {
            if #available(iOS 26.0, *) {
                ChatView()
            }
        }
        #endif
    }
}
