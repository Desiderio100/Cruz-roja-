//
//  Configuracion.swift
//  Compartido por TODAS las pantallas (Comun/).
//
//  Aquí vive la dirección del backend. Si cambia (otra IP, el dominio real),
//  se cambia en este único archivo y todas las pantallas se enteran.
//

import Foundation

enum Configuracion {
    /// Dirección base del backend (la API que habla con la base de datos).
    /// La app NUNCA se conecta directo a MySQL: siempre pasa por esta API.
    static let apiBaseURL: URL = {
        #if DEBUG && targetEnvironment(simulator)
        // Simulador: el backend corre en tu Mac.
        return URL(string: "http://localhost:3000")!
        #elseif DEBUG
        // iPhone real: la IP de la Mac donde corre el backend (misma red Wi‑Fi).
        // Cambia cada vez que la Mac se conecta a otra red: actualízala aquí.
        return URL(string: "http://10.22.160.207:3000")!
        #else
        // Producción: cambia por el dominio real del backend. Siempre https.
        return URL(string: "https://api.tu-dominio.com")!
        #endif
    }()

    /// La misma dirección como texto, sin "/" al final (la usa el módulo de citas).
    static var urlBase: String { apiBaseURL.absoluteString }

    /// Delegación que usa la agenda de citas por ahora (2 = Monterrey en los datos de prueba).
    /// Provisional: cuando la pantalla de delegaciones entregue la más cercana, se toma de ahí.
    static let delegacionId = 2

    /// Botón Donar de la pantalla principal: abre el canal oficial de Cruz Roja Mexicana.
    /// Cambiar por la página exacta de donativos que nos dé el socio formador.
    static let urlDonar = URL(string: "https://www.cruzrojamexicana.org.mx")!

    /// true mientras centros.json tenga teléfonos INVENTADOS: el respaldo sin internet de
    /// Emergencia muestra el número pero NO lo marca (podría ser el número de alguien real).
    /// Pásalo a false solo cuando centros.json tenga el directorio oficial.
    static let directorioDePrueba = true
}
