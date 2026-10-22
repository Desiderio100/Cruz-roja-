// Ponlo en cualquier pantalla que necesite la ubicación:
//
//     AvisoPermisoUbicacion(motivo: "para mostrarte el centro más cercano")

import SwiftUI

struct AvisoPermisoUbicacion: View {
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(\.openURL) private var abrirURL
    let motivo: String

    var body: some View {
        if !ubicacion.tienePermiso {
            VStack(alignment: .leading, spacing: 10) {
                Label("Activa tu ubicación", systemImage: "location.fill")
                    .font(.headline)
                Text("La necesitamos \(motivo).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if ubicacion.permisoNegado {
                    Button("Abrir Ajustes") {
                        abrirURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    .buttonStyle(BotonRojo())
                } else {
                    Button("Permitir ubicación") { ubicacion.pedirPermiso() }
                        .buttonStyle(BotonRojo())
                }
            }
            .tarjeta()
        }
    }
}
