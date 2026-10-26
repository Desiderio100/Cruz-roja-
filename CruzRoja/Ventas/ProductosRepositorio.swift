//
//  Productosrepositorio.swift
//  Ventas
//
//  Created by Sebastián Martinez on 20/10/26.
//

import Foundation

/// De dónde salen los productos. La pantalla solo conoce este protocolo:
/// cuando el backend esté listo se escribe otra versión que llame a tu API
/// y la pantalla no cambia.
protocol ProductosRepositorio {
    func productos() async throws -> [Producto]
}

/// Datos fijos para desarrollar la pantalla sin backend.
struct ProductosDeEjemplo: ProductosRepositorio {
    func productos() async throws -> [Producto] {
        Producto.ejemplos
    }
}

