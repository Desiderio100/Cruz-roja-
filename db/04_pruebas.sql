-- =====================================================================
-- 04_pruebas.sql  (MySQL 8.0 o superior)
-- Pruebas del esquema. Necesita 01_esquema.sql, 02_datos_prueba.sql y (para la
-- prueba 10) 03_permisos_app.sql ya corridos.
--
-- Cada prueba corre dentro de una transacción que se deshace al terminar, así que
-- no deja datos en la base. Lo único que avanza son los contadores consecutivos
-- (folios e ids), por eso no las corras en la base de producción.
-- Si una prueba falla, las demás siguen y el resultado final dice cuál falló y por qué.
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--   Tarda unos segundos. Al final aparece una tabla con una fila por prueba:
--   todas deben decir OK (la prueba 10 puede decir OMITIDA si aún no existe cruzroja_app).
--   El script crea unos procedimientos temporales que empiezan con zz_ y los borra al terminar.
--
-- Nota: TRUNCATE no se prueba aquí porque en MySQL guarda los cambios por sí solo.
-- La app no puede hacerlo porque no tiene el permiso DROP (lo verifica la prueba 10).
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS zz_correr_pruebas;
DROP PROCEDURE IF EXISTS zz_registrar;
DROP PROCEDURE IF EXISTS zz_afirmar;
DROP PROCEDURE IF EXISTS zz_debe_fallar;
DROP PROCEDURE IF EXISTS zz_prueba_01;
DROP PROCEDURE IF EXISTS zz_prueba_02;
DROP PROCEDURE IF EXISTS zz_prueba_03;
DROP PROCEDURE IF EXISTS zz_prueba_04;
DROP PROCEDURE IF EXISTS zz_prueba_05;
DROP PROCEDURE IF EXISTS zz_prueba_06;
DROP PROCEDURE IF EXISTS zz_prueba_07;
DROP PROCEDURE IF EXISTS zz_prueba_08;
DROP PROCEDURE IF EXISTS zz_prueba_09;
DROP PROCEDURE IF EXISTS zz_prueba_10;
DROP PROCEDURE IF EXISTS zz_prueba_11;
DROP PROCEDURE IF EXISTS zz_prueba_12;
DROP PROCEDURE IF EXISTS zz_prueba_13;
DROP PROCEDURE IF EXISTS zz_prueba_14;
DROP PROCEDURE IF EXISTS zz_prueba_15;
DROP PROCEDURE IF EXISTS zz_prueba_16;
DROP PROCEDURE IF EXISTS zz_prueba_17;

DELIMITER //

-- ---------------------------------------------------------------------
-- Herramientas de las pruebas
-- ---------------------------------------------------------------------

-- Guarda una fila en la tabla de resultados (vive solo en tu sesión).
CREATE PROCEDURE zz_registrar(IN p_n INT, IN p_resultado VARCHAR(10), IN p_texto VARCHAR(400))
BEGIN
    INSERT INTO zz_resultados (n, resultado, detalle) VALUES (p_n, p_resultado, p_texto);
END//

-- Falla con un mensaje si la condición no es verdadera.
CREATE PROCEDURE zz_afirmar(IN p_condicion TINYINT, IN p_mensaje VARCHAR(120))
BEGIN
    IF p_condicion IS NULL OR p_condicion = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_mensaje;
    END IF;
END//

