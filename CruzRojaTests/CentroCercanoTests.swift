//
//  CentroCercanoTests.swift
//  Pruebas unitarias de HU11 · Delegación según mi ubicación (Centro más cercano).
//
//  Usan centros con coordenadas fijas para no depender de centros.json,
//  salvo la prueba que revisa que ese directorio se pueda leer.
//

import CoreLocation
import Testing
@testable import CruzRoja

@Suite("HU11 · Centro más cercano")
struct CentroCercanoTests {
    let centro = CentroCercanoTests.crearCentro("centro", latitud: 25.6714, longitud: -100.3090)
    let sanNicolas = CentroCercanoTests.crearCentro("san-nicolas", latitud: 25.7417, longitud: -100.3010)
    let sanPedro = CentroCercanoTests.crearCentro("san-pedro", latitud: 25.6573, longitud: -100.4029)

    var todos: [Centro] { [centro, sanNicolas, sanPedro] }

    /// Crea un centro de prueba con solo lo necesario para calcular distancias.
    static func crearCentro(_ id: String, latitud: Double, longitud: Double,
                            telefono: String = "8112345600") -> Centro {
        Centro(id: id, nombre: id, telefono: telefono, direccion: "Dirección de prueba",
               referencia: nil, latitud: latitud, longitud: longitud)
    }

    // MARK: - CA11.1 · La app actualiza la delegación que me corresponde

    @Test("Elige el centro más cercano a mi ubicación")
    func eligeElMasCercano() {
        let juntoASanNicolas = CLLocationCoordinate2D(latitude: 25.7400, longitude: -100.3000)
        #expect(Centro.masCercano(a: juntoASanNicolas, entre: todos)?.id == "san-nicolas")
    }

    @Test("Al moverme a otra zona cambia el centro que me corresponde")
    func cambiaAlMoverme() {
        let enElCentro = CLLocationCoordinate2D(latitude: 25.6720, longitude: -100.3100)
        let enSanPedro = CLLocationCoordinate2D(latitude: 25.6600, longitude: -100.4000)
        #expect(Centro.masCercano(a: enElCentro, entre: todos)?.id == "centro")
        #expect(Centro.masCercano(a: enSanPedro, entre: todos)?.id == "san-pedro")
    }

    @Test("Sin centros no regresa ninguno")
    func sinCentros() {
        let punto = CLLocationCoordinate2D(latitude: 25.6720, longitude: -100.3100)
        #expect(Centro.masCercano(a: punto, entre: []) == nil)
    }

    @Test("La lista va del más cercano al más lejano")
    func ordenadosPorDistancia() {
        let enElCentro = CLLocationCoordinate2D(latitude: 25.6720, longitude: -100.3100)
        let lista = Centro.ordenados(desde: enElCentro, entre: todos)
        let distancias = lista.map { $0.metros }
        #expect(lista.map { $0.centro.id } == ["centro", "san-nicolas", "san-pedro"])
        #expect(distancias == distancias.sorted())
    }

    // MARK: - CA11.2 · Sin internet usa el directorio guardado en el teléfono

    @Test("El directorio guardado en la app se puede leer")
    func directorioGuardado() {
        #expect(!Centro.todos.isEmpty)
        #expect(Centro.todos.allSatisfy { !$0.telefono.isEmpty })
    }

    // MARK: - Textos de la tarjeta

    @Test("Distancia legible", arguments: [
        (850.0, "850 m"),
        (999.4, "999 m"),
        (3_400.0, "3.4 km"),
    ])
    func distanciaLegible(metros: Double, esperado: String) {
        #expect(textoDistancia(metros) == esperado)
    }

    @Test("Sentido del centro respecto a hacia dónde voy", arguments: [
        (0.0, "adelante"),
        (90.0, "a tu derecha"),
        (180.0, "atrás"),
        (350.0, "adelante"),
    ])
    func sentidoRelativo(grados: Double, esperado: String) {
        #expect(textoRelativo(grados) == esperado)
    }

    @Test("Punto cardinal hacia el centro")
    func puntoCardinal() {
        let origen = CLLocationCoordinate2D(latitude: 25.0, longitude: -100.0)
        let alNorte = CLLocationCoordinate2D(latitude: 26.0, longitude: -100.0)
        let alEste = CLLocationCoordinate2D(latitude: 25.0, longitude: -99.0)
        #expect(textoCardinal(rumboEntre(origen, alNorte)) == "al norte")
        #expect(textoCardinal(rumboEntre(origen, alEste)) == "al este")
    }

    @Test("Teléfono con espacios para leerlo fácil")
    func telefonoParaMostrar() {
        #expect(centro.telefonoParaMostrar == "81 1234 5600")
        let corto = Self.crearCentro("corto", latitud: 0, longitud: 0, telefono: "911")
        #expect(corto.telefonoParaMostrar == "911")
    }
}
