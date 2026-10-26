//
//  Producto.swift
//  Ventas
//
//  Created by Sebastián Martinez on 20/10/26.
//


import Foundation

/// Un producto del catálogo "Productos con causa".
/// Los nombres de `CodingKeys` son los de la tabla `producto` de la base de datos,
/// para que el backend pueda mandar las columnas tal cual.
struct Producto: Identifiable, Decodable, Equatable {
    let id: Int
    let nombre: String
    let precioMXN: Decimal
    let causa: String
    let imagenURL: URL?
    /// Canal oficial de Cruz Roja. La compra ocurre allá, no en la app.
    let enlaceCompra: URL

    enum CodingKeys: String, CodingKey {
        case id, nombre, causa
        case precioMXN = "precio_mxn"
        case imagenURL = "imagen_url"
        case enlaceCompra = "enlace_compra"
    }

    /// "$150 MXN", o "$150.50 MXN" si el precio trae centavos.
    var precioTexto: String {
        let numero = NSDecimalNumber(decimal: precioMXN)
        let conCentavos = numero.doubleValue.truncatingRemainder(dividingBy: 1) != 0
        let formato = NumberFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.numberStyle = .decimal
        formato.minimumFractionDigits = conCentavos ? 2 : 0
        formato.maximumFractionDigits = 2
        return "$\(formato.string(from: numero) ?? numero.stringValue) MXN"
    }
}

extension Producto {
    /// Los mismos productos de 02_datos_prueba.sql, para trabajar sin backend.
    static let ejemplos: [Producto] = [
        Producto(id: 1, nombre: "Bolsa solidaria", precioMXN: 150,
                 causa: "Apoya atención prehospitalaria", imagenURL: nil,
                 enlaceCompra: URL(string: "https://tienda.ejemplo.invalid/bolsa")!),
        Producto(id: 2, nombre: "Termo solidario", precioMXN: 220,
                 causa: "Apoya programas de salud", imagenURL: nil,
                 enlaceCompra: URL(string: "https://tienda.ejemplo.invalid/termo")!),
        Producto(id: 3, nombre: "Botiquín personal", precioMXN: 250,
                 causa: "Apoya capacitación en primeros auxilios", imagenURL: nil,
                 enlaceCompra: URL(string: "https://tienda.ejemplo.invalid/botiquin")!),
        Producto(id: 4, nombre: "Playera solidaria", precioMXN: 180,
                 causa: "Apoya ayuda en desastres", imagenURL: nil,
                 enlaceCompra: URL(string: "https://tienda.ejemplo.invalid/playera")!)
    ]
}