-- Ejecuta una instrucción que DEBE fallar con el error esperado. Falla si no da error
-- o si da otro error (p_estado en NULL = no revisar el SQLSTATE).
CREATE PROCEDURE zz_debe_fallar(IN p_sql TEXT, IN p_errno INT, IN p_estado CHAR(5), IN p_mensaje VARCHAR(100))
BEGIN
    DECLARE v_errno  INT     DEFAULT 0;
    DECLARE v_estado CHAR(5) DEFAULT '00000';
    DECLARE v_texto  VARCHAR(200);

    BEGIN
        -- 1265 ("Data truncated") es un error en modo estricto pero MySQL lo clasifica como aviso
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, 1265
            GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_estado = RETURNED_SQLSTATE;
        SET @zz_sql_dinamico = p_sql;
        PREPARE zz_s FROM @zz_sql_dinamico;
        IF v_errno = 0 THEN
            EXECUTE zz_s;
            DEALLOCATE PREPARE zz_s;
        END IF;
    END;

    IF v_errno = 0 THEN
        SET v_texto = LEFT(CONCAT('debió fallar y no falló: ', p_mensaje), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
    END IF;
    IF v_errno <> p_errno OR (p_estado IS NOT NULL AND v_estado <> p_estado) THEN
        SET v_texto = LEFT(CONCAT(p_mensaje, ': dio el error ', v_errno, ' (', v_estado, ') y se esperaba ', p_errno), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
    END IF;
END//

-- ---------------------------------------------------------------------
-- 1. Delegación más cercana (RF17)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_01(IN p_n INT)
BEGIN
    DECLARE v_total INT;
    DECLARE v_malas INT;
    DECLARE v_lejos INT;
    DECLARE v_mty   INT;
    DECLARE v_km    DOUBLE;

    -- Un punto a unos 3 km de cada delegación devuelve esa delegación.
    SELECT COUNT(*) INTO v_total FROM delegacion WHERE nombre LIKE '%(prueba)';
    CALL zz_afirmar(v_total = 6, 'se esperaban 6 delegaciones de prueba (corre 02_datos_prueba.sql)');
    SELECT COUNT(*) INTO v_malas FROM delegacion d
     WHERE d.nombre LIKE '%(prueba)'
       AND delegacion_cercana_id(d.latitud + 0.02, d.longitud - 0.02) <> d.id;
    CALL zz_afirmar(v_malas = 0, 'un punto cercano a una delegación devolvió otra delegación');
    SELECT COUNT(*) INTO v_lejos FROM delegacion d
     WHERE d.nombre LIKE '%(prueba)'
       AND distancia_km(d.latitud + 0.02, d.longitud - 0.02, d.latitud, d.longitud) >= 5;
    CALL zz_afirmar(v_lejos = 0, 'distancia absurda: un punto a 3 km salió a 5 km o más');

    -- Saltillo queda a unos 75 km en línea recta de Monterrey (75.1 km con Haversine).
    SELECT id, distancia_km(25.4232, -101.0053, latitud, longitud) INTO v_mty, v_km
      FROM delegacion WHERE nombre = 'Cruz Roja Monterrey (prueba)';
    CALL zz_afirmar(delegacion_cercana_id(25.4232, -101.0053) = v_mty, 'Saltillo debe devolver Monterrey');
    CALL zz_afirmar(v_km BETWEEN 74.5 AND 75.7, 'la distancia Saltillo-Monterrey debe ser de unos 75.1 km');
    -- Distancia larga, calculada aparte con la fórmula de Haversine (radio de la Tierra 6371 km).
    CALL zz_afirmar(distancia_km(32.5149, -117.0382, 20.9674, -89.5926) BETWEEN 2998 AND 3003,
                    'la distancia Tijuana-Mérida debe ser de unos 3000 km');

    CALL zz_registrar(p_n, 'OK', 'delegación más cercana y distancia correctas');
END//

-- ---------------------------------------------------------------------
-- 2. Una delegación inactiva no se ofrece; coordenadas fuera de rango fallan
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_02(IN p_n INT)
BEGIN
    DECLARE v_mty INT;
    DECLARE v_id  INT;

    SELECT id INTO v_mty FROM delegacion WHERE nombre = 'Cruz Roja Monterrey (prueba)';
    UPDATE delegacion SET activa = 0 WHERE id = v_mty;
    SET v_id = delegacion_cercana_id(25.6866, -100.3161);
    CALL zz_afirmar(v_id IS NOT NULL AND v_id <> v_mty, 'se ofreció una delegación inactiva');
    UPDATE delegacion SET activa = 1 WHERE id = v_mty;

    CALL zz_debe_fallar('DO delegacion_cercana_id(91, 0)',        1644, '22023', 'latitud 91');
    CALL zz_debe_fallar('DO delegacion_cercana_id(0, 181)',       1644, '22023', 'longitud 181');
    CALL zz_debe_fallar('DO delegacion_cercana_id(NULL, NULL)',   1644, '22023', 'coordenadas nulas');

    CALL zz_registrar(p_n, 'OK', 'delegaciones inactivas y coordenadas inválidas');
END//

-- ---------------------------------------------------------------------
-- 3. Versiones del directorio (RF18)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_03(IN p_n INT)
BEGIN
    DECLARE v0  INT;
    DECLARE v1  INT;
    DECLARE rv0 INT;
    DECLARE rv1 INT;

    SELECT version INTO v0  FROM directorio_meta WHERE id = 1;
    SELECT version INTO rv0 FROM delegacion WHERE nombre = 'Cruz Roja Puebla (prueba)';

    UPDATE delegacion SET telefono_cecom = '+522200000099' WHERE nombre = 'Cruz Roja Puebla (prueba)';
    SELECT version INTO v1  FROM directorio_meta WHERE id = 1;
    SELECT version INTO rv1 FROM delegacion WHERE nombre = 'Cruz Roja Puebla (prueba)';
    CALL zz_afirmar(v1 = v0 + 1,   'una modificación debe subir la versión del directorio');
    CALL zz_afirmar(rv1 = rv0 + 1, 'una modificación debe subir la versión de la fila');

    INSERT INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado)
    VALUES ('Cruz Roja Nueva (prueba)', '+525500000007', 19.0, -99.0, 'Ciudad de México');
    CALL zz_afirmar((SELECT version FROM directorio_meta WHERE id = 1) = v1 + 1,
                    'un alta debe subir la versión del directorio');

    DELETE FROM delegacion WHERE nombre = 'Cruz Roja Nueva (prueba)';
    CALL zz_afirmar((SELECT version FROM directorio_meta WHERE id = 1) = v1 + 2,
                    'una baja debe subir la versión del directorio');

    CALL zz_debe_fallar('INSERT INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado)
                         VALUES (''Mala (prueba)'', ''abc'', 19.0, -99.0, ''X'')',
                        3819, NULL, 'debió rechazar un teléfono inválido');
    CALL zz_debe_fallar('INSERT INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado)
                         VALUES (''Mala (prueba)'', ''+525500000008'', 95.0, -99.0, ''X'')',
                        3819, NULL, 'debió rechazar latitud 95');
    CALL zz_debe_fallar('INSERT INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado)
                         VALUES (''Cruz Roja Centro (prueba)'', ''+525500000008'', 19.0, -99.0, ''X'')',
                        1062, NULL, 'debió rechazar un nombre repetido');

    CALL zz_registrar(p_n, 'OK', 'versiones del directorio y validaciones');
END//

-- ---------------------------------------------------------------------
-- 4. Personal (RF31, RNF07)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_04(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_hash  VARCHAR(100) DEFAULT '$argon2id$v=19$m=19456,t=2,p=1$c2FsdGRlcHJ1ZWJh$aGFzaGRlcHJ1ZWJh';
    DECLARE v_uuid4 INT;
    DECLARE v_dist  INT;

    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';

    -- El id se genera solo y es un UUID versión 4 (aleatorio, no adivinable).
    SELECT COUNT(*), COUNT(DISTINCT id) INTO v_uuid4, v_dist FROM personal
     WHERE usuario IN ('operador.prueba', 'admin.prueba')
       AND id REGEXP '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
    CALL zz_afirmar(v_uuid4 = 2 AND v_dist = 2, 'los ids de personal deben ser UUID v4 distintos');

    -- el permiso de contenido es solo de administrativos
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol, permiso_contenido)
                                VALUES (', v_deleg, ', ''operador.malo'', ', QUOTE(v_hash), ', ''operador'', 1)'),
                        3819, NULL, 'un operador no debe tener permiso de contenido');
    -- usuario en minúsculas
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''Mayusculas'', ', QUOTE(v_hash), ', ''operador'')'),
                        3819, NULL, 'debió rechazar un usuario con mayúsculas');
    -- usuario de al menos 3 caracteres
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''ab'', ', QUOTE(v_hash), ', ''operador'')'),
                        3819, NULL, 'debió rechazar un usuario de 2 caracteres');
    -- usuario único
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''operador.prueba'', ', QUOTE(v_hash), ', ''operador'')'),
                        1062, NULL, 'debió rechazar un usuario repetido');
    -- toda cuenta pertenece a una delegación
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (NULL, ''sin.delegacion'', ', QUOTE(v_hash), ', ''operador'')'),
                        1048, NULL, 'debió exigir delegación');
    -- la delegación debe existir
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (999999, ''delegacion.falsa'', ', QUOTE(v_hash), ', ''operador'')'),
                        1452, NULL, 'debió rechazar una delegación inexistente');
    -- el rol solo puede ser uno de los dos
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''rol.raro'', ', QUOTE(v_hash), ', ''dios'')'),
                        1265, NULL, 'debió rechazar un rol que no existe');

    CALL zz_registrar(p_n, 'OK', 'restricciones de personal');
END//

-- ---------------------------------------------------------------------
-- 5. Llamadas (RF05 a RF11)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_05(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_ll    CHAR(36) DEFAULT UUID();
    DECLARE v_sin_id INT;

    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';

    INSERT INTO llamada (id, delegacion_id, solicitante_nombre, solicitante_telefono, telefono_verificado,
                         latitud, longitud, precision_m)
    VALUES (v_ll, v_deleg, 'Persona de prueba', '+525512345678', 1, 19.4326, -99.1332, 12.5);
    CALL zz_afirmar((SELECT estado FROM llamada WHERE id = v_ll) = 'entrante', 'estado inicial: entrante');
    CALL zz_afirmar((SELECT canal  FROM llamada WHERE id = v_ll) = 'internet', 'canal inicial: internet');
    CALL zz_afirmar((SELECT video_aceptado FROM llamada WHERE id = v_ll) = 0, 'el video empieza sin aceptar');

    -- Una llamada sin nombre, número ni ubicación debe poder registrarse (RF08),
    -- y su id se genera solo como UUID versión 4.
    INSERT INTO llamada (delegacion_id) VALUES (v_deleg);
    SELECT COUNT(*) INTO v_sin_id FROM llamada
     WHERE delegacion_id = v_deleg AND solicitante_nombre IS NULL AND latitud IS NULL
       AND id REGEXP '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
    CALL zz_afirmar(v_sin_id = 1, 'una llamada sin datos debe registrarse con un id UUID v4');

    -- latitud sin longitud
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, latitud) VALUES (', v_deleg, ', 19.4)'),
                        3819, NULL, 'debió rechazar una ubicación incompleta');
    -- verificado sin teléfono
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, telefono_verificado) VALUES (', v_deleg, ', 1)'),
                        3819, NULL, 'debió rechazar verificado sin teléfono');
    -- fin antes de inicio
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, inicio, fin) VALUES (', v_deleg,
                               ', UTC_TIMESTAMP(3), UTC_TIMESTAMP(3) - INTERVAL 1 MINUTE)'),
                        3819, NULL, 'debió rechazar fin anterior al inicio');
    -- el canal solo puede ser internet o telefonica
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, canal) VALUES (', v_deleg, ', ''radio'')'),
                        1265, NULL, 'debió rechazar un canal que no existe');

    CALL zz_registrar(p_n, 'OK', 'restricciones de llamada');
