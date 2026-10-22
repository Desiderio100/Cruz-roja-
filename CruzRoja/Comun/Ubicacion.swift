// Uso:
//     @Environment(Ubicacion.self) private var ubicacion
//
//     ubicacion.coordenada       // dónde estás (o nil si aún no sabemos)
//     ubicacion.rumbo            // hacia dónde vas o miras, en grados (0 = norte)
//     ubicacion.tienePermiso     // ¿ya nos dio permiso?
//     ubicacion.pedirPermiso()   // muestra la alerta de iOS
//
// Así nadie del equipo tiene que crear su propio CLLocationManager.

import CoreLocation
import Observation

@Observable
final class Ubicacion: NSObject, CLLocationManagerDelegate {
    private(set) var permiso: CLAuthorizationStatus = .notDetermined
    private(set) var coordenada: CLLocationCoordinate2D?
    /// Hacia dónde vas (en carro, por el GPS) o hacia dónde apunta el teléfono
    /// (caminando, por la brújula). 0 = norte, 90 = este. Funciona sin internet.
    private(set) var rumbo: CLLocationDirection?
    private(set) var simulando = false

    var tienePermiso: Bool { permiso == .authorizedWhenInUse || permiso == .authorizedAlways }
    var permisoNegado: Bool { permiso == .denied || permiso == .restricted }

    @ObservationIgnored private let manager = CLLocationManager()
    /// En carro el teléfono va en el soporte y la brújula falla; usamos el GPS.
    @ObservationIgnored private var enMovimiento = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50
        manager.headingFilter = 10
        permiso = manager.authorizationStatus
    }

    func pedirPermiso() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: Prueba (recorrido simulado)

    /// Pone una ubicación falsa.
    func simular(_ punto: CLLocationCoordinate2D) {
        if simulando, let anterior = coordenada {
            rumbo = rumboEntre(anterior, punto) // como si fueras en carro
        }
        simulando = true
        coordenada = punto
    }

    /// Regresa al GPS real.
    func detenerSimulacion() {
        guard simulando else { return }
        simulando = false
        coordenada = manager.location?.coordinate
        rumbo = nil
    }

    // MARK: Avisos de iOS

    // Cuando cambia el permiso (también al abrir la app).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permiso = manager.authorizationStatus
        if tienePermiso {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !simulando, let ultima = locations.last, ultima.horizontalAccuracy >= 0 else { return }
        coordenada = ultima.coordinate
        // Más de ~10 km/h: vas en carro → el rumbo sale del GPS.
        enMovimiento = ultima.speed > 3 && ultima.course >= 0
        if enMovimiento { rumbo = ultima.course }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        // Caminando o parado: el rumbo sale de la brújula.
        guard !simulando, !enMovimiento, heading.headingAccuracy >= 0 else { return }
        rumbo = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Error temporal (p. ej. sin señal): iOS sigue intentando solo.
    }
}
