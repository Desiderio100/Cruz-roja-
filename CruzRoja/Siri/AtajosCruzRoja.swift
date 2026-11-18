import AppIntents

struct AtajosCruzRoja: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CentrosCercanosIntent(),
            phrases: [
                "Centro más cercano de \(.applicationName)",
                "Centros cercanos de \(.applicationName)",
                "Buscar un centro de \(.applicationName)"
            ],
            shortTitle: "Centros cercanos",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: RutaCentroIntent(),
            phrases: [
                "Llévame al centro más cercano de \(.applicationName)",
                "Ruta al centro de \(.applicationName)",
                "Cómo llegar a \(.applicationName)"
            ],
            shortTitle: "Ruta al centro",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: MisCitasIntent(),
            phrases: [
                "Mis citas en \(.applicationName)",
                "Ver mis citas de \(.applicationName)"
            ],
            shortTitle: "Mis citas",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AgendarCitaIntent(),
            phrases: [
                "Agendar una cita en \(.applicationName)",
                "Quiero una cita en \(.applicationName)"
            ],
            shortTitle: "Agendar cita",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: CancelarCitaIntent(),
            phrases: [
                "Cancelar mi cita en \(.applicationName)",
                "Cancelar una cita de \(.applicationName)"
            ],
            shortTitle: "Cancelar cita",
            systemImageName: "calendar.badge.minus"
        )
        AppShortcut(
            intent: ReprogramarCitaIntent(),
            phrases: [
                "Reprogramar mi cita en \(.applicationName)",
                "Reprogramar una cita de \(.applicationName)"
            ],
            shortTitle: "Reprogramar cita",
            systemImageName: "calendar.badge.clock"
        )
    }
}
