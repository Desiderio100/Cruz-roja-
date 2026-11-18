-- =====================================================================
-- App Cruz Roja - Rutinas de dispositivos y citas que usa la API
-- (backend/src/rutas/dispositivos.js y backend/src/rutas/citas.js)
-- =====================================================================
-- Estas cinco rutinas existían solo en Aiven y faltaban en esta carpeta: con una
-- base creada desde cero, POST /api/dispositivos y todo /api/citas respondían 500
-- (ER_SP_DOES_NOT_EXIST). Este archivo las deja reproducibles.
--
--   dispositivo_registrar   alta de un dispositivo; devuelve su id
--   citas_del_dispositivo   citas vigentes de un dispositivo (pospuestas primero)
--   cita_agendar            agenda en un horario libre y devuelve la cita
--   cita_cancelar           cancela una cita del dispositivo y libera el horario
--   cita_reprogramar        mueve una cita del dispositivo a otro horario libre
--
-- IMPORTANTE: están escritas a partir de lo que la API manda y de lo que la app
-- lee (CruzRoja/Citas/Modelos.swift). En Aiven NO reemplaza nada: usa
-- CREATE PROCEDURE IF NOT EXISTS, así que si la rutina ya existe se queda la de
-- Aiven. Sirve para una base nueva (tu MySQL local o la máquina virtual).
-- Requiere MySQL 8.0.29 o superior. Córrelo después del 01 y del 02.
--
-- Errores (los convierte backend/src/errores.js):
--   SQLSTATE 22023  datos inválidos                         -> HTTP 400
--   SQLSTATE 45000  "... no existe" -> 404; lo demás        -> HTTP 409
-- =====================================================================

USE cruzroja;
SET NAMES utf8mb4;

DELIMITER //

-- Crea un dispositivo y devuelve su id. El teléfono es opcional.
CREATE PROCEDURE IF NOT EXISTS dispositivo_registrar(IN p_telefono VARCHAR(16))
BEGIN
    DECLARE v_id CHAR(36) DEFAULT (UUID());
    IF p_telefono IS NOT NULL AND p_telefono NOT REGEXP '^[+]?[0-9]{10,15}$' THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'teléfono no válido';
    END IF;
    INSERT INTO dispositivo (id, telefono) VALUES (v_id, p_telefono);
    SELECT v_id AS id;
END//

-- Citas confirmadas o pospuestas del dispositivo. Las pospuestas van primero
-- porque la persona tiene que elegir un horario nuevo.
CREATE PROCEDURE IF NOT EXISTS citas_del_dispositivo(IN p_dispositivo CHAR(36))
BEGIN
    SELECT c.id, c.folio, c.servicio, c.inicio, c.estado,
           e.delegacion_id, d.nombre AS delegacion
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
      JOIN delegacion d   ON d.id = e.delegacion_id
     WHERE c.dispositivo_id = p_dispositivo
       AND c.estado IN ('confirmada', 'pospuesta')
     ORDER BY (c.estado = 'pospuesta') DESC, c.inicio;
END//