END//

-- ---------------------------------------------------------------------
-- 6. Fichas y campos pendientes (RF13, RF15, RF16)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_06(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_ll    CHAR(36) DEFAULT UUID();
    DECLARE v_ficha CHAR(36) DEFAULT UUID();
    DECLARE v_total INT;
    DECLARE v_lista VARCHAR(200);
    DECLARE v_antes DATETIME(3) DEFAULT UTC_TIMESTAMP(3) - INTERVAL 1 DAY;

    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';
    INSERT INTO llamada (id, delegacion_id) VALUES (v_ll, v_deleg);

    INSERT INTO ficha (id, llamada_id, nombre, actualizada) VALUES (v_ficha, v_ll, 'Persona de prueba', v_antes);
    SELECT total_pendientes INTO v_total FROM ficha_pendientes WHERE ficha_id = v_ficha;
    CALL zz_afirmar(v_total = 7, 'con solo el nombre deben quedar 7 campos pendientes');

    -- Cero lesionados es un dato, no un pendiente; el texto en blanco sí es pendiente.
    UPDATE ficha SET num_lesionados = 0, motivo = '   ' WHERE id = v_ficha;
    SELECT total_pendientes, campos_pendientes INTO v_total, v_lista FROM ficha_pendientes WHERE ficha_id = v_ficha;
    CALL zz_afirmar(v_total = 6, 'num_lesionados = 0 cuenta como llenado y el motivo en blanco sigue pendiente');
    CALL zz_afirmar(FIND_IN_SET('motivo', v_lista) > 0, 'el motivo en blanco debe aparecer como pendiente');
    CALL zz_afirmar(FIND_IN_SET('num_lesionados', v_lista) = 0, 'num_lesionados = 0 no debe aparecer como pendiente');
    CALL zz_afirmar(FIND_IN_SET('nombre', v_lista) = 0, 'el nombre ya está llenado y no debe aparecer');

    -- La fecha de la ficha se actualiza sola.
    UPDATE ficha SET lugar = 'Insurgentes' WHERE id = v_ficha;
    CALL zz_afirmar((SELECT actualizada FROM ficha WHERE id = v_ficha) > v_antes, 'actualizada debe cambiar al editar');

    -- una sola ficha por llamada
    CALL zz_debe_fallar(CONCAT('INSERT INTO ficha (llamada_id) VALUES (', QUOTE(v_ll), ')'),
                        1062, NULL, 'debió rechazar una segunda ficha para la misma llamada');
    CALL zz_debe_fallar(CONCAT('UPDATE ficha SET num_lesionados = -1 WHERE id = ', QUOTE(v_ficha)),
                        3819, NULL, 'debió rechazar lesionados negativos');

    DELETE FROM llamada WHERE id = v_ll;
    CALL zz_afirmar(NOT EXISTS (SELECT 1 FROM ficha WHERE id = v_ficha), 'al borrar la llamada debe borrarse su ficha');

    CALL zz_registrar(p_n, 'OK', 'fichas y campos pendientes');
END//

-- ---------------------------------------------------------------------
-- 7. Horarios de citas y cupo (RF20)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_07(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_dia   DATE DEFAULT UTC_DATE() + INTERVAL 14 DAY;
    DECLARE v_cuantos INT;
    DECLARE v_suma    INT;
    DECLARE v_primero DATETIME(3);
    DECLARE v_ultimo  DATETIME(3);

    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';

    -- Nutrición: 9:00 a 16:00 (hora de Monterrey, -06:00), 7 bloques, 2 especialistas = 14 citas al día.
    -- Los inicios quedan en UTC: 9:00 local = 15:00 UTC.
    CALL horarios_calcular(v_deleg, 'nutricion', v_dia, '-06:00');
    SELECT COUNT(*), SUM(especialistas_libres), MIN(inicio), MAX(inicio)
      INTO v_cuantos, v_suma, v_primero, v_ultimo FROM cr_horarios;
    CALL zz_afirmar(v_cuantos = 7, 'nutrición: 7 bloques');
    CALL zz_afirmar(v_suma = 14, 'nutrición: 14 citas al día');
    CALL zz_afirmar(v_primero = TIMESTAMP(v_dia, '15:00:00'), 'nutrición abre a las 9:00 locales (15:00 UTC)');
    CALL zz_afirmar(v_ultimo  = TIMESTAMP(v_dia, '21:00:00'), 'el último bloque de nutrición es a las 15:00 locales (21:00 UTC)');

    -- Psicología: 9:00 a 17:00, 8 bloques, 3 especialistas = 24 citas al día.
    CALL horarios_calcular(v_deleg, 'psicologia', v_dia, '-06:00');
    SELECT COUNT(*), SUM(especialistas_libres) INTO v_cuantos, v_suma FROM cr_horarios;
    CALL zz_afirmar(v_cuantos = 8, 'psicología: 8 bloques');
    CALL zz_afirmar(v_suma = 24, 'psicología: 24 citas al día');

    -- Capacitación no tiene horarios; una fecha pasada tampoco ofrece nada.
    CALL horarios_calcular(v_deleg, 'capacitacion', v_dia, '-06:00');
    CALL zz_afirmar((SELECT COUNT(*) FROM cr_horarios) = 0, 'capacitación sin horarios');
    CALL horarios_calcular(v_deleg, 'nutricion', UTC_DATE() - INTERVAL 2 DAY, '-06:00');
    CALL zz_afirmar((SELECT COUNT(*) FROM cr_horarios) = 0, 'no se ofrecen horas pasadas');

    -- Otra delegación sin especialistas no ofrece horarios.
    CALL horarios_calcular((SELECT id FROM delegacion WHERE nombre = 'Cruz Roja Puebla (prueba)'),
                           'nutricion', v_dia, '-06:00');
    CALL zz_afirmar((SELECT COUNT(*) FROM cr_horarios) = 0, 'una delegación sin especialistas no ofrece horarios');

    -- Una zona horaria desconocida se rechaza en lugar de dar horarios equivocados.
    CALL zz_debe_fallar(CONCAT('CALL horarios_calcular(', v_deleg, ', ''nutricion'', CURDATE(), ''Nowhere/Land'')'),
                        1644, '22023', 'debió rechazar una zona horaria desconocida');

    -- Si el servidor tiene las tablas de zonas horarias, el nombre de la zona da lo mismo que el desfase.
    IF CONVERT_TZ('2026-01-01 12:00:00', 'America/Monterrey', '+00:00') IS NOT NULL THEN
        CALL horarios_calcular(v_deleg, 'nutricion', v_dia, 'America/Monterrey');
        CALL zz_afirmar((SELECT MIN(inicio) FROM cr_horarios) = TIMESTAMP(v_dia, '15:00:00'),
                        'America/Monterrey debe dar lo mismo que -06:00');
    END IF;

    CALL zz_registrar(p_n, 'OK', 'horarios disponibles');
END//

-- ---------------------------------------------------------------------
-- 8. Citas: reglas de agendado (RF21 a RF25)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_08(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_n1 INT;
    DECLARE v_n2 INT;
    DECLARE v_p1 INT;
    DECLARE v_dia DATE DEFAULT UTC_DATE() + INTERVAL 14 DAY;
    DECLARE v_t10 DATETIME(3);          -- las 10:00 locales (-06:00), en UTC
    DECLARE v_c1 CHAR(36);
    DECLARE v_c2 CHAR(36);
    DECLARE v_folio  VARCHAR(16);
    DECLARE v_folio2 VARCHAR(16);
    DECLARE v_libres INT;

    SET v_t10 = CONVERT_TZ(TIMESTAMP(v_dia, '10:00:00'), '-06:00', '+00:00');
    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';
    SELECT MIN(id), MAX(id) INTO v_n1, v_n2 FROM especialista WHERE delegacion_id = v_deleg AND servicio = 'nutricion';
    SELECT MIN(id) INTO v_p1 FROM especialista WHERE delegacion_id = v_deleg AND servicio = 'psicologia';

    INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
    VALUES (v_n1, 'nutricion', v_t10, 'Persona de prueba', '+525512345678', 1);
    SELECT id, folio INTO v_c1, v_folio FROM cita WHERE especialista_id = v_n1 AND inicio = v_t10;
    CALL zz_afirmar(v_folio REGEXP '^CR-[0-9]{6}$', 'el folio debe tener el formato CR-000123');

    CALL horarios_calcular(v_deleg, 'nutricion', v_dia, '-06:00');
    SET v_libres = NULL;
    SELECT especialistas_libres INTO v_libres FROM cr_horarios WHERE inicio = v_t10;
    CALL zz_afirmar(v_libres = 1, 'después de una cita debe quedar 1 especialista libre a las 10:00');

    -- El mismo especialista no puede tener dos citas a la misma hora.
    CALL zz_debe_fallar(CONCAT('INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
                                VALUES (', v_n1, ', ''nutricion'', ', QUOTE(v_t10), ', ''Otra persona'', ''+525512345679'', 1)'),
                        1062, NULL, 'debió rechazar el empalme');

    -- Con el segundo especialista ocupado, el horario desaparece.
    INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
    VALUES (v_n2, 'nutricion', v_t10, 'Otra persona', '+525512345679', 1);
    SELECT id, folio INTO v_c2, v_folio2 FROM cita WHERE especialista_id = v_n2 AND inicio = v_t10;
    CALL zz_afirmar(CAST(SUBSTRING(v_folio2, 4) AS UNSIGNED) > CAST(SUBSTRING(v_folio, 4) AS UNSIGNED),
                    'los folios deben ir creciendo');
    CALL horarios_calcular(v_deleg, 'nutricion', v_dia, '-06:00');
    CALL zz_afirmar((SELECT COUNT(*) FROM cr_horarios WHERE inicio = v_t10) = 0,
                    'con los 2 especialistas ocupados el horario no debe aparecer');
    CALL zz_afirmar((SELECT COUNT(*) FROM cr_horarios) = 6, 'deben quedar 6 bloques');

    -- Cancelar libera el horario (RF24) y se puede volver a reservar.
    UPDATE cita SET estado = 'cancelada' WHERE id = v_c1;
    CALL horarios_calcular(v_deleg, 'nutricion', v_dia, '-06:00');
    SET v_libres = NULL;
    SELECT especialistas_libres INTO v_libres FROM cr_horarios WHERE inicio = v_t10;
    CALL zz_afirmar(v_libres = 1, 'una cita cancelada debe liberar el horario');
    INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
    VALUES (v_n1, 'nutricion', v_t10, 'Tercera persona', '+525512345680', 1);

    -- Una cita pospuesta también libera el horario (RF25).
    UPDATE cita SET estado = 'pospuesta' WHERE id = v_c2;
    CALL horarios_calcular(v_deleg, 'nutricion', v_dia, '-06:00');
    SET v_libres = NULL;
    SELECT especialistas_libres INTO v_libres FROM cr_horarios WHERE inicio = v_t10;
    CALL zz_afirmar(v_libres = 1, 'una cita pospuesta debe liberar el horario');

    -- sin aceptar el aviso no se confirma (RF22)
    CALL zz_debe_fallar(CONCAT('INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
                                VALUES (', v_p1, ', ''psicologia'', ', QUOTE(v_t10), ', ''Persona'', ''+525512345678'', 0)'),
                        3819, NULL, 'debió exigir aceptar el aviso');
    -- el servicio debe ser el del especialista
    CALL zz_debe_fallar(CONCAT('INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
                                VALUES (', v_n1, ', ''psicologia'', ', QUOTE(v_t10 + INTERVAL 2 HOUR), ', ''Persona'', ''+525512345678'', 1)'),
                        1452, NULL, 'debió rechazar un servicio que no es del especialista');
    -- solo bloques de hora exacta
    CALL zz_debe_fallar(CONCAT('INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
                                VALUES (', v_p1, ', ''psicologia'', ', QUOTE(v_t10 + INTERVAL 30 MINUTE), ', ''Persona'', ''+525512345678'', 1)'),
                        3819, NULL, 'debió rechazar una hora que no es en punto');
    -- teléfono inválido
    CALL zz_debe_fallar(CONCAT('INSERT INTO cita (especialista_id, servicio, inicio, nombre, telefono, aviso_aceptado)
                                VALUES (', v_p1, ', ''psicologia'', ', QUOTE(v_t10), ', ''Persona'', ''12345'', 1)'),
                        3819, NULL, 'debió rechazar un teléfono inválido');

    CALL zz_registrar(p_n, 'OK', 'reglas de citas');
END//

-- ---------------------------------------------------------------------
-- 9. Cursos, contenido y bitácora
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_09(IN p_n INT)
BEGIN
    DECLARE v_curso INT;
    DECLARE v_ip    VARCHAR(40);

    SELECT MIN(id) INTO v_curso FROM curso;
    INSERT INTO inscripcion_curso (curso_id, nombre, telefono) VALUES (v_curso, 'Persona', '+525512345678');
    -- una inscripción por teléfono y curso
    CALL zz_debe_fallar(CONCAT('INSERT INTO inscripcion_curso (curso_id, nombre, telefono)
                                VALUES (', v_curso, ', ''Persona'', ''+525512345678'')'),
                        1062, NULL, 'debió rechazar la inscripción repetida');
    CALL zz_debe_fallar('INSERT INTO producto (nombre, precio_mxn, causa, enlace_compra)
                         VALUES (''Malo'', -1, ''x'', ''https://x.invalid'')',
                        3819, NULL, 'debió rechazar un precio negativo');
    CALL zz_afirmar((SELECT COUNT(*) FROM producto WHERE activo = 1) = 4, 'deben existir los 4 productos de ejemplo');
    CALL zz_afirmar((SELECT COUNT(*) FROM tutorial WHERE activo = 1) = 2, 'deben existir los 2 tutoriales de ejemplo');

    INSERT INTO bitacora (personal_id, accion, entidad, entidad_id, detalle)
    VALUES ((SELECT id FROM personal WHERE usuario = 'operador.prueba'), 'ver_ficha', 'ficha', 'x', '{"ip":"127.0.0.1"}');
    SELECT JSON_UNQUOTE(JSON_EXTRACT(detalle, '$.ip')) INTO v_ip FROM bitacora WHERE id = LAST_INSERT_ID();
    CALL zz_afirmar(v_ip = '127.0.0.1', 'el detalle de la bitácora debe guardarse como JSON');
    CALL zz_debe_fallar('INSERT INTO bitacora (accion, detalle) VALUES (''x'', ''{mal'')',
                        3140, NULL, 'debió rechazar un JSON inválido');

    CALL zz_registrar(p_n, 'OK', 'cursos, contenido y bitácora');
END//

-- ---------------------------------------------------------------------
-- 10. Permisos del usuario de la app (03_permisos_app.sql)
--     Se revisan los permisos que MySQL tiene anotados para cruzroja_app; no hace falta
--     conectarse con esa cuenta.
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_10(IN p_n INT)
BEGIN
    DECLARE v_cuenta  VARCHAR(100) DEFAULT '''cruzroja_app''';
    DECLARE v_existe  INT;
    DECLARE v_globales INT;
    DECLARE v_otros   INT;
    DECLARE v_sobran  INT;
    DECLARE v_faltan  INT;
    DECLARE v_grant   INT;

    SELECT COUNT(*) INTO v_existe FROM information_schema.USER_PRIVILEGES
     WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta;
    IF v_existe = 0 THEN
        CALL zz_registrar(p_n, 'OMITIDA', 'el usuario cruzroja_app no existe todavía (corre 03_permisos_app.sql)');
    ELSE
        -- Qué debe tener: tabla y permiso
        DROP TEMPORARY TABLE IF EXISTS zz_esperado;
        CREATE TEMPORARY TABLE zz_esperado (
            tabla   VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
            permiso VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL
        ) ENGINE=MEMORY;
        -- lectura y escritura sin borrado
        INSERT INTO zz_esperado
        SELECT t.tabla, p.permiso
          FROM (SELECT 'delegacion' AS tabla UNION ALL SELECT 'personal' UNION ALL SELECT 'llamada'
                UNION ALL SELECT 'ficha' UNION ALL SELECT 'especialista' UNION ALL SELECT 'dispositivo'
                UNION ALL SELECT 'cita' UNION ALL SELECT 'curso' UNION ALL SELECT 'producto'
                UNION ALL SELECT 'tutorial') t
          CROSS JOIN (SELECT 'SELECT' AS permiso UNION ALL SELECT 'INSERT' UNION ALL SELECT 'UPDATE') p;
        -- solo lectura
        INSERT INTO zz_esperado
        SELECT t.tabla, 'SELECT'
          FROM (SELECT 'directorio_meta' AS tabla UNION ALL SELECT 'servicio_horario'
                UNION ALL SELECT 'aviso_privacidad' UNION ALL SELECT 'ficha_pendientes'
                UNION ALL SELECT 'consentimiento_vigente' UNION ALL SELECT 'llamada_tiempos'
                UNION ALL SELECT 'contenido_ultima_actualizacion') t;
        -- solo agregar
        INSERT INTO zz_esperado
        SELECT t.tabla, p.permiso
          FROM (SELECT 'inscripcion_curso' AS tabla UNION ALL SELECT 'consentimiento'
                UNION ALL SELECT 'bitacora') t
          CROSS JOIN (SELECT 'SELECT' AS permiso UNION ALL SELECT 'INSERT') p;

        -- Sin permisos globales (solo USAGE, que significa "puede conectarse") ni opción de dar permisos
        SELECT COUNT(*) INTO v_globales FROM information_schema.USER_PRIVILEGES
         WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta AND privilege_type <> 'USAGE';
        CALL zz_afirmar(v_globales = 0, 'cruzroja_app tiene permisos globales: corre 03_permisos_app.sql');

        -- Por base: solo EXECUTE sobre cruzroja, y nada sobre otras bases
        SELECT COUNT(*) INTO v_otros FROM information_schema.SCHEMA_PRIVILEGES
         WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta
           AND NOT (table_schema = 'cruzroja' AND privilege_type = 'EXECUTE');
        CALL zz_afirmar(v_otros = 0, 'cruzroja_app tiene permisos por base distintos de EXECUTE sobre cruzroja');
        CALL zz_afirmar((SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES
                          WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta
                            AND table_schema = 'cruzroja' AND privilege_type = 'EXECUTE') >= 1,
                        'cruzroja_app debe poder ejecutar los procedimientos de cruzroja');

        -- Sin permisos por columna
        CALL zz_afirmar((SELECT COUNT(*) FROM information_schema.COLUMN_PRIVILEGES
                          WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta) = 0,
                        'cruzroja_app tiene permisos por columna que no se esperaban');

        -- Por tabla: exactamente la lista esperada, ni una de más ni una de menos
        SELECT COUNT(*) INTO v_sobran FROM information_schema.TABLE_PRIVILEGES p
         WHERE SUBSTRING_INDEX(p.grantee, '@', 1) = v_cuenta
           AND NOT EXISTS (SELECT 1 FROM zz_esperado e
                            WHERE p.table_schema = 'cruzroja'
                              AND CONVERT(p.table_name USING utf8mb4) COLLATE utf8mb4_bin = e.tabla
                              AND CONVERT(p.privilege_type USING utf8mb4) COLLATE utf8mb4_bin = e.permiso);
        CALL zz_afirmar(v_sobran = 0, 'cruzroja_app tiene permisos de más sobre alguna tabla (¿DELETE? ¿UPDATE en la bitácora?)');

        SELECT COUNT(*) INTO v_faltan FROM zz_esperado e
         WHERE NOT EXISTS (SELECT 1 FROM information_schema.TABLE_PRIVILEGES p
                            WHERE SUBSTRING_INDEX(p.grantee, '@', 1) = v_cuenta
                              AND p.table_schema = 'cruzroja'
                              AND CONVERT(p.table_name USING utf8mb4) COLLATE utf8mb4_bin = e.tabla
                              AND CONVERT(p.privilege_type USING utf8mb4) COLLATE utf8mb4_bin = e.permiso);
        CALL zz_afirmar(v_faltan = 0, 'a cruzroja_app le falta algún permiso: corre 03_permisos_app.sql');

        -- Nada con opción de dar permisos a otros
        SELECT (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES
                 WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta AND is_grantable = 'YES')
             + (SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES
                 WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta AND is_grantable = 'YES')
             + (SELECT COUNT(*) FROM information_schema.TABLE_PRIVILEGES
                 WHERE SUBSTRING_INDEX(grantee, '@', 1) = v_cuenta AND is_grantable = 'YES')
          INTO v_grant;
        CALL zz_afirmar(v_grant = 0, 'cruzroja_app puede dar permisos a otros (WITH GRANT OPTION)');

        DROP TEMPORARY TABLE zz_esperado;
        CALL zz_registrar(p_n, 'OK', 'permisos mínimos del usuario de la app (43 permisos de tabla, EXECUTE, nada más)');
    END IF;
END//

-- ---------------------------------------------------------------------
-- 11. Contraseñas solo como hash (RNF20)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_11(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';

    -- una contraseña en texto plano no entra
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''texto.plano'', ''MiContrasena123!'', ''operador'')'),
                        3819, NULL, 'debió rechazar una contraseña en texto plano');
    -- un texto cualquiera con signo de pesos tampoco
    CALL zz_debe_fallar(CONCAT('INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
                                VALUES (', v_deleg, ', ''falso.hash'', ''$no-es-un-hash'', ''operador'')'),
                        3819, NULL, 'debió rechazar un texto que no es un hash');
    -- bcrypt y argon2id sí entran
    INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
    VALUES (v_deleg, 'con.bcrypt', CONCAT('$2b$12$', REPEAT('a', 53)), 'operador');
    INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
    VALUES (v_deleg, 'con.argon2', '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA', 'operador');

    CALL zz_registrar(p_n, 'OK', 'el campo de contraseña solo acepta hashes');
END//

-- ---------------------------------------------------------------------
-- 12. Bloqueo por intentos fallidos (RNF07)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_12(IN p_n INT)
BEGIN
    DECLARE v_id    CHAR(36);
    DECLARE v_deleg INT;
    DECLARE v_hasta DATETIME(3);
    DECLARE v_otra  DATETIME(3);
    DECLARE v_intentos INT;
    DECLARE v_bloq  DATETIME(3);
    DECLARE v_acceso DATETIME(3);
    DECLARE i INT DEFAULT 1;

    SELECT id INTO v_id FROM personal WHERE usuario = 'operador.prueba';
    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';

    -- Los primeros 4 intentos no bloquean
    WHILE i <= 4 DO
        SET v_hasta = NULL;
        CALL personal_login_fallido('operador.prueba', 5, 15, v_hasta);
        CALL zz_afirmar(v_hasta IS NULL, CONCAT('el intento ', i, ' no debe bloquear'));
        SET i = i + 1;
    END WHILE;
    CALL zz_afirmar((SELECT intentos_fallidos FROM personal WHERE id = v_id) = 4, 'deben contarse 4 intentos');

    -- El quinto bloquea 15 minutos (y el usuario se acepta en mayúsculas)
    CALL personal_login_fallido('OPERADOR.Prueba', 5, 15, v_hasta);
    CALL zz_afirmar(v_hasta IS NOT NULL, 'el quinto intento debe bloquear la cuenta');
    CALL zz_afirmar(TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(3), v_hasta) BETWEEN 898 AND 900,
                    'el bloqueo debe durar 15 minutos');

    -- Seguir intentando no alarga el bloqueo (nadie mantiene bloqueada una cuenta ajena)
    CALL personal_login_fallido('operador.prueba', 5, 60, v_otra);
    CALL zz_afirmar(v_otra = v_hasta, 'un intento durante el bloqueo no debe alargarlo');

    -- Usuario inexistente o dado de baja: no pasa nada y no revela nada
    SET v_otra = UTC_TIMESTAMP(3);
    CALL personal_login_fallido('no.existe', 5, 15, v_otra);
    CALL zz_afirmar(v_otra IS NULL, 'usuario inexistente debe devolver null');
    INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol, activo)
    VALUES (v_deleg, 'baja.prueba', '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA', 'operador', 0);
    SET v_otra = UTC_TIMESTAMP(3);
    CALL personal_login_fallido('baja.prueba', 5, 15, v_otra);
    CALL zz_afirmar(v_otra IS NULL, 'cuenta dada de baja debe devolver null');
    CALL zz_afirmar((SELECT intentos_fallidos FROM personal WHERE usuario = 'baja.prueba') = 0,
                    'una cuenta dada de baja no debe contar intentos');

    -- Venció el bloqueo: el conteo empieza de nuevo
    UPDATE personal SET bloqueado_hasta = UTC_TIMESTAMP(3) - INTERVAL 1 MINUTE WHERE id = v_id;
    SET v_hasta = UTC_TIMESTAMP(3);
    CALL personal_login_fallido('operador.prueba', 5, 15, v_hasta);
    SELECT intentos_fallidos, bloqueado_hasta INTO v_intentos, v_bloq FROM personal WHERE id = v_id;
    CALL zz_afirmar(v_intentos = 1 AND v_bloq IS NULL AND v_hasta IS NULL,
                    'al vencer el bloqueo el conteo debe empezar en 1 y la cuenta quedar libre');

    -- Un acceso correcto limpia todo
    CALL personal_login_fallido('operador.prueba', 5, 15, v_hasta);
    CALL personal_login_exitoso(v_id);
    SELECT intentos_fallidos, bloqueado_hasta, ultimo_acceso INTO v_intentos, v_bloq, v_acceso
      FROM personal WHERE id = v_id;
    CALL zz_afirmar(v_intentos = 0 AND v_bloq IS NULL AND v_acceso IS NOT NULL,
                    'un acceso correcto debe reiniciar los intentos');

    CALL zz_registrar(p_n, 'OK', 'bloqueo al quinto intento fallido');
END//

-- ---------------------------------------------------------------------
-- 13. Consentimiento con fecha y versión del aviso (RNF08)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_13(IN p_n INT)
BEGIN
    DECLARE v_disp CHAR(36) DEFAULT UUID();

    INSERT INTO dispositivo (id) VALUES (v_disp);
    CALL zz_afirmar(tiene_consentimiento(v_disp, 'ubicacion') = 0, 'sin registro no hay consentimiento');

    -- Acepta la ubicación hace una hora
    INSERT INTO consentimiento (dispositivo_id, permiso, aceptado, version_aviso, registrado_en)
    VALUES (v_disp, 'ubicacion', 1, '1.0-prueba', UTC_TIMESTAMP(3) - INTERVAL 1 HOUR);
    CALL zz_afirmar(tiene_consentimiento(v_disp, 'ubicacion') = 1, 'debe haber consentimiento de ubicación');
    CALL zz_afirmar(tiene_consentimiento(v_disp, 'camara') = 0, 'los permisos son independientes');

    -- Después lo retira: manda el registro más reciente
    INSERT INTO consentimiento (dispositivo_id, permiso, aceptado, version_aviso, registrado_en)
    VALUES (v_disp, 'ubicacion', 0, '1.0-prueba', UTC_TIMESTAMP(3));
    CALL zz_afirmar(tiene_consentimiento(v_disp, 'ubicacion') = 0, 'el último registro debe mandar');
    CALL zz_afirmar((SELECT COUNT(*) FROM consentimiento WHERE dispositivo_id = v_disp) = 2,
                    'el historial de consentimientos se conserva');
    CALL zz_afirmar((SELECT version_aviso FROM consentimiento_vigente
                      WHERE dispositivo_id = v_disp AND permiso = 'ubicacion') = '1.0-prueba',
                    'el registro debe guardar la versión del aviso');

    -- la versión del aviso debe existir
    CALL zz_debe_fallar(CONCAT('INSERT INTO consentimiento (dispositivo_id, permiso, aceptado, version_aviso)
                                VALUES (', QUOTE(v_disp), ', ''camara'', 1, ''0.0-no-existe'')'),
                        1452, NULL, 'debió rechazar una versión de aviso inexistente');
    -- el permiso solo puede ser uno de los cuatro
    CALL zz_debe_fallar(CONCAT('INSERT INTO consentimiento (dispositivo_id, permiso, aceptado, version_aviso)
                                VALUES (', QUOTE(v_disp), ', ''contactos'', 1, ''1.0-prueba'')'),
                        1265, NULL, 'debió rechazar un permiso que no existe');

    CALL zz_registrar(p_n, 'OK', 'consentimiento con fecha y versión del aviso');
END//

-- ---------------------------------------------------------------------
-- 14. Tiempo de entrega de los datos al operador (RNF02, RNF18)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_14(IN p_n INT)
BEGIN
    DECLARE v_deleg INT;
    DECLARE v_a CHAR(36) DEFAULT UUID();
    DECLARE v_b CHAR(36) DEFAULT UUID();
    DECLARE v_t DATETIME(3) DEFAULT UTC_TIMESTAMP(3);

    SELECT id INTO v_deleg FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';
    INSERT INTO llamada (id, delegacion_id, conectada_en, datos_recibidos_en)
    VALUES (v_a, v_deleg, v_t, v_t + INTERVAL 3 SECOND);
    INSERT INTO llamada (id, delegacion_id, conectada_en, datos_recibidos_en)
    VALUES (v_b, v_deleg, v_t, v_t + INTERVAL 6 SECOND);

    CALL zz_afirmar((SELECT segundos_hasta_datos FROM llamada_tiempos WHERE llamada_id = v_a) = 3.000, 'debe calcular 3 segundos');
    CALL zz_afirmar((SELECT cumple_5s FROM llamada_tiempos WHERE llamada_id = v_a) = 1, '3 s cumple la meta de 5 s');
    CALL zz_afirmar((SELECT cumple_5s FROM llamada_tiempos WHERE llamada_id = v_b) = 0, '6 s no cumple la meta');

    -- los datos no pueden llegar antes de que conecte la llamada
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, conectada_en, datos_recibidos_en)
                                VALUES (', v_deleg, ', ', QUOTE(v_t), ', ', QUOTE(v_t - INTERVAL 1 SECOND), ')'),
                        3819, NULL, 'debió rechazar datos recibidos antes de conectar');
    -- ni sin haber conectado
    CALL zz_debe_fallar(CONCAT('INSERT INTO llamada (delegacion_id, datos_recibidos_en) VALUES (', v_deleg, ', ', QUOTE(v_t), ')'),
                        3819, NULL, 'debió rechazar datos recibidos sin conexión');

    CALL zz_registrar(p_n, 'OK', 'tiempos de entrega de datos');
END//

-- ---------------------------------------------------------------------
-- 15. La bitácora no se puede modificar ni borrar (RNF21)
--     Estas pruebas corren con la cuenta de administración: el disparador
--     protege aunque alguien le dé permisos a la cuenta de la app por error.
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_15(IN p_n INT)
BEGIN
    DECLARE v_id BIGINT UNSIGNED;

    INSERT INTO bitacora (accion) VALUES ('prueba_inmutable');
    SET v_id = LAST_INSERT_ID();

    CALL zz_debe_fallar(CONCAT('UPDATE bitacora SET accion = ''x'' WHERE id = ', v_id),
                        1644, '45000', 'debió rechazar UPDATE en la bitácora');
    CALL zz_debe_fallar(CONCAT('UPDATE bitacora SET personal_id = NULL WHERE id = ', v_id),
                        1644, '45000', 'debió rechazar UPDATE de otra columna en la bitácora');
    CALL zz_debe_fallar(CONCAT('DELETE FROM bitacora WHERE id = ', v_id),
                        1644, '45000', 'debió rechazar DELETE en la bitácora');
    CALL zz_afirmar((SELECT accion FROM bitacora WHERE id = v_id) = 'prueba_inmutable', 'el registro debe seguir ahí intacto');

    CALL zz_registrar(p_n, 'OK', 'bitácora de solo agregar');
END//

-- ---------------------------------------------------------------------
-- 16. La app sabe cuándo cambió el contenido (RNF14)
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_16(IN p_n INT)
BEGIN
    DECLARE v_id    INT;
    DECLARE v_antes DATETIME(3) DEFAULT UTC_TIMESTAMP(3) - INTERVAL 1 DAY;

    INSERT INTO producto (nombre, precio_mxn, causa, enlace_compra, actualizado_en)
    VALUES ('Producto fechado', 99, 'x', 'https://x.invalid', v_antes);
    SET v_id = LAST_INSERT_ID();
    CALL zz_afirmar((SELECT actualizado_en FROM producto WHERE id = v_id) = v_antes, 'fecha inicial');

    UPDATE producto SET precio_mxn = 120 WHERE id = v_id;
    CALL zz_afirmar((SELECT actualizado_en FROM producto WHERE id = v_id) > v_antes, 'un cambio debe actualizar la fecha');

    UPDATE producto SET activo = 0 WHERE id = v_id;   -- una baja también cuenta como cambio
    CALL zz_afirmar((SELECT actualizado_en FROM contenido_ultima_actualizacion WHERE tipo = 'producto')
                      >= UTC_TIMESTAMP(3) - INTERVAL 10 SECOND,
                    'la vista debe reflejar el último cambio');
    CALL zz_afirmar((SELECT COUNT(*) FROM contenido_ultima_actualizacion) = 4, 'la vista cubre 4 tipos de contenido');

    CALL zz_registrar(p_n, 'OK', 'fechas de actualización del contenido');
END//

-- ---------------------------------------------------------------------
-- 17. Configuración del servidor
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_prueba_17(IN p_n INT)
BEGIN
    -- En modo estricto un dato inválido (texto demasiado largo, un valor que no está en un
    -- ENUM, un número fuera de rango) da error; sin él, MySQL lo corta o lo cambia en silencio.
    CALL zz_afirmar(@@session.sql_mode LIKE '%STRICT_TRANS_TABLES%' OR @@session.sql_mode LIKE '%STRICT_ALL_TABLES%',
                    'el modo SQL no es estricto: activa STRICT_TRANS_TABLES en sql_mode');
    CALL zz_registrar(p_n, 'OK', CONCAT('modo SQL estricto; servidor ', VERSION()));
END//

-- ---------------------------------------------------------------------
-- Ejecutor: corre las pruebas una por una, cada una con su propio ROLLBACK
-- ---------------------------------------------------------------------
CREATE PROCEDURE zz_correr_pruebas()
BEGIN
    DECLARE v_n       INT DEFAULT 1;
    DECLARE v_total   INT DEFAULT 17;
    DECLARE v_falla   TINYINT DEFAULT 0;
    DECLARE v_msg     VARCHAR(500) DEFAULT '';
    DECLARE v_errno   INT DEFAULT 0;
    DECLARE v_hash    VARCHAR(100) DEFAULT '$argon2id$v=19$m=19456,t=2,p=1$c2FsdGRlcHJ1ZWJh$aGFzaGRlcHJ1ZWJh';
    DECLARE v_antes   BIGINT;
    DECLARE v_despues BIGINT;
    DECLARE v_ok      INT;
    DECLARE v_mal     INT;
    DECLARE v_omit    INT;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, 1265
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT, v_errno = MYSQL_ERRNO;
        SET v_falla = 1;
    END;

    -- Tabla de resultados: MEMORY para que ni el ROLLBACK la borre.
    DROP TEMPORARY TABLE IF EXISTS zz_resultados;
    CREATE TEMPORARY TABLE zz_resultados (
        n         INT          NOT NULL,
        resultado VARCHAR(10)  NOT NULL,
        detalle   VARCHAR(400) NOT NULL
    ) ENGINE=MEMORY;

    -- Fotografía de la base antes de empezar (para comprobar que no queda nada).
    SELECT (SELECT COUNT(*) FROM delegacion) + (SELECT COUNT(*) FROM personal) + (SELECT COUNT(*) FROM llamada)
         + (SELECT COUNT(*) FROM ficha) + (SELECT COUNT(*) FROM especialista) + (SELECT COUNT(*) FROM dispositivo)
         + (SELECT COUNT(*) FROM cita) + (SELECT COUNT(*) FROM curso) + (SELECT COUNT(*) FROM inscripcion_curso)
         + (SELECT COUNT(*) FROM producto) + (SELECT COUNT(*) FROM tutorial) + (SELECT COUNT(*) FROM consentimiento)
         + (SELECT COUNT(*) FROM bitacora) + (SELECT version FROM directorio_meta WHERE id = 1)
      INTO v_antes;

    START TRANSACTION;

    -- Cuentas de ejemplo que usan varias pruebas
    INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol)
    SELECT id, 'operador.prueba', v_hash, 'operador' FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';
    INSERT INTO personal (delegacion_id, usuario, hash_contrasena, rol, permiso_contenido)
    SELECT id, 'admin.prueba', v_hash, 'administrativo', 1 FROM delegacion WHERE nombre = 'Cruz Roja Centro (prueba)';
    IF v_falla = 1 OR (SELECT COUNT(*) FROM personal WHERE usuario IN ('operador.prueba', 'admin.prueba')) <> 2 THEN
        INSERT INTO zz_resultados VALUES (0, 'FALLÓ',
            LEFT(CONCAT('no se pudieron crear las cuentas de ejemplo (¿corriste 02_datos_prueba.sql?) ', v_msg), 400));
        SET v_n = v_total + 1;      -- no se corre ninguna prueba
    END IF;

    SAVEPOINT zz_base;

    WHILE v_n <= v_total DO
        SET v_falla = 0;
        SET v_msg = '';
        SET @zz_llamada = CONCAT('CALL zz_prueba_', LPAD(v_n, 2, '0'), '(', v_n, ')');
        PREPARE zz_p FROM @zz_llamada;
        IF v_falla = 0 THEN
            EXECUTE zz_p;
            DEALLOCATE PREPARE zz_p;
        END IF;
        IF v_falla = 1 THEN
            INSERT INTO zz_resultados (n, resultado, detalle)
            VALUES (v_n, 'FALLÓ', LEFT(CONCAT(v_msg, ' [error ', v_errno, ']'), 400));
        END IF;
        ROLLBACK TO SAVEPOINT zz_base;      -- cada prueba empieza desde cero
        SET v_n = v_n + 1;
    END WHILE;

    ROLLBACK;

    -- La base debe haber quedado exactamente como estaba.
    SET v_falla = 0;
    SELECT (SELECT COUNT(*) FROM delegacion) + (SELECT COUNT(*) FROM personal) + (SELECT COUNT(*) FROM llamada)
         + (SELECT COUNT(*) FROM ficha) + (SELECT COUNT(*) FROM especialista) + (SELECT COUNT(*) FROM dispositivo)
         + (SELECT COUNT(*) FROM cita) + (SELECT COUNT(*) FROM curso) + (SELECT COUNT(*) FROM inscripcion_curso)
         + (SELECT COUNT(*) FROM producto) + (SELECT COUNT(*) FROM tutorial) + (SELECT COUNT(*) FROM consentimiento)
         + (SELECT COUNT(*) FROM bitacora) + (SELECT version FROM directorio_meta WHERE id = 1)
      INTO v_despues;
    IF v_despues = v_antes THEN
        INSERT INTO zz_resultados VALUES (18, 'OK', 'las pruebas no dejaron ningún dato en la base');
    ELSE
        INSERT INTO zz_resultados VALUES (18, 'FALLÓ', 'las pruebas dejaron datos en la base (¿hay una transacción abierta?)');
    END IF;

    SELECT SUM(resultado = 'OK'), SUM(resultado = 'FALLÓ'), SUM(resultado = 'OMITIDA')
      INTO v_ok, v_mal, v_omit FROM zz_resultados;

    SELECT n AS prueba, resultado, detalle FROM zz_resultados
    UNION ALL
    SELECT 99, IF(v_mal = 0, 'TODO BIEN', 'HAY FALLAS'),
           CONCAT(v_ok, ' OK, ', v_mal, ' con falla, ', v_omit, ' omitida(s)')
    ORDER BY prueba;
END//

DELIMITER ;

CALL zz_correr_pruebas();

-- Limpieza: borra los procedimientos temporales de las pruebas.
DROP PROCEDURE IF EXISTS zz_correr_pruebas;
DROP PROCEDURE IF EXISTS zz_registrar;
DROP PROCEDURE IF EXISTS zz_afirmar;
DROP PROCEDURE IF EXISTS zz_debe_fallar;
DROP PROCEDURE IF EXISTS zz_prueba_01;
DROP PROCEDURE IF EXISTS zz_prueba_02;
DROP PROCEDURE IF EXISTS zz_prueba_03;
DROP PROCEDURE IF EXISTS zz_prueba_04;
DROP PROCEDURE IF EXISTS zz_prueba_05;
DROP PROCEDURE IF EXISTS zz_prueba_06;
DROP PROCEDURE IF EXISTS zz_prueba_07;
DROP PROCEDURE IF EXISTS zz_prueba_08;
DROP PROCEDURE IF EXISTS zz_prueba_09;
DROP PROCEDURE IF EXISTS zz_prueba_10;
DROP PROCEDURE IF EXISTS zz_prueba_11;
DROP PROCEDURE IF EXISTS zz_prueba_12;
DROP PROCEDURE IF EXISTS zz_prueba_13;
DROP PROCEDURE IF EXISTS zz_prueba_14;
DROP PROCEDURE IF EXISTS zz_prueba_15;
DROP PROCEDURE IF EXISTS zz_prueba_16;
DROP PROCEDURE IF EXISTS zz_prueba_17;
