-- =====================================================================
-- 03_permisos_app.sql  (MySQL 8.0 o superior)
-- Deja al usuario cruzroja_app (el que usa el backend) con los permisos mínimos.
--
-- En Aiven, al crear un usuario el servicio le da permisos muy amplios sobre TODO el
-- servidor (borrar y crear tablas, crear usuarios, dar permisos, etc.). Este script
-- primero se los quita todos y luego le da solo lo que necesita sobre la base cruzroja:
--   * puede leer y escribir, pero no borrar llamadas, fichas, cuentas ni citas
--     (una baja se marca con activa / activo);
--   * la bitácora y los consentimientos son de solo agregar;
--   * no puede crear ni borrar tablas, ni crear usuarios, ni dar permisos;
--   * no ve ninguna otra base de datos.
--
-- ANTES DE CORRERLO
--   El usuario cruzroja_app ya debe existir (en Aiven: pestaña Users del servicio >
--   Add service user). Su contraseña es la que Aiven te mostró; este script no la toca
--   y no escribe ninguna contraseña. Guárdala en las variables de entorno del backend,
--   nunca en el repositorio.
--
--   Si migras a la máquina virtual de la escuela, ahí el usuario no existe; créalo
--   primero con tu propia contraseña (cámbiala por una larga y aleatoria):
--       CREATE USER 'cruzroja_app'@'%' IDENTIFIED BY 'CAMBIA-ESTA-CONTRASENA';
--   y en lugar de '%' pon la dirección desde la que se conecta el backend, si la conoces
--   (en ese caso cambia también el host en las líneas de este archivo).
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--   Se puede correr cuantas veces quieras (por ejemplo, después de 99 y 01): siempre
--   deja el mismo resultado. Al final aparece la lista de permisos para que la revises.
-- =====================================================================
USE cruzroja;

-- 1. Quita lo que tenga el usuario hoy. Es un procedimiento temporal que se borra al
--    terminar. Si el usuario todavía tiene permisos globales (lo normal la primera vez
--    en Aiven), los quita todos con un solo REVOKE: permisos del servidor, permisos
--    dinámicos (ROLE_ADMIN, REPLICATION_APPLIER), la opción de dar permisos y las
--    restricciones parciales que pone Aiven. Si ya los había quitado antes, solo limpia
--    los permisos por base y por tabla que haya dejado una corrida anterior.
DROP PROCEDURE IF EXISTS zz_quitar_permisos;

DELIMITER //

CREATE PROCEDURE zz_quitar_permisos(IN p_usuario VARCHAR(32), IN p_host VARCHAR(255))
BEGIN
    DECLARE v_fin     TINYINT DEFAULT 0;
    DECLARE v_esq     VARCHAR(64);
    DECLARE v_tab     VARCHAR(64);
    DECLARE v_cuenta  VARCHAR(300) DEFAULT CONCAT(QUOTE(p_usuario), '@', QUOTE(p_host));
    DECLARE v_globales INT;
    DECLARE c_tablas CURSOR FOR
        SELECT DISTINCT table_schema, table_name
          FROM information_schema.TABLE_PRIVILEGES WHERE grantee = v_cuenta;
    DECLARE c_esquemas CURSOR FOR
        SELECT DISTINCT table_schema
          FROM information_schema.SCHEMA_PRIVILEGES WHERE grantee = v_cuenta;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    IF NOT EXISTS (SELECT 1 FROM information_schema.USER_PRIVILEGES WHERE grantee = v_cuenta) THEN
        SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'el usuario no existe: crealo primero (ver el inicio de este archivo)';
    END IF;

    -- Permisos globales (o con opción de dar permisos)
    SELECT COUNT(*) INTO v_globales
      FROM information_schema.USER_PRIVILEGES
     WHERE grantee = v_cuenta AND (privilege_type <> 'USAGE' OR is_grantable = 'YES');
    IF v_globales > 0 THEN
        SET @zz_sql = CONCAT('REVOKE ALL PRIVILEGES, GRANT OPTION FROM ', v_cuenta);
        PREPARE zz_s FROM @zz_sql;
        EXECUTE zz_s;
        DEALLOCATE PREPARE zz_s;
    END IF;

    -- Permisos por tabla de una corrida anterior (incluso de tablas ya borradas)
    OPEN c_tablas;
    bucle_tablas: LOOP
        FETCH c_tablas INTO v_esq, v_tab;
        IF v_fin = 1 THEN LEAVE bucle_tablas; END IF;
        SET @zz_sql = CONCAT('REVOKE ALL PRIVILEGES ON `', REPLACE(v_esq, '`', '``'), '`.`',
                             REPLACE(v_tab, '`', '``'), '` FROM ', v_cuenta);
        PREPARE zz_s FROM @zz_sql;
        EXECUTE zz_s;
        DEALLOCATE PREPARE zz_s;
    END LOOP;
    CLOSE c_tablas;

    -- Permisos por base de una corrida anterior
    SET v_fin = 0;
    OPEN c_esquemas;
    bucle_esquemas: LOOP
        FETCH c_esquemas INTO v_esq;
        IF v_fin = 1 THEN LEAVE bucle_esquemas; END IF;
        SET @zz_sql = CONCAT('REVOKE ALL PRIVILEGES ON `', REPLACE(v_esq, '`', '``'), '`.* FROM ', v_cuenta);
        PREPARE zz_s FROM @zz_sql;
        EXECUTE zz_s;
        DEALLOCATE PREPARE zz_s;
    END LOOP;
    CLOSE c_esquemas;
