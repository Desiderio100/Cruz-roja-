-- =====================================================================
-- 10_modo_personal.sql  (MySQL 8.0.16 o superior)
-- Modo personal de Cruz Roja (RF31 a RF33): lo que necesita el panel web de llamadas y citas
-- (carpeta personal/CruzRoja.Personal, en C#). Copia EXACTA de lo que ya está en la base de Aiven
-- (sacado del respaldo del 15-nov-2026), para que el repositorio pueda crear la misma base desde cero.
--
-- EN AIVEN NO HACE FALTA CORRERLO: todo esto ya existe ahí. Si lo corres de todos modos no pasa
-- nada (se puede repetir): solo vuelve a crear los procedimientos con el mismo código.
-- Sirve para una base nueva (tu MySQL local, la máquina virtual de la escuela...).
-- Orden: 01, 02, 03, 08, 09, 10. No hace falta volver a correr el 03: la cuenta cruzroja_app ya puede
-- llamar procedimientos (GRANT EXECUTE del 03) y el panel solo usa procedimientos.
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--
-- Qué agrega
--   personal        el personal también puede entrar con su MATRÍCULA (25 letras y números). Se guarda
--                   solo su huella SHA-256 (matricula_huella), nunca la matrícula. Por eso usuario y
--                   hash_contrasena ahora pueden ir vacíos, pero cada cuenta necesita al menos una forma
--                   de entrar: matrícula, o usuario + contraseña (la del sitio de pedidos /admin).
--   intento_acceso  intentos fallidos de matrícula por dirección de internet (bloqueo temporal).
--   transcripcion   lo que se dice en la llamada, línea por línea, para la ficha con IA.
--   Procedimientos  entrar con matrícula, abrir la siguiente llamada, ver su detalle, guardar la ficha,
--                   finalizar, llamadas perdidas, transcripción, citas del día y posponer una cita.
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1. personal: entrada con matrícula. Una sola sentencia: o se aplica completa o nada.
--    ¿Ya está aplicado? (la columna matricula_huella es la señal)
-- ---------------------------------------------------------------------
SET @zz_ya := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE table_schema = 'cruzroja' AND table_name = 'personal' AND column_name = 'matricula_huella');

