// HU11 · Delegación según mi ubicación: tarjeta "Tu delegación" de la pantalla Centro más cercano.

import SwiftUI

/// La delegación que te corresponde por tu ubicación y el número de su CECOM.
/// Cambia sola cuando te mueves a otra zona y sin internet usa el directorio guardado en el teléfono.
struct TarjetaDelegacion: View {
    @Environment(DirectorioDelegaciones.self) private var directorio
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(Internet.self) private var internet
    @Environment(\.openURL) private var abrirURL
    @State private var avisoPrueba = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ubicacion.coordenada == nil && directorio.actual != nil ? "ÚLTIMA DELEGACIÓN CONOCIDA" : "TU DELEGACIÓN")
                .font(.caption.bold())
                .foregroundStyle(Color.rojoCruzRoja)

            if let delegacion = directorio.actual {
                if let anterior = directorio.anterior {
                    Label("Cambiaste de zona. Antes te correspondía \(anterior.nombre).",
                          systemImage: "arrow.triangle.swap")
                        .font(.footnote.bold())
                        .foregroundStyle(Color.rojoCruzRoja)
                }

                Text(delegacion.nombre).font(.title3.bold())
                Label(delegacion.direccion ?? delegacion.estado, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let referencia = delegacion.referencia {
                    Label(referencia, systemImage: "signpost.right.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("CECOM", systemImage: "phone.fill")
                        .font(.subheadline)
                    Spacer()
                    Text(delegacion.telefonoParaMostrar)
                        .font(.title3.bold())
                        .monospacedDigit()
                        .foregroundStyle(Color.rojoCruzRoja)
                }
                .accessibilityElement(children: .combine)

                Button {
                    llamar(delegacion)
                } label: {
                    Label("Llamar a mi delegación", systemImage: "phone.fill")
                }
                .buttonStyle(BotonRojo())
            } else {
                Text("Aún no sabemos tu zona").font(.headline)
                Text("Activa tu ubicación para saber a qué delegación llamar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Label(textoDirectorio, systemImage: internet.hayConexion ? "checkmark.icloud" : "iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tarjeta()
        .alert("Directorio de prueba", isPresented: $avisoPrueba) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text("Los teléfonos del directorio son de prueba y no se marcan. Cuando la base tenga el directorio oficial, cambia Configuracion.directorioDePrueba a false.")
        }
    }

    /// De dónde salen los datos: del servidor o del directorio guardado en el teléfono.
    private var textoDirectorio: String {
        guard let fecha = directorio.confirmadoEn else {
            return internet.hayConexion ? "Descargando el directorio de delegaciones…"
                                        : "Sin internet: usando el directorio que trae la app."
        }
        let cuando = fecha.formatted(.relative(presentation: .named).locale(Locale(identifier: "es_MX")))
        return internet.hayConexion
            ? "Directorio de \(directorio.delegaciones.count) delegaciones, actualizado \(cuando)."
            : "Sin internet: usando el directorio guardado en el teléfono (actualizado \(cuando))."
    }

    private func llamar(_ delegacion: Delegacion) {
        if Configuracion.directorioDePrueba {
            avisoPrueba = true
        } else {
            abrirURL(Telefono.url(delegacion.telefonoLocal))
        }
    }
}

#Preview {
    TarjetaDelegacion()
        .padding()
        .environment(DirectorioDelegaciones())
        .environment(Ubicacion())
        .environment(Internet())
}
