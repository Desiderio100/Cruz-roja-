-- =====================================================================
-- 12_transcripcion_app.sql  (MySQL 8.0 o superior)
-- Transcripción de la llamada de emergencia desde el teléfono (RF12, HU09).
--
-- El iPhone convierte a texto lo que dice la persona (en el propio teléfono) y manda cada
-- frase a la API (POST /api/llamadas/:id/transcripcion). La API llama a este procedimiento
-- y el panel del operador lee las líneas con transcripcion_listar (10_modo_personal.sql).
--
-- La tabla transcripcion ya existe (la crea el 10). La cuenta cruzroja_app no tiene permisos
-- sobre esa tabla y no los necesita: solo llama al procedimiento (GRANT EXECUTE del 03).
-- Por eso NO hace falta volver a correr el 03.
--
-- Orden: después del 10. Se puede repetir: vuelve a crear el procedimiento con el mismo código.
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

DELIMITER //

DROP PROCEDURE IF EXISTS transcripcion_agregar//
CREATE PROCEDURE transcripcion_agregar(
    IN p_llamada     CHAR(36),
    IN p_dispositivo CHAR(36),
    IN p_texto       VARCHAR(1000),
    IN p_momento_seg INT UNSIGNED
)
BEGIN
    DECLARE v_lineas INT DEFAULT 0;

    -- Solo el teléfono que hizo la llamada puede agregarle texto, y solo mientras sigue abierta.
    IF NOT EXISTS (SELECT 1 FROM llamada
                    WHERE id = p_llamada AND dispositivo_id = p_dispositivo
                      AND estado IN ('entrante', 'en_curso')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la llamada no existe o ya terminó';
    END IF;

    IF p_texto IS NULL OR CHAR_LENGTH(TRIM(p_texto)) = 0 THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'la línea de la transcripción está vacía';
    END IF;

    -- Tope por llamada, para que un teléfono no pueda llenar la tabla.
    SELECT COUNT(*) INTO v_lineas FROM transcripcion WHERE llamada_id = p_llamada;
    IF v_lineas >= 2000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la transcripción de esta llamada ya está completa';
    END IF;

    INSERT INTO transcripcion (llamada_id, hablante, texto, momento_seg)
    VALUES (p_llamada, 'solicitante', TRIM(p_texto), p_momento_seg);

    SELECT LAST_INSERT_ID() AS id;
END//

DELIMITER ;

-- Revisa el resultado: debe aparecer el procedimiento.
SELECT routine_type AS tipo, routine_name AS nombre
  FROM information_schema.ROUTINES
 WHERE routine_schema = 'cruzroja' AND routine_name = 'transcripcion_agregar';
