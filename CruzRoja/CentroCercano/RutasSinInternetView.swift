// Nosotros no podemos calcular rutas por calles sin internet; Apple Maps y
// Google Maps sí, si antes descargaste el mapa de Monterrey (una sola vez).

import SwiftUI

struct RutasSinInternetView: View {
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Descarga una vez el mapa de Monterrey, con internet. Después, el botón Cómo llegar te dará la ruta en carro aunque no tengas señal.")
                }
                Section("Apple Maps") {
                    Paso(1, "Abre Mapas y toca tu foto o tus iniciales.")
                    Paso(2, "Toca Mapas sin conexión › Descargar nuevo mapa.")
                    Paso(3, "Busca Monterrey, ajusta el área y toca Descargar.")
                }
                Section("Google Maps") {
                    Paso(1, "Abre Google Maps y toca tu foto.")
                    Paso(2, "Toca Mapas sin conexión › Selecciona tu propio mapa.")
                    Paso(3, "Ajusta el área de Monterrey y toca Descargar.")
                }
                Section {
                    Label("Aunque no descargues nada, la flecha y los km de esta app siempre funcionan sin internet.", systemImage: "location.north.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rutas sin internet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Listo") { cerrar() } }
        }
        .tint(Color.rojoCruzRoja)
    }
}

private struct Paso: View {
    let numero: Int
    let texto: String
    init(_ numero: Int, _ texto: String) { self.numero = numero; self.texto = texto }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(numero)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.rojoCruzRoja, in: Circle())
            Text(texto)
        }
    }
}

#Preview { RutasSinInternetView() }
