-- =====================================================================
-- 05_usuarios_desarrollo.sql  (MySQL 8.0 o superior)
-- Deja a los compañeros del equipo con permisos de DESARROLLO sobre la base cruzroja:
-- pueden ver, editar y borrar datos, y crear, modificar y borrar TABLAS e ÍNDICES.
--
-- NO pueden (a propósito):
--   * crear, cambiar ni borrar disparadores, procedimientos, funciones ni vistas
--     (esas piezas guardan el nombre de quien las crea, y si esa persona se borra
--     después, dejan de funcionar; ese tipo de cambio lo hace avnadmin con el 01);
--   * crear usuarios ni dar permisos a otros;
--   * ver ni tocar otras bases del servidor.
-- Ojo: con permiso de borrar tablas también pueden vaciarlas (TRUNCATE, incluida la
-- bitácora) y borrar la base completa (DROP DATABASE). MySQL no permite quitar solo eso.
-- Por eso conviene que el equipo acuerde nunca hacerlo, y que los scripts 01 a 03 sean
-- siempre la versión buena de la base.
--
-- ANTES DE CORRERLO
--   1. En Aiven (pestaña Users del servicio > Add service user) crea un usuario por
--      persona, por ejemplo dev_ana, dev_luis. Aiven te muestra la contraseña de cada uno.
--   2. Escribe abajo los nombres, separados por comas, en la línea que dice
--      SET @zz_usuarios. Es la única línea que se edita.
--   3. Corre el archivo conectado como avnadmin.
--   No uses los nombres avnadmin ni cruzroja_app: este script los rechaza.
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--   Se puede repetir las veces que quieras, por ejemplo al sumar a alguien más.
--   Al final aparece, por cada persona, la lista de sus permisos.
--
-- PARA QUITARLE EL ACCESO A ALGUIEN:  DROP USER 'dev_ana'@'%';
-- =====================================================================
USE cruzroja;

SET @zz_usuarios = 'dev_ana,dev_luis,dev_pedro';      -- <== EDITA ESTA LÍNEA

DROP PROCEDURE IF EXISTS zz_quitar_permisos;
DROP PROCEDURE IF EXISTS zz_dar_desarrollo;

DELIMITER //

-- Quita todo lo que tenga el usuario hoy (igual que en 03_permisos_app.sql).
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

    SELECT COUNT(*) INTO v_globales
      FROM information_schema.USER_PRIVILEGES
     WHERE grantee = v_cuenta AND (privilege_type <> 'USAGE' OR is_grantable = 'YES');
    IF v_globales > 0 THEN
        SET @zz_sql = CONCAT('REVOKE ALL PRIVILEGES, GRANT OPTION FROM ', v_cuenta);
        PREPARE zz_s FROM @zz_sql;
        EXECUTE zz_s;
        DEALLOCATE PREPARE zz_s;
    END IF;

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

-- Recorre la lista de nombres y deja a cada uno con permisos de desarrollo.
CREATE PROCEDURE zz_dar_desarrollo(IN p_lista VARCHAR(500), IN p_host VARCHAR(255))
BEGIN
    DECLARE v_lista  VARCHAR(500);
    DECLARE v_resto  VARCHAR(500);
    DECLARE v_nombre VARCHAR(100);
    DECLARE v_cuenta VARCHAR(300);
    DECLARE v_texto  VARCHAR(120);
    DECLARE v_total  INT DEFAULT 0;

    -- Primero se revisan todos los nombres, para no dejar a medias a nadie.
    SET v_lista = REPLACE(REPLACE(p_lista, ' ', ''), '\n', '');
    SET v_resto = v_lista;
    revisar: WHILE v_resto <> '' DO
        SET v_nombre = SUBSTRING_INDEX(v_resto, ',', 1);
        SET v_resto  = IF(LOCATE(',', v_resto) = 0, '', SUBSTRING(v_resto, LOCATE(',', v_resto) + 1));
        IF v_nombre <> '' THEN
            IF v_nombre NOT REGEXP '^[A-Za-z0-9_]{3,32}$' THEN
                SET v_texto = LEFT(CONCAT('nombre no válido (solo letras, números y _): ', v_nombre), 120);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
            END IF;
            IF LOWER(v_nombre) IN ('avnadmin', 'cruzroja_app', 'root') THEN
                SET v_texto = LEFT(CONCAT('este nombre no se puede usar aquí: ', v_nombre), 120);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM information_schema.USER_PRIVILEGES
                            WHERE grantee = CONCAT(QUOTE(v_nombre), '@', QUOTE(p_host))) THEN
                SET v_texto = LEFT(CONCAT('el usuario no existe, créalo primero en Aiven: ', v_nombre), 120);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
            END IF;
        END IF;
    END WHILE revisar;

    SET v_resto = v_lista;
    aplicar: WHILE v_resto <> '' DO
        SET v_nombre = SUBSTRING_INDEX(v_resto, ',', 1);
        SET v_resto  = IF(LOCATE(',', v_resto) = 0, '', SUBSTRING(v_resto, LOCATE(',', v_resto) + 1));
        IF v_nombre <> '' THEN
            SET v_cuenta = CONCAT(QUOTE(v_nombre), '@', QUOTE(p_host));
            CALL zz_quitar_permisos(v_nombre, p_host);
            SET @zz_sql = CONCAT('GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, REFERENCES, INDEX, ALTER, ',
                                 'CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, SHOW VIEW ',
                                 'ON cruzroja.* TO ', v_cuenta);
            PREPARE zz_s FROM @zz_sql;
            EXECUTE zz_s;
            DEALLOCATE PREPARE zz_s;
            SET v_total = v_total + 1;
        END IF;
    END WHILE aplicar;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la lista de usuarios está vacía: edita la línea SET @zz_usuarios';
    END IF;
END//

DELIMITER ;

CALL zz_dar_desarrollo(@zz_usuarios, '%');
DROP PROCEDURE zz_dar_desarrollo;
DROP PROCEDURE zz_quitar_permisos;

-- Revisa el resultado: cada persona debe tener GRANT USAGE ON *.* (sin permisos globales)
-- y una sola línea de permisos sobre `cruzroja`.*, sin WITH GRANT OPTION.
SELECT SUBSTRING_INDEX(REPLACE(grantee, '''', ''), '@', 1) AS usuario,
       GROUP_CONCAT(privilege_type ORDER BY privilege_type SEPARATOR ', ') AS permisos_sobre_cruzroja,
       MAX(is_grantable) AS puede_dar_permisos
  FROM information_schema.SCHEMA_PRIVILEGES
 WHERE table_schema = 'cruzroja'
   AND FIND_IN_SET(SUBSTRING_INDEX(REPLACE(grantee, '''', ''), '@', 1), REPLACE(@zz_usuarios, ' ', '')) > 0
 GROUP BY grantee
 ORDER BY usuario;
