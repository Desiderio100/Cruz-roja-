// La lista viene de centros.json, que va dentro de la app: funciona sin internet.
// Para agregar o corregir un centro, edita ese archivo.

import CoreLocation
import MapKit

// Los nombres de las propiedades deben coincidir con las llaves de centros.json.
struct Centro: Codable, Identifiable, Hashable {
    let id: String
    let nombre: String
    let telefono: String
    let direccion: String
    /// Cómo ubicarlo por avenidas principales: "Sobre Av. Constitución, …".
    let referencia: String?
    let latitud: Double
    let longitud: Double

    var coordenada: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitud, longitude: longitud)
    }

    /// Distancia en metros, en línea recta (no por calles).
    func distancia(desde punto: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitud, longitude: longitud)
            .distance(from: CLLocation(latitude: punto.latitude, longitude: punto.longitude))
    }

    func abrirEnAppleMaps() {
        let destino = MKMapItem(placemark: MKPlacemark(coordinate: coordenada))
        destino.name = nombre
        destino.phoneNumber = telefono
        destino.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    // Con enlaces universales iOS abre la app si está instalada; si no, la página web.
    // El `!` es seguro: la URL siempre es válida porque solo lleva números.
    var urlGoogleMaps: URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(latitud),\(longitud)&travelmode=driving")!
    }

    var urlWaze: URL {
        URL(string: "https://waze.com/ul?ll=\(latitud),\(longitud)&navigate=yes")!
    }
}

extension Centro {
    static let todos: [Centro] = {
        struct Archivo: Decodable { let centros: [Centro] }
        guard let url = Bundle.main.url(forResource: "centros", withExtension: "json"),
              let datos = try? Data(contentsOf: url),
              let archivo = try? JSONDecoder().decode(Archivo.self, from: datos)
        else {
            assertionFailure("No se pudo leer centros.json")
            return []
        }
        return archivo.centros
    }()

    static func masCercano(a punto: CLLocationCoordinate2D, entre centros: [Centro] = todos) -> Centro? {
        centros.min { $0.distancia(desde: punto) < $1.distancia(desde: punto) }
    }

    // La distancia se calcula una vez por centro y se guarda junto a él para ordenar.
    static func ordenados(desde punto: CLLocationCoordinate2D, entre centros: [Centro] = todos) -> [(centro: Centro, metros: CLLocationDistance)] {
        centros
            .map { (centro: $0, metros: $0.distancia(desde: punto)) }
            .sorted { $0.metros < $1.metros }
    }

    /// "8112345600" → "81 1234 5600". Si no tiene 10 dígitos, se deja como viene.
    var telefonoParaMostrar: String {
        let d = Array(telefono.filter { $0.isASCII && $0.isNumber })
        guard d.count == 10 else { return telefono }
        return "\(String(d[0..<2])) \(String(d[2..<6])) \(String(d[6..<10]))"
    }
}

/// Distancia legible: menos de 1 km en metros ("850 m"), si no en km con un decimal ("3.4 km").
func textoDistancia(_ metros: CLLocationDistance) -> String {
    metros < 1_000 ? "\(Int(metros.rounded())) m" : String(format: "%.1f km", metros / 1_000)
}

// MARK: - Dirección y sentido (funciona sin internet)

/// Rumbo en grados de `a` hacia `b` (0 = norte, 90 = este, 180 = sur, 270 = oeste).
/// Usa la fórmula del rumbo inicial sobre una esfera; solo necesita las coordenadas.
func rumboEntre(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDirection {
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    // atan2 da un ángulo entre -180° y 180°; se pasa a 0°–360°.
    let grados = atan2(y, x) * 180 / .pi
    return (grados + 360).truncatingRemainder(dividingBy: 360)
}

/// Punto cardinal para un rumbo: 45° → "al noreste".
func textoCardinal(_ grados: CLLocationDirection) -> String {
    let nombres = ["norte", "noreste", "este", "sureste", "sur", "suroeste", "oeste", "noroeste"]
    // Cada nombre cubre 45°, centrado en su dirección (norte = 337.5° a 22.5°).
    // Sumar 22.5 alinea esos rangos y `% 8` hace que 360° vuelva a "norte".
    return "al " + nombres[Int((grados + 22.5) / 45) % 8]
}

/// Dirección del centro respecto a hacia dónde vas: 90° → "a tu derecha".
/// `relativo` = rumbo al centro menos el rumbo de tu movimiento, en 0°–360°.
func textoRelativo(_ relativo: CLLocationDirection) -> String {
    // Mismo reparto en 8 sectores de 45° que en `textoCardinal`.
    let nombres = ["adelante", "adelante a la derecha", "a tu derecha", "atrás a la derecha",
                   "atrás", "atrás a la izquierda", "a tu izquierda", "adelante a la izquierda"]
    return nombres[Int((relativo + 22.5) / 45) % 8]
}
