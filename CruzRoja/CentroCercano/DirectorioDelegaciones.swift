// HU11 · Delegación según mi ubicación.
//
//   • Con internet baja el directorio de GET /api/delegaciones y lo guarda en el teléfono.
//     Solo lo vuelve a bajar completo si la versión del servidor cambió.
//   • Sin internet usa la copia guardada (o, la primera vez, delegaciones.json, que va dentro de la app).
//   • Cada vez que cambia tu ubicación recalcula la delegación que te corresponde.
//
// Uso:
//     @Environment(DirectorioDelegaciones.self) private var directorio
//     directorio.actual            // tu delegación (o nil si aún no sabemos tu zona)
//     directorio.actual?.telefono  // el número de su CECOM
//
// La app lo crea una vez (App/CruzRojaApp.swift) y lo mantiene al día con `.seguirDelegacion()`.

import CoreLocation
import Foundation
import Observation
import SwiftUI

/// Respuesta de GET /api/delegaciones.
struct RespuestaDirectorio: Decodable {
    let version: Int
    let sinCambios: Bool?
    let delegaciones: [Delegacion]?
}

/// De dónde sale el directorio. La app usa el backend; las pruebas, una fuente en memoria.
@MainActor
protocol FuenteDirectorio {
    /// - Parameter version: la versión que ya tiene el teléfono, o `nil` para pedir el directorio completo.
    func descargar(version: Int?) async throws -> RespuestaDirectorio
}

/// El directorio del backend.
@MainActor
struct ServidorDirectorio: FuenteDirectorio {
    func descargar(version: Int?) async throws -> RespuestaDirectorio {
        let consulta = version.map { [URLQueryItem(name: "version", value: String($0))] } ?? []
        let datos = try await ClienteAPI.compartido.pedir("GET", "/api/delegaciones", consulta: consulta, conDispositivo: false)
        return try ClienteAPI.compartido.decodificar(RespuestaDirectorio.self, datos)
    }
}

@MainActor
@Observable
final class DirectorioDelegaciones {
    /// Delegaciones activas, como las dio el servidor la última vez.
    private(set) var delegaciones: [Delegacion] = []
    /// Versión del directorio (sube en la base con cada alta, cambio o baja de una delegación).
    private(set) var version = 0
    /// Última vez que el servidor confirmó el directorio. `nil` = solo tenemos la copia que trae la app.
    private(set) var confirmadoEn: Date?
    /// La delegación que te corresponde por tu ubicación.
    private(set) var actual: Delegacion?
    /// La delegación que tenías antes de cambiar de zona (para avisarte del cambio).
    private(set) var anterior: Delegacion?
    private(set) var actualizando = false

    /// Para no brincar de una delegación a otra en la frontera entre dos zonas: la nueva
    /// tiene que estar al menos 2 km más cerca que la actual.
    static let margenCambio: CLLocationDistance = 2_000

    @ObservationIgnored private let archivo: URL
    @ObservationIgnored private let almacen: UserDefaults
    @ObservationIgnored private let fuente: any FuenteDirectorio
    @ObservationIgnored private var ultimoPunto: CLLocationCoordinate2D?

    private static let claveActual = "delegacion.actual"

    /// Archivo donde se guarda la copia del directorio en el teléfono.
    nonisolated static var archivoPorDefecto: URL {
        URL.applicationSupportDirectory.appending(path: "directorio-delegaciones.json")
    }

    /// - Parameters:
    ///   - archivo: dónde guardar la copia del directorio (las pruebas usan uno temporal).
    ///   - almacen: dónde recordar la última delegación conocida.
    ///   - fuente: de dónde bajar el directorio (por defecto, el backend).
    init(archivo: URL = DirectorioDelegaciones.archivoPorDefecto,
         almacen: UserDefaults = .standard,
         fuente: (any FuenteDirectorio)? = nil) {
        self.archivo = archivo
        self.almacen = almacen
        self.fuente = fuente ?? ServidorDirectorio()

        if let guardado = Self.leer(archivo) ?? Self.leerIncluido() {
            delegaciones = guardado.delegaciones
            version = guardado.version
            confirmadoEn = guardado.confirmadoEn
        }
        let idActual = almacen.integer(forKey: Self.claveActual)
        actual = delegaciones.first { $0.id == idActual }
    }

    /// El directorio guardado en el teléfono (o el que trae la app), para quien lo necesita fuera
    /// de las vistas: Siri, el chat y el respaldo de Emergencia, por medio de `Centro.todos`.
    nonisolated static func copiaGuardada(archivo: URL = archivoPorDefecto) -> [Delegacion] {
        (leer(archivo) ?? leerIncluido())?.delegaciones ?? []
    }

