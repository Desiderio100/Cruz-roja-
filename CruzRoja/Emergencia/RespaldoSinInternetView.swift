//
//  RespaldoSinInternetView.swift
//  Respaldo de EMERGENCIA cuando no hay internet o el servidor no responde (maqueta
//  "Respaldo sin internet"): el centro más cercano sale de centros.json, que va dentro de
//  la app, y las coordenadas del GPS, que funciona sin internet. La persona llama por
//  línea telefónica y le dicta sus coordenadas al operador.
//
//  ⚠️ Mientras Configuracion.directorioDePrueba sea true, el botón NO marca: los
//  teléfonos de centros.json son inventados.
//

import CoreLocation
import SwiftUI

struct RespaldoSinInternetView: View {
    let centro: Centro?
    let punto: CLLocationCoordinate2D?
    let cerrar: () -> Void

    @Environment(Internet.self) private var internet
    @Environment(\.openURL) private var abrirURL
    @State private var avisoPrueba = false

    private var numero: String { centro?.telefono ?? Telefono.emergencias }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aviso

                    VStack(alignment: .leading, spacing: 6) {
                        Text(centro == nil ? "Número de emergencias" : "Delegación más cercana")
                            .font(.caption.bold())
                            .foregroundStyle(Color.rojoCruzRoja)
                        Text(centro?.nombre ?? "Emergencias")
                            .font(.title2.bold())
                        Text(centro?.telefonoParaMostrar ?? Telefono.emergencias)
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(Color.rojoCruzRoja)
                    }
                    .tarjetaConBorde()

                    coordenadas
                        .tarjetaConBorde()

                    Button {
                        llamar()
                    } label: {
                        Label("Llamar", systemImage: "phone.fill")
                    }
                    .buttonStyle(BotonRojo())

                    Button("Cerrar", action: cerrar)
                        .buttonStyle(BotonBorde())
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 24)
            }
            .pantalla("Llamada por teléfono")
            .alert("Directorio de prueba", isPresented: $avisoPrueba) {
                Button("Entendido", role: .cancel) { }
            } message: {
                Text("Este número es inventado y no se marca. Cuando centros.json tenga el directorio oficial, cambia Configuracion.directorioDePrueba a false.")
            }
        }
    }

    private var aviso: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(internet.hayConexion ? "No pudimos conectar con el servidor." : "Sin internet.")
                    .font(.headline)
                Text("Llama por línea telefónica a la delegación más cercana.")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rojoCruzRoja, in: RoundedRectangle(cornerRadius: Medida.radio, style: .continuous))
    }

    @ViewBuilder
    private var coordenadas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coordenadas GPS")
                .font(.caption.bold())
                .foregroundStyle(Color.rojoCruzRoja)
            if let punto {
                Text(Self.texto(punto.latitude, positivo: "N", negativo: "S"))
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(Self.texto(punto.longitude, positivo: "E", negativo: "O"))
                    .font(.title2.bold())
                    .monospacedDigit()
                Text("Díctaselas al operador.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No tenemos tu ubicación. Dile al operador una dirección o una referencia cercana.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 25.67141 → "25.6714° N"
    private static func texto(_ grados: Double, positivo: String, negativo: String) -> String {
        String(format: "%.4f° %@", abs(grados), grados >= 0 ? positivo : negativo)
    }

    private func llamar() {
        if Configuracion.directorioDePrueba {
            avisoPrueba = true
        } else {
            abrirURL(Telefono.url(numero))
        }
    }
}

#Preview {
    RespaldoSinInternetView(
        centro: Centro.todos.first,
        punto: CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.309)
    ) { }
    .environment(Internet())
}