END//

DELIMITER ;

CALL zz_quitar_permisos('cruzroja_app', '%');
DROP PROCEDURE zz_quitar_permisos;

-- 2. Lectura y escritura sin borrado.
GRANT SELECT, INSERT, UPDATE ON cruzroja.delegacion   TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.personal     TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.llamada      TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.ficha        TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.especialista TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.dispositivo  TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.cita         TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.curso        TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.producto     TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT, UPDATE ON cruzroja.tutorial     TO 'cruzroja_app'@'%';

-- 3. Solo lectura. Los avisos de privacidad nuevos los agrega la cuenta de administración.
--    (Las vistas y los disparadores trabajan con los permisos de quien creó el esquema,
--    por eso la app no necesita permisos sobre directorio_meta ni cita_folio_seq.)
GRANT SELECT ON cruzroja.directorio_meta                TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.servicio_horario               TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.aviso_privacidad               TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.ficha_pendientes               TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.consentimiento_vigente         TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.llamada_tiempos                TO 'cruzroja_app'@'%';
GRANT SELECT ON cruzroja.contenido_ultima_actualizacion TO 'cruzroja_app'@'%';

-- 4. Se crean y se leen; no se editan ni se borran. Si el usuario cambia de opinión
--    sobre un permiso, se agrega un registro nuevo. La bitácora es de solo agregar:
--    sin UPDATE ni DELETE nadie puede borrar su rastro aunque robe la conexión del backend.
GRANT SELECT, INSERT ON cruzroja.inscripcion_curso TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT ON cruzroja.consentimiento    TO 'cruzroja_app'@'%';
GRANT SELECT, INSERT ON cruzroja.bitacora          TO 'cruzroja_app'@'%';

-- 5. Puede llamar las funciones y procedimientos de la base (CALL horarios_disponibles(...),
--    CALL personal_login_fallido(...), etc.). No puede crearlos ni cambiarlos.
GRANT EXECUTE ON cruzroja.* TO 'cruzroja_app'@'%';

-- 6. Opcional: obligar a que cruzroja_app solo se conecte con TLS. Aiven ya exige TLS a
--    todos; en la máquina virtual hay que configurar los certificados del servidor
--    antes de activar esto (quita los dos guiones de la línea de abajo).
-- ALTER USER 'cruzroja_app'@'%' REQUIRE SSL;

-- 7. Revisa el resultado: debe aparecer GRANT USAGE ON *.* (sin permisos globales) y
--    solo permisos sobre `cruzroja`.
SHOW GRANTS FOR 'cruzroja_app'@'%';