SET @zz_sql := IF(@zz_ya > 0, 'DO 0', '
ALTER TABLE personal
    MODIFY COLUMN usuario          VARCHAR(60)  NULL,
    MODIFY COLUMN hash_contrasena  VARCHAR(255) NULL,
    ADD COLUMN    matricula_huella CHAR(64)     NULL AFTER hash_contrasena,
    ADD UNIQUE KEY personal_matricula_uq (matricula_huella),
    ADD CONSTRAINT personal_huella_formato
        CHECK (matricula_huella IS NULL OR matricula_huella REGEXP ''^[0-9a-f]{64}$''),
    ADD CONSTRAINT personal_tiene_credencial
        CHECK (matricula_huella IS NOT NULL OR (usuario IS NOT NULL AND hash_contrasena IS NOT NULL))');

PREPARE zz_s FROM @zz_sql;
EXECUTE zz_s;
DEALLOCATE PREPARE zz_s;

-- ---------------------------------------------------------------------
-- 2. Tablas nuevas
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intento_acceso (
    origen          VARCHAR(45) NOT NULL,                 -- dirección de internet de quien intenta entrar
    intentos        SMALLINT    NOT NULL DEFAULT 0,
    bloqueado_hasta DATETIME(3) NULL,
    actualizado_en  DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (origen),
    CONSTRAINT intento_acceso_no_negativo CHECK (intentos >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS transcripcion (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    llamada_id  CHAR(36)        NOT NULL,
    hablante    ENUM('operador', 'solicitante') NOT NULL,
    texto       VARCHAR(1000)   NOT NULL,
    momento_seg INT UNSIGNED    NOT NULL,                 -- segundos desde que empezó la llamada
    PRIMARY KEY (id),
    KEY transcripcion_llamada_idx (llamada_id, id),
    CONSTRAINT transcripcion_llamada_fk FOREIGN KEY (llamada_id) REFERENCES llamada (id) ON DELETE CASCADE,
    CONSTRAINT transcripcion_texto_no_vacio CHECK (CHAR_LENGTH(TRIM(texto)) >= 1)
) ENGINE=InnoDB
  COMMENT='Contradice el comentario de la tabla llamada (no se guarda transcripción): decisión del equipo para llenar la ficha.';

-- ---------------------------------------------------------------------
-- 3. Funciones y procedimientos del panel (mismo código que en Aiven)
-- ---------------------------------------------------------------------
DELIMITER //

DROP FUNCTION IF EXISTS personal_delegacion_de//
CREATE FUNCTION personal_delegacion_de(p_personal CHAR(36), p_rol VARCHAR(20)) RETURNS int
    READS SQL DATA
BEGIN
    DECLARE v_id INT DEFAULT NULL;
    SELECT delegacion_id INTO v_id
      FROM personal
     WHERE id = p_personal AND activo = 1 AND rol = p_rol;
    RETURN v_id;
END//

DROP PROCEDURE IF EXISTS llamadas_marcar_perdidas//
CREATE PROCEDURE llamadas_marcar_perdidas(IN p_segundos INT)
BEGIN
    UPDATE llamada
       SET estado = 'perdida', fin = UTC_TIMESTAMP(3)
     WHERE operador_id IS NULL
       AND estado IN ('entrante', 'en_curso')
       AND inicio <= UTC_TIMESTAMP(3) - INTERVAL p_segundos SECOND;
END//

DROP PROCEDURE IF EXISTS llamada_detalle//
CREATE PROCEDURE llamada_detalle(IN p_personal CHAR(36), IN p_llamada CHAR(36))
BEGIN
    DECLARE v_deleg INT;
    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo un operador activo puede ver llamadas';
    END IF;

    SELECT l.id AS llamada_id, l.estado, l.canal, l.inicio, d.nombre AS delegacion,
           l.solicitante_telefono, l.telefono_verificado,
           l.latitud, l.longitud, l.precision_m,
           f.nombre, f.celular, f.motivo, f.num_lesionados, f.lesion_principal,
           f.lugar, f.ubicacion, f.comentarios,
           f.editado_por, f.actualizada AS ficha_actualizada
      FROM llamada l
      JOIN delegacion d ON d.id = l.delegacion_id
      LEFT JOIN ficha f ON f.llamada_id = l.id
     WHERE l.id = p_llamada AND l.operador_id = p_personal;
END//

DROP PROCEDURE IF EXISTS llamada_abrir_siguiente//
CREATE PROCEDURE llamada_abrir_siguiente(IN p_personal CHAR(36))
BEGIN
    DECLARE v_deleg   INT;
    DECLARE v_llamada CHAR(36) DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo un operador activo puede abrir llamadas';
    END IF;

    CALL llamadas_marcar_perdidas(60);

    START TRANSACTION;

    SELECT id INTO v_llamada
      FROM llamada
     WHERE operador_id = p_personal AND estado IN ('entrante', 'en_curso')
     ORDER BY inicio, id
     LIMIT 1
       FOR UPDATE;

    IF v_llamada IS NULL THEN
        SELECT id INTO v_llamada
          FROM llamada
         WHERE delegacion_id = v_deleg AND operador_id IS NULL AND estado IN ('entrante', 'en_curso')
         ORDER BY inicio, id
         LIMIT 1
           FOR UPDATE;

        IF v_llamada IS NOT NULL THEN
            UPDATE llamada
               SET operador_id = p_personal, estado = 'en_curso',
                   conectada_en = COALESCE(conectada_en, UTC_TIMESTAMP(3))
             WHERE id = v_llamada;
        END IF;
    END IF;

    COMMIT;

    IF v_llamada IS NOT NULL THEN
        CALL llamada_detalle(p_personal, v_llamada);
    END IF;
END//

DROP PROCEDURE IF EXISTS llamada_finalizar//
CREATE PROCEDURE llamada_finalizar(IN p_personal CHAR(36), IN p_llamada CHAR(36))
BEGIN
    DECLARE v_deleg INT;
    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL OR NOT EXISTS (SELECT 1 FROM llamada WHERE id = p_llamada AND operador_id = p_personal) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la llamada no es de este operador';
    END IF;

    UPDATE llamada
       SET estado = 'finalizada', fin = UTC_TIMESTAMP(3)
     WHERE id = p_llamada AND operador_id = p_personal AND estado IN ('entrante', 'en_curso');
END//

DROP PROCEDURE IF EXISTS ficha_guardar//
CREATE PROCEDURE ficha_guardar(
    IN p_personal         CHAR(36),
    IN p_llamada          CHAR(36),
    IN p_nombre           VARCHAR(120),
    IN p_celular          VARCHAR(20),
    IN p_motivo           VARCHAR(500),
    IN p_num_lesionados   INT,
    IN p_lesion_principal VARCHAR(200),
    IN p_lugar            VARCHAR(300),
    IN p_ubicacion        VARCHAR(300),
    IN p_comentarios      TEXT
)
BEGIN
    DECLARE v_deleg   INT;
    DECLARE v_celular VARCHAR(20);
    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL OR NOT EXISTS (SELECT 1 FROM llamada WHERE id = p_llamada AND operador_id = p_personal) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la llamada no es de este operador';
    END IF;

    SET v_celular = NULLIF(REPLACE(REPLACE(TRIM(p_celular), ' ', ''), '-', ''), '');
    IF v_celular IS NOT NULL AND v_celular NOT REGEXP '^[+]?[0-9]{10,15}$' THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'celular no valido';
    END IF;
    IF p_num_lesionados IS NOT NULL AND (p_num_lesionados < 0 OR p_num_lesionados > 32767) THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'numero de lesionados no valido';
    END IF;

    UPDATE ficha
       SET nombre           = NULLIF(TRIM(p_nombre), ''),
           celular          = v_celular,
           motivo           = NULLIF(TRIM(p_motivo), ''),
           num_lesionados   = p_num_lesionados,
           lesion_principal = NULLIF(TRIM(p_lesion_principal), ''),
           lugar            = NULLIF(TRIM(p_lugar), ''),
           ubicacion        = NULLIF(TRIM(p_ubicacion), ''),
           comentarios      = NULLIF(TRIM(p_comentarios), ''),
           editado_por      = p_personal
     WHERE llamada_id = p_llamada;

    SELECT actualizada AS ficha_actualizada FROM ficha WHERE llamada_id = p_llamada;
END//

DROP PROCEDURE IF EXISTS transcripcion_listar//
CREATE PROCEDURE transcripcion_listar(IN p_personal CHAR(36), IN p_llamada CHAR(36), IN p_desde_id BIGINT UNSIGNED)
BEGIN
    DECLARE v_deleg INT;
    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL OR NOT EXISTS (SELECT 1 FROM llamada WHERE id = p_llamada AND operador_id = p_personal) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la llamada no es de este operador';
    END IF;

    SELECT t.id, t.hablante, t.texto, t.momento_seg
      FROM transcripcion t
     WHERE t.llamada_id = p_llamada AND t.id > p_desde_id
     ORDER BY t.id;
END//

DROP PROCEDURE IF EXISTS llamadas_perdidas_listar//
CREATE PROCEDURE llamadas_perdidas_listar(IN p_personal CHAR(36), IN p_horas INT)
BEGIN
    DECLARE v_deleg INT;
    SET v_deleg = personal_delegacion_de(p_personal, 'operador');
    IF v_deleg IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo un operador activo puede ver llamadas';
    END IF;

    CALL llamadas_marcar_perdidas(60);

    SELECT l.id AS llamada_id, l.inicio, l.solicitante_nombre, l.solicitante_telefono, l.telefono_verificado
      FROM llamada l
     WHERE l.delegacion_id = v_deleg
       AND l.estado = 'perdida'
       AND l.inicio >= UTC_TIMESTAMP(3) - INTERVAL p_horas HOUR
     ORDER BY l.inicio DESC;
END//

DROP PROCEDURE IF EXISTS personal_login_matricula//
CREATE PROCEDURE personal_login_matricula(
    IN p_huella       CHAR(64),
    IN p_origen       VARCHAR(45),
    IN p_max          INT,
    IN p_bloqueo_min  INT
)
BEGIN
    DECLARE v_intentos SMALLINT    DEFAULT 0;
    DECLARE v_hasta    DATETIME(3) DEFAULT NULL;
    DECLARE v_id       CHAR(36)    DEFAULT NULL;
    DECLARE v_rol      VARCHAR(20) DEFAULT NULL;
    DECLARE v_deleg    INT         DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(120) DEFAULT NULL;
    DECLARE v_permiso  TINYINT(1)  DEFAULT NULL;
    DECLARE v_estado   VARCHAR(12) DEFAULT 'incorrecta';
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT IGNORE INTO intento_acceso (origen) VALUES (p_origen);
    SELECT intentos, bloqueado_hasta INTO v_intentos, v_hasta
      FROM intento_acceso WHERE origen = p_origen FOR UPDATE;

    IF v_hasta IS NOT NULL AND v_hasta > UTC_TIMESTAMP(3) THEN
        SET v_estado = 'bloqueado';
    ELSE
        IF v_hasta IS NOT NULL THEN
            SET v_intentos = 0;
            SET v_hasta = NULL;
        END IF;

        SELECT p.id, p.rol, p.delegacion_id, d.nombre, p.permiso_contenido
          INTO v_id, v_rol, v_deleg, v_nombre, v_permiso
          FROM personal p
          JOIN delegacion d ON d.id = p.delegacion_id
         WHERE p.matricula_huella = p_huella AND p.activo = 1;

        IF v_id IS NOT NULL THEN
            SET v_estado = 'ok';
            UPDATE intento_acceso
               SET intentos = 0, bloqueado_hasta = NULL, actualizado_en = UTC_TIMESTAMP(3)
             WHERE origen = p_origen;
            UPDATE personal SET ultimo_acceso = UTC_TIMESTAMP(3) WHERE id = v_id;
        ELSE
            SET v_intentos = v_intentos + 1;
            IF v_intentos >= p_max THEN
                SET v_hasta = UTC_TIMESTAMP(3) + INTERVAL p_bloqueo_min MINUTE;
                SET v_estado = 'bloqueado';
            END IF;
            UPDATE intento_acceso
               SET intentos = v_intentos, bloqueado_hasta = v_hasta, actualizado_en = UTC_TIMESTAMP(3)
             WHERE origen = p_origen;
        END IF;
    END IF;

    COMMIT;

    SELECT v_estado AS estado, v_id AS personal_id, v_rol AS rol, v_deleg AS delegacion_id,
           v_nombre AS delegacion, v_permiso AS permiso_contenido, v_hasta AS bloqueado_hasta;
END//

DROP PROCEDURE IF EXISTS citas_del_dia//
CREATE PROCEDURE citas_del_dia(IN p_personal CHAR(36), IN p_fecha DATE, IN p_zona VARCHAR(40))
BEGIN
    DECLARE v_deleg  INT;
    DECLARE v_desde  DATETIME;
    SET v_deleg = personal_delegacion_de(p_personal, 'administrativo');
    IF v_deleg IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo el personal administrativo activo puede ver citas';
    END IF;

    SET v_desde = CONVERT_TZ(TIMESTAMP(p_fecha, '00:00:00'), p_zona, '+00:00');
    IF v_desde IS NULL THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'zona horaria desconocida: usa un desfase como -06:00';
    END IF;

    SELECT c.folio, c.inicio, c.servicio, c.estado, c.nombre, c.telefono,
           e.id AS especialista_id, e.nombre AS especialista
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
     WHERE e.delegacion_id = v_deleg
       AND c.inicio >= v_desde
       AND c.inicio <  v_desde + INTERVAL 1 DAY
     ORDER BY e.id, c.inicio;
END//

DROP PROCEDURE IF EXISTS cita_posponer_personal//
CREATE PROCEDURE cita_posponer_personal(IN p_personal CHAR(36), IN p_folio VARCHAR(16))
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_id    CHAR(36) DEFAULT NULL;
    SET v_deleg = personal_delegacion_de(p_personal, 'administrativo');
    IF v_deleg IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo el personal administrativo activo puede posponer citas';
    END IF;

    SELECT c.id INTO v_id
      FROM cita c
      JOIN especialista e ON e.id = c.especialista_id
     WHERE c.folio = p_folio AND e.delegacion_id = v_deleg;
    IF v_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cita no existe en esta delegacion';
    END IF;

    UPDATE cita SET estado = 'pospuesta' WHERE id = v_id AND estado = 'confirmada';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo se puede posponer una cita confirmada';
    END IF;
END//

DELIMITER ;

-- Revisa el resultado: deben aparecer las 11 rutinas y la columna matricula_huella.
SELECT routine_type AS tipo, routine_name AS nombre
  FROM information_schema.ROUTINES
 WHERE routine_schema = 'cruzroja'
   AND routine_name IN ('personal_delegacion_de', 'llamadas_marcar_perdidas', 'llamada_detalle',
                        'llamada_abrir_siguiente', 'llamada_finalizar', 'ficha_guardar', 'transcripcion_listar',
                        'llamadas_perdidas_listar', 'personal_login_matricula', 'citas_del_dia',
                        'cita_posponer_personal')
 ORDER BY routine_name;