    /// La delegación más cercana a un punto según el directorio guardado.
    func masCercana(a punto: CLLocationCoordinate2D) -> Delegacion? {
        Delegacion.masCercana(a: punto, entre: delegaciones)
    }

    /// Recalcula tu delegación con una ubicación nueva. Sin ubicación se queda la última conocida.
    func ubicar(_ punto: CLLocationCoordinate2D?) {
        guard let punto else { return }
        ultimoPunto = punto
        guard let candidata = masCercana(a: punto) else { return }

        guard let actual, let vigente = delegaciones.first(where: { $0.id == actual.id }) else {
            elegir(candidata)          // primera vez, o tu delegación ya no está en el directorio
            return
        }
        if candidata.id == vigente.id {
            if vigente != actual { self.actual = vigente }   // mismo id con datos nuevos (p. ej. otro teléfono)
            return
        }
        if candidata.distancia(desde: punto) + Self.margenCambio < vigente.distancia(desde: punto) {
            anterior = vigente
            elegir(candidata)
        }
    }

    /// Baja el directorio del servidor y lo guarda en el teléfono. Si no hay internet o el
    /// servidor no responde, no pasa nada: se sigue usando la copia guardada.
    func actualizar() async {
        guard !actualizando else { return }
        actualizando = true
        defer { actualizando = false }

        // Si la copia es la que trae la app, se pide completa para guardarla ya confirmada.
        guard let respuesta = try? await fuente.descargar(version: confirmadoEn == nil ? nil : version) else { return }
        if respuesta.sinCambios != true, let nuevas = respuesta.delegaciones {
            delegaciones = nuevas
            version = respuesta.version
        }
        confirmadoEn = .now
        guardar()
        if let actual, !delegaciones.contains(where: { $0.id == actual.id }) { self.actual = nil }
        ubicar(ultimoPunto)
    }

    // MARK: Guardar en el teléfono

    private struct Copia: Codable {
        let version: Int
        let confirmadoEn: Date?
        let delegaciones: [Delegacion]
    }

    private func elegir(_ delegacion: Delegacion) {
        actual = delegacion
        almacen.set(delegacion.id, forKey: Self.claveActual)
    }

    private func guardar() {
        let copia = Copia(version: version, confirmadoEn: confirmadoEn, delegaciones: delegaciones)
        guard let datos = try? JSONEncoder().encode(copia) else { return }
        try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? datos.write(to: archivo, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated private static func leer(_ archivo: URL) -> Copia? {
        guard let datos = try? Data(contentsOf: archivo),
              let copia = try? JSONDecoder().decode(Copia.self, from: datos),
              !copia.delegaciones.isEmpty
        else { return nil }
        return copia
    }

    /// delegaciones.json va dentro de la app: así hay directorio aun si nunca hubo internet.
    nonisolated private static func leerIncluido() -> Copia? {
        struct Incluido: Decodable { let version: Int; let delegaciones: [Delegacion] }
        guard let url = Bundle.main.url(forResource: "delegaciones", withExtension: "json"),
              let datos = try? Data(contentsOf: url),
              let incluido = try? JSONDecoder().decode(Incluido.self, from: datos)
        else { return nil }
        return Copia(version: incluido.version, confirmadoEn: nil, delegaciones: incluido.delegaciones)
    }
}

// MARK: - Seguir la delegación en toda la app

/// Mantiene al día la delegación de la persona: baja el directorio cuando hay internet y
/// recalcula la delegación cada vez que cambia la ubicación. Va una sola vez, en la raíz de la app.
private struct SeguirDelegacion: ViewModifier {
    @Environment(DirectorioDelegaciones.self) private var directorio
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(Internet.self) private var internet
    @Environment(\.scenePhase) private var fase

    func body(content: Content) -> some View {
        content
            .task(id: "\(internet.hayConexion)-\(fase == .active)") {
                guard internet.hayConexion, fase == .active else { return }
                await directorio.actualizar()
            }
            .onChange(of: PuntoGPS(ubicacion.coordenada), initial: true) { _, punto in
                directorio.ubicar(punto.coordenada)
            }
    }
}

/// `CLLocationCoordinate2D` no es Equatable; esto permite usarla en `.onChange`.
private struct PuntoGPS: Equatable {
    let coordenada: CLLocationCoordinate2D?

    init(_ coordenada: CLLocationCoordinate2D?) { self.coordenada = coordenada }

    static func == (a: PuntoGPS, b: PuntoGPS) -> Bool {
        a.coordenada?.latitude == b.coordenada?.latitude && a.coordenada?.longitude == b.coordenada?.longitude
    }
}

extension View {
    /// Mantiene al día `DirectorioDelegaciones` (ver `SeguirDelegacion`).
    func seguirDelegacion() -> some View {
        modifier(SeguirDelegacion())
    }
}