-- Agenda una cita. Elige al primer especialista libre de la delegación en ese
-- horario. p_inicio va en UTC; p_zona es el desfase del teléfono (por ejemplo
-- '-06:00') y sirve para comprobar que la hora cae dentro del horario de atención.
CREATE PROCEDURE IF NOT EXISTS cita_agendar(
    IN p_dispositivo   CHAR(36),
    IN p_delegacion_id INT,
    IN p_servicio      VARCHAR(20),
    IN p_inicio        DATETIME(3),
    IN p_zona          VARCHAR(40),
    IN p_nombre        VARCHAR(120),
    IN p_telefono      VARCHAR(16)
)
BEGIN
    DECLARE v_especialista INT DEFAULT NULL;
    DECLARE v_id CHAR(36) DEFAULT (UUID());

    IF p_servicio IS NULL OR p_servicio NOT IN ('nutricion', 'psicologia') THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'servicio no válido';
    END IF;
    IF p_nombre IS NULL OR CHAR_LENGTH(TRIM(p_nombre)) < 3 THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'escribe tu nombre completo';
    END IF;
    IF p_telefono IS NULL OR p_telefono NOT REGEXP '^[+]?[0-9]{10,15}$' THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'teléfono no válido';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM dispositivo WHERE id = p_dispositivo) THEN
        -- La app reconoce este mensaje: registra el dispositivo y reintenta.
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'dispositivo no registrado';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM delegacion WHERE id = p_delegacion_id AND activa = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la delegación no existe';
    END IF;

    -- Horarios libres de ese día (misma regla que ve la persona en la agenda).
    CALL horarios_calcular(p_delegacion_id, p_servicio,
                           DATE(CONVERT_TZ(p_inicio, '+00:00', p_zona)), p_zona);
    IF NOT EXISTS (SELECT 1 FROM cr_horarios WHERE inicio = p_inicio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ese horario ya no está disponible';
    END IF;

    SELECT e.id INTO v_especialista
      FROM especialista e
     WHERE e.delegacion_id = p_delegacion_id
       AND e.servicio      = p_servicio
       AND e.activo        = 1
       AND NOT EXISTS (SELECT 1 FROM cita c
                        WHERE c.especialista_id = e.id
                          AND c.inicio          = p_inicio
                          AND c.confirmada      = 1)
     ORDER BY e.id
     LIMIT 1
       FOR UPDATE;
    IF v_especialista IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ese horario ya no está disponible';
    END IF;

    INSERT INTO cita (id, especialista_id, servicio, inicio, nombre, telefono, dispositivo_id, aviso_aceptado)
    VALUES (v_id, v_especialista, p_servicio, p_inicio, TRIM(p_nombre), p_telefono, p_dispositivo, 1);

    SELECT c.id, c.folio, c.servicio, c.inicio, c.estado,
           e.delegacion_id, d.nombre AS delegacion
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
      JOIN delegacion d   ON d.id = e.delegacion_id
     WHERE c.id = v_id;
END//

-- Cancela una cita del dispositivo. El horario queda libre (RF24).
CREATE PROCEDURE IF NOT EXISTS cita_cancelar(IN p_id CHAR(36), IN p_dispositivo CHAR(36))
BEGIN
    UPDATE cita
       SET estado = 'cancelada'
     WHERE id = p_id AND dispositivo_id = p_dispositivo
       AND estado IN ('confirmada', 'pospuesta');
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cita no existe';
    END IF;
END//

-- Mueve una cita del dispositivo a otro horario libre de la misma delegación y
-- servicio, y la deja confirmada (RF25: elegir otro horario si la pospusieron).
CREATE PROCEDURE IF NOT EXISTS cita_reprogramar(
    IN p_id          CHAR(36),
    IN p_dispositivo CHAR(36),
    IN p_inicio      DATETIME(3),
    IN p_zona        VARCHAR(40)
)
BEGIN
    DECLARE v_delegacion   INT DEFAULT NULL;
    DECLARE v_servicio     VARCHAR(20) DEFAULT NULL;
    DECLARE v_especialista INT DEFAULT NULL;

    SELECT e.delegacion_id, c.servicio INTO v_delegacion, v_servicio
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
     WHERE c.id = p_id AND c.dispositivo_id = p_dispositivo
       AND c.estado IN ('confirmada', 'pospuesta');
    IF v_delegacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cita no existe';
    END IF;

    CALL horarios_calcular(v_delegacion, v_servicio,
                           DATE(CONVERT_TZ(p_inicio, '+00:00', p_zona)), p_zona);
    IF NOT EXISTS (SELECT 1 FROM cr_horarios WHERE inicio = p_inicio) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ese horario ya no está disponible';
    END IF;

    SELECT e.id INTO v_especialista
      FROM especialista e
     WHERE e.delegacion_id = v_delegacion
       AND e.servicio      = v_servicio
       AND e.activo        = 1
       AND NOT EXISTS (SELECT 1 FROM cita c
                        WHERE c.especialista_id = e.id
                          AND c.inicio          = p_inicio
                          AND c.confirmada      = 1)
     ORDER BY e.id
     LIMIT 1
       FOR UPDATE;
    IF v_especialista IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ese horario ya no está disponible';
    END IF;

    UPDATE cita
       SET especialista_id = v_especialista, inicio = p_inicio, estado = 'confirmada'
     WHERE id = p_id;

    SELECT c.id, c.folio, c.servicio, c.inicio, c.estado,
           e.delegacion_id, d.nombre AS delegacion
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
      JOIN delegacion d   ON d.id = e.delegacion_id
     WHERE c.id = p_id;
END//

DELIMITER ;

-- Revisa el resultado: deben aparecer las cinco rutinas.
SELECT routine_type AS tipo, routine_name AS nombre
  FROM information_schema.ROUTINES
 WHERE routine_schema = 'cruzroja'
   AND routine_name IN ('dispositivo_registrar', 'citas_del_dispositivo', 'cita_agendar',
                        'cita_cancelar', 'cita_reprogramar')
 ORDER BY routine_name;
