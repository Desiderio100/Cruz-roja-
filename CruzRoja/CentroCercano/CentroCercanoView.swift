// El botón de llamar NO va aquí: irá en la página principal. Para marcar al
// centro más cercano desde ahí:
//     Link("Llamar", destination: Telefono.url(centro.telefono))

import SwiftUI
import MapKit

struct CentroCercanoView: View {
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(Internet.self) private var internet
    @State private var camara: MapCameraPosition = .region(.monterrey)
    @State private var prueba = false
    /// Último centro que te tocó, por si abres la app sin señal de GPS.
    @AppStorage("ultimoCentroCercano") private var ultimoCentroId = ""

    private var cercano: Centro? {
        if let punto = ubicacion.coordenada { return Centro.masCercano(a: punto) }
        return Centro.todos.first { $0.id == ultimoCentroId }
    }

    var body: some View {
        VStack(spacing: 0) {
            mapa
                .frame(height: 300)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !internet.hayConexion { AvisoSinInternet("la lista de centros sigue funcionando") }
                    AvisoPermisoUbicacion(motivo: "para mostrarte el centro de Cruz Roja más cercano")
                    TarjetaCentroCercano(centro: cercano, metros: distancia(a: cercano))
                    listaCentros
                    seccionPrueba
                }
                .padding()
            }
        }
        .navigationTitle("Centro más cercano")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: cercano) { _, nuevo in
            guard let nuevo else { return }
            ultimoCentroId = nuevo.id
            enfocar(nuevo)
        }
        .onAppear { if let cercano { enfocar(cercano) } }
        .task(id: prueba) { await correrPrueba() }
    }

    // MARK: Mapa satelital

    private var mapa: some View {
        Map(position: $camara) {
            ForEach(Centro.todos) { centro in
                Marker(centro.nombre, systemImage: "cross.fill", coordinate: centro.coordenada)
                    .tint(centro == cercano ? Color.rojoCruzRoja : .gray)
            }
            if let punto = ubicacion.coordenada {
                Annotation("Tú", coordinate: punto) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .overlay(alignment: .bottomTrailing) {
            if !internet.hayConexion {
                Label("Mapa guardado · sin internet", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private func enfocar(_ centro: Centro) {
        guard let punto = ubicacion.coordenada else {
            withAnimation { camara = .region(MKCoordinateRegion(center: centro.coordenada, latitudinalMeters: 4_000, longitudinalMeters: 4_000)) }
            return
        }
        let centroMapa = CLLocationCoordinate2D(latitude: (punto.latitude + centro.latitud) / 2,
                                                longitude: (punto.longitude + centro.longitud) / 2)
        let lado = max(abs(punto.latitude - centro.latitud), abs(punto.longitude - centro.longitud)) * 2.5 + 0.01
        withAnimation {
            camara = .region(MKCoordinateRegion(center: centroMapa,
                                                span: MKCoordinateSpan(latitudeDelta: lado, longitudeDelta: lado)))
        }
    }

    private func distancia(a centro: Centro?) -> CLLocationDistance? {
        guard let centro, let punto = ubicacion.coordenada else { return nil }
        return centro.distancia(desde: punto)
    }

    // MARK: Lista de centros

    private var filas: [(centro: Centro, metros: CLLocationDistance?)] {
        if let punto = ubicacion.coordenada {
            return Centro.ordenados(desde: punto).map { (centro: $0.centro, metros: Optional($0.metros)) }
        }
        return Centro.todos.map { (centro: $0, metros: nil as CLLocationDistance?) }
    }

    private var listaCentros: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Todos los centros").font(.headline)

            ForEach(Array(filas.enumerated()), id: \.element.centro.id) { i, fila in
                let esCercano = fila.centro == cercano && fila.metros != nil
                Button {
                    enfocar(fila.centro)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cross.fill")
                            .font(.caption.bold())
                            .foregroundStyle(esCercano ? Color.white : Color.secondary)
                            .frame(width: 26, height: 26)
                            .background(esCercano ? Color.rojoCruzRoja : Color.gray.opacity(0.2), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fila.centro.nombre).font(.subheadline.bold())
                            Text(esCercano ? "Más cercano" : fila.centro.direccion)
                                .font(.caption)
                                .foregroundStyle(esCercano ? Color.rojoCruzRoja : Color.secondary)
                        }
                        Spacer()
                        if let metros = fila.metros {
                            Text(textoDistancia(metros))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < filas.count - 1 { Divider() }
            }
        }
        .tarjeta()
    }

    // MARK: Prueba para presentar

    private var seccionPrueba: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Simular recorrido por Monterrey", isOn: $prueba)
                .tint(Color.rojoCruzRoja)
                .font(.subheadline.bold())
            Text("Para presentar: tu ubicación se mueve sola por Monterrey, como en carro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tarjeta()
    }

    private func correrPrueba() async {
        guard prueba else {
            ubicacion.detenerSimulacion()
            return
        }
        let paradas = Centro.todos.map {
            CLLocationCoordinate2D(latitude: $0.latitud + 0.006, longitude: $0.longitud - 0.004)
        }
        guard paradas.count > 1 else { return }
        let pasosPorTramo = 8
        var i = 0
        while !Task.isCancelled {
            let desde = paradas[(i / pasosPorTramo) % paradas.count]
            let hasta = paradas[(i / pasosPorTramo + 1) % paradas.count]
            let t = Double(i % pasosPorTramo) / Double(pasosPorTramo)
            ubicacion.simular(CLLocationCoordinate2D(latitude: desde.latitude + (hasta.latitude - desde.latitude) * t,
                                                     longitude: desde.longitude + (hasta.longitude - desde.longitude) * t))
            i += 1
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}

// MARK: - Tarjetas

private struct TarjetaCentroCercano: View {
    let centro: Centro?
    let metros: CLLocationDistance?
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(\.openURL) private var abrirURL
    @State private var eligiendoApp = false
    @State private var viendoRutasSinInternet = false
    @State private var anterior: (id: String, metros: Double)?
    @State private var acercandote: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sin ubicación mostramos el último centro que te tocó, y lo decimos.
            Text(ubicacion.coordenada == nil && centro != nil ? "ÚLTIMO CENTRO CERCANO CONOCIDO" : "TU CENTRO MÁS CERCANO")
                .font(.caption.bold())
                .foregroundStyle(Color.rojoCruzRoja)

            if let centro {
                Text(centro.nombre).font(.title2.bold())
                Label(centro.direccion, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let referencia = centro.referencia {
                    Label(referencia, systemImage: "signpost.right.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let metros, let punto = ubicacion.coordenada {
                    FlechaCentro(rumboAlCentro: rumboEntre(punto, centro.coordenada),
                                 tuRumbo: ubicacion.rumbo,
                                 metros: metros,
                                 acercandote: acercandote)
                        .padding(.vertical, 4)
                }

                Button {
                    eligiendoApp = true
                } label: {
                    Label("Cómo llegar", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(BotonRojo())
                // Google Maps y Waze abren su app si está instalada; si no, su página web.
                .confirmationDialog("Cómo llegar a \(centro.nombre)", isPresented: $eligiendoApp, titleVisibility: .visible) {
                    Button("Apple Maps") { centro.abrirEnAppleMaps() }
                    Button("Google Maps") { abrirURL(centro.urlGoogleMaps) }
                    Button("Waze") { abrirURL(centro.urlWaze) }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Sin internet, solo Apple Maps y Google Maps dan ruta si descargaste el mapa de Monterrey.")
                }

                Button("¿Rutas sin internet?") { viendoRutasSinInternet = true }
                    .font(.footnote.bold())
                    .foregroundStyle(Color.rojoCruzRoja)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Aún no sabemos tu zona").font(.title3.bold())
                Text("Activa tu ubicación o prende la prueba de abajo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .tarjeta()
        .sheet(isPresented: $viendoRutasSinInternet) { RutasSinInternetView() }
        .onChange(of: metros) { _, nuevo in revisarSiTeAcercas(nuevo) }
    }

    /// Compara la distancia nueva con la anterior para decir si vas bien.
    private func revisarSiTeAcercas(_ nuevo: CLLocationDistance?) {
        guard let centro, let nuevo else { anterior = nil; acercandote = nil; return }
        guard let previo = anterior, previo.id == centro.id else {
            anterior = (centro.id, nuevo)   // cambió el centro: empezamos de nuevo
            acercandote = nil
            return
        }
        guard abs(nuevo - previo.metros) >= 15 else { return } // ignorar brincos chicos del GPS
        acercandote = nuevo < previo.metros
        anterior = (centro.id, nuevo)
    }
}

/// Flecha que apunta al centro + "a 2.3 km · adelante a la derecha".
/// Solo usa GPS y brújula: funciona sin internet.
private struct FlechaCentro: View {
    let rumboAlCentro: CLLocationDirection
    let tuRumbo: CLLocationDirection?
    let metros: CLLocationDistance
    let acercandote: Bool?

    /// Si sabemos hacia dónde vas, la flecha es relativa a ti; si no, al norte.
    private var giro: Double {
        guard let tuRumbo else { return rumboAlCentro }
        return (rumboAlCentro - tuRumbo + 360).truncatingRemainder(dividingBy: 360)
    }

    private var sentido: String {
        tuRumbo == nil ? textoCardinal(rumboAlCentro) : textoRelativo(giro)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.north.fill")
                .font(.title)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(giro))
                .animation(.easeInOut, value: giro)
                .frame(width: 60, height: 60)
                .background(Color.rojoCruzRoja, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("a \(textoDistancia(metros))")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(sentido)
                    .font(.headline)
                if let acercandote {
                    Label(acercandote ? "Te estás acercando" : "Te estás alejando",
                          systemImage: acercandote ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(acercandote ? Color.green : Color.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension MKCoordinateRegion {
    /// Zona metropolitana de Monterrey (vista inicial).
    static let monterrey = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.6866, longitude: -100.3161),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
}

#Preview {
    NavigationStack {
        CentroCercanoView()
    }
    .environment(Ubicacion())
    .environment(Internet())
}
