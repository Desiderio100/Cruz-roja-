#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
struct BuscarCentrosTool: Tool {
    let name = "buscarCentros"
    let description = "Busca los centros de Cruz Roja más cercanos a la persona."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Cuántos centros mostrar", .range(1...5))
        let cantidad: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.buscarCentros(cantidad: arguments.cantidad)
    }
}

@available(iOS 26.0, *)
struct ProponerRutaTool: Tool {
    let name = "proponerRuta"
    let description = "Prepara abrir la ruta a un centro de la lista. Si la persona no dijo la aplicación, déjala vacía: la pantalla le mostrará botones para elegir. La persona confirma con un botón."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número del centro en la lista", .range(1...5))
        let numero: Int
        @Guide(description: "Apple Maps, Google Maps o Waze. Déjalo vacío si la persona no lo dijo, sin preguntar")
        let aplicacion: String
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.proponerRuta(numero: arguments.numero, aplicacion: arguments.aplicacion)
    }
}

@available(iOS 26.0, *)
struct ListarCursosTool: Tool {
    let name = "listarCursos"
    let description = "Muestra los próximos cursos de capacitación."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Cuántos cursos mostrar", .range(1...10))
        let cantidad: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.listarCursos(cantidad: arguments.cantidad)
    }
}

@available(iOS 26.0, *)
struct DetalleCursoTool: Tool {
    let name = "detalleCurso"
    let description = "Da el detalle de un curso de la lista."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número del curso en la lista", .range(1...10))
        let numero: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.detalleCurso(numero: arguments.numero)
    }
}

@available(iOS 26.0, *)
struct ProponerInscripcionTool: Tool {
    let name = "proponerInscripcion"
    let description = "Prepara la inscripción a un curso de la lista. La persona confirma con un botón."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número del curso en la lista", .range(1...10))
        let numero: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.proponerInscripcion(numero: arguments.numero)
    }
}

@available(iOS 26.0, *)
struct VerHorariosTool: Tool {
    let name = "verHorarios"
    let description = "Consulta los horarios libres de nutrición o psicología en un día."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "nutrición o psicología")
        let servicio: String
        @Guide(description: "hoy, mañana, un día de la semana o una fecha AAAA-MM-DD")
        let dia: String
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.verHorarios(servicio: arguments.servicio, dia: arguments.dia)
    }
}

@available(iOS 26.0, *)
struct VerMisCitasTool: Tool {
    let name = "verMisCitas"
    let description = "Muestra las citas de la persona."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "nutrición, psicología o vacío para todas")
        let servicio: String
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.verMisCitas(servicio: arguments.servicio)
    }
}

@available(iOS 26.0, *)
struct ProponerCitaTool: Tool {
    let name = "proponerCita"
    let description = "Prepara agendar un horario de la última lista de horarios. La persona confirma con un botón."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número del horario en la lista", .range(1...30))
        let numeroHorario: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.proponerCita(numeroHorario: arguments.numeroHorario)
    }
}

@available(iOS 26.0, *)
struct ProponerCancelacionTool: Tool {
    let name = "proponerCancelacion"
    let description = "Prepara cancelar una cita de la lista. La persona confirma con un botón."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número de la cita en la lista", .range(1...20))
        let numeroCita: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.proponerCancelacion(numeroCita: arguments.numeroCita)
    }
}

@available(iOS 26.0, *)
struct ProponerReprogramacionTool: Tool {
    let name = "proponerReprogramacion"
    let description = "Prepara elegir un nuevo horario para una cita pospuesta. La persona confirma con un botón."
    let acciones: AccionesChat

    @Generable
    struct Arguments {
        @Guide(description: "Número de la cita pospuesta en la lista", .range(1...20))
        let numeroCita: Int
        @Guide(description: "Número del nuevo horario en la lista", .range(1...30))
        let numeroHorario: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await acciones.proponerReprogramacion(numeroCita: arguments.numeroCita, numeroHorario: arguments.numeroHorario)
    }
}
#endif
