// HU11 · Delegación según mi ubicación. Una delegación es a quien se llama: su CECOM
// (centro de comunicaciones). Los datos salen de la tabla `delegacion` de la base, por
// GET /api/delegaciones, y la app guarda una copia para usarla sin internet
// (ver DirectorioDelegaciones.swift).

import CoreLocation
import Foundation

/// Una delegación de Cruz Roja y el teléfono de su CECOM.
/// Los nombres de las propiedades coinciden con los de GET /api/delegaciones.
struct Delegacion: Codable, Identifiable, Hashable {
    let id: Int
    let nombre: String
    /// Como viene de la base: "+528100000002".
    let telefono: String
    let latitud: Double
    let longitud: Double
    /// Estado de la república: "Nuevo León".
    let estado: String
    /// "Centro de Monterrey, N.L." (puede no venir).
    var direccion: String? = nil
    /// Cómo ubicarla por avenidas principales: "Sobre Av. Constitución, …" (puede no venir).
    var referencia: String? = nil

    var coordenada: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitud, longitude: longitud)
    }

    /// Distancia en metros, en línea recta (la misma fórmula que usa la base para elegirla).
    func distancia(desde punto: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitud, longitude: longitud)
            .distance(from: CLLocation(latitude: punto.latitude, longitude: punto.longitude))
    }

    /// Los 10 dígitos para marcar desde México: "+528100000002" → "8100000002".
    var telefonoLocal: String {
        let digitos = telefono.filter { $0.isASCII && $0.isNumber }
        return digitos.count == 12 && digitos.hasPrefix("52") ? String(digitos.dropFirst(2)) : digitos
    }

    /// "81 0000 0002" para leerlo fácil.
    var telefonoParaMostrar: String { comoCentro.telefonoParaMostrar }

    /// La misma delegación como `Centro`, para las pantallas que ya trabajan con centros
    /// (el respaldo telefónico de Emergencia).
    var comoCentro: Centro {
        Centro(id: "delegacion-\(id)", nombre: nombre, telefono: telefonoLocal, direccion: direccion ?? estado,
               referencia: referencia, latitud: latitud, longitud: longitud)
    }
}

extension Delegacion {
    /// La delegación más cercana a un punto, o `nil` si no hay ninguna.
    static func masCercana(a punto: CLLocationCoordinate2D, entre delegaciones: [Delegacion]) -> Delegacion? {
        delegaciones.min { $0.distancia(desde: punto) < $1.distancia(desde: punto) }
    }
}
