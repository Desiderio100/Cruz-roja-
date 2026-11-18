-- =====================================================================
-- 12_cursos_y_centros.sql  (MySQL 8.0.16 o superior)
-- HU11 y HU14: los datos que la app traía fijos ahora viven en la base.
--   1. curso: columnas duracion y costo_mxn.
--   2. delegacion: columnas direccion y referencia ("Sobre Av. …").
--   3. Los 8 centros de la zona metropolitana de Monterrey (antes en centros.json, dentro de
--      la app) como delegaciones. Desde aquí, la app toma todos los centros de la base.
--   4. Los 4 cursos de Capacitación (antes Curso.ejemplos en la app), con sus lugares ocupados.
--      "RCP para adultos" queda lleno (15 de 15) para probar que no deja inscribirse.
-- Necesita 01_esquema.sql ya corrido.
--
-- CÓMO CORRERLO (necesita una cuenta que pueda cambiar tablas: avnadmin o tu usuario dev):
--   • Desde backend/:  npm run db:correr -- ../db/12_cursos_y_centros.sql
--   • O en MySQL Workbench / DBeaver: abre este archivo y ejecuta todo el script.
--   NO hace falta correr 03_permisos_app.sql otra vez: cruzroja_app ya puede leer curso y
--   delegacion completas (los permisos son por tabla, incluyen las columnas nuevas).
--
-- Se puede correr varias veces: las columnas, centros y cursos que ya existan no se tocan.
-- Los teléfonos, coordenadas, fechas e inscritos son DATOS DE PRUEBA (los mismos que tenía la app).
-- OJO: Emergencia elige en el servidor la delegación activa más cercana; con estos centros, una
-- llamada desde Monterrey le llega al centro más cercano y no a "Cruz Roja Monterrey (prueba)".
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1. curso: duración y costo
-- ---------------------------------------------------------------------
SET @zz_ya := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE table_schema = 'cruzroja' AND table_name = 'curso' AND column_name = 'duracion');
SET @zz_sql := IF(@zz_ya > 0, 'DO 0', '
ALTER TABLE curso
    ADD COLUMN duracion  VARCHAR(40)   NULL AFTER inicio,
    ADD COLUMN costo_mxn DECIMAL(10,2) NULL AFTER cupo,
    ADD CONSTRAINT curso_costo CHECK (costo_mxn IS NULL OR costo_mxn >= 0)');
PREPARE zz_s FROM @zz_sql;
EXECUTE zz_s;
DEALLOCATE PREPARE zz_s;

-- ---------------------------------------------------------------------
-- 2. delegacion: dirección y referencia
-- ---------------------------------------------------------------------
SET @zz_ya := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE table_schema = 'cruzroja' AND table_name = 'delegacion' AND column_name = 'direccion');
SET @zz_sql := IF(@zz_ya > 0, 'DO 0', '
ALTER TABLE delegacion
    ADD COLUMN direccion  VARCHAR(200) NULL AFTER estado,
    ADD COLUMN referencia VARCHAR(200) NULL AFTER direccion');
PREPARE zz_s FROM @zz_sql;
EXECUTE zz_s;
DEALLOCATE PREPARE zz_s;

-- ---------------------------------------------------------------------
-- 3. Centros de la zona metropolitana de Monterrey (los que tenía centros.json)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado, direccion, referencia) VALUES
    ('Cruz Roja Monterrey Centro', '+528112345600', 25.671400, -100.309000, 'Nuevo León', 'Centro de Monterrey, N.L.',      'Sobre Av. Constitución, a dos cuadras de la Macroplaza'),
    ('Cruz Roja Monterrey Sur',    '+528112345601', 25.637000, -100.285000, 'Nuevo León', 'Zona Tec / Contry, N.L.',        'Sobre Av. Eugenio Garza Sada, pasando el Tec'),
    ('Cruz Roja San Nicolás',      '+528112345602', 25.741700, -100.302000, 'Nuevo León', 'San Nicolás de los Garza, N.L.', 'Sobre Av. Universidad, cerca de Av. Juárez'),
    ('Cruz Roja Guadalupe',        '+528112345603', 25.676700, -100.256500, 'Nuevo León', 'Guadalupe, N.L.',                'Sobre Av. Benito Juárez, frente a la plaza principal'),
    ('Cruz Roja San Pedro',        '+528112345604', 25.657300, -100.402300, 'Nuevo León', 'San Pedro Garza García, N.L.',   'Sobre Av. Vasconcelos, cerca de Calzada San Pedro'),
    ('Cruz Roja Santa Catarina',   '+528112345605', 25.673300, -100.458000, 'Nuevo León', 'Santa Catarina, N.L.',           'Sobre Av. Manuel Ordóñez, cerca del centro'),
    ('Cruz Roja Apodaca',          '+528112345606', 25.781700, -100.188000, 'Nuevo León', 'Apodaca, N.L.',                  'Sobre Av. Miguel Alemán, a la altura del centro de Apodaca'),
    ('Cruz Roja Escobedo',         '+528112345607', 25.799000, -100.324000, 'Nuevo León', 'General Escobedo, N.L.',         'Sobre Av. Raúl Salinas, cerca de la presidencia municipal');

-- ---------------------------------------------------------------------
-- 4. Cursos de Capacitación. Las fechas son a partir de hoy, en hora de Monterrey
--    (UTC-6); se guardan en UTC como el resto de la base.
-- ---------------------------------------------------------------------
INSERT INTO curso (delegacion_id, titulo, descripcion, inicio, duracion, cupo, costo_mxn)
SELECT d.id, n.titulo, n.descripcion,
       TIMESTAMP(UTC_DATE() + INTERVAL n.dias DAY, n.hora) + INTERVAL 6 HOUR,
       n.duracion, n.cupo, n.costo
  FROM (
        SELECT 'Primeros auxilios básicos' AS titulo,
               'Valorar a una persona lesionada, controlar hemorragias, atender quemaduras y actuar mientras llega la ambulancia.' AS descripcion,
               4 AS dias, '10:00:00' AS hora, '4 horas' AS duracion, 20 AS cupo, 350.00 AS costo,
               'Cruz Roja Monterrey Centro' AS sede
        UNION ALL SELECT 'RCP para adultos',
               'Reanimación cardiopulmonar paso a paso y uso del desfibrilador (DEA).',
               6, '09:00:00', '3 horas', 15, 300.00, 'Cruz Roja San Nicolás'
        UNION ALL SELECT 'Primeros auxilios pediátricos',
               'Atragantamiento, fiebre, caídas y RCP en bebés y niños.',
               9, '16:00:00', '3 horas', 12, 300.00, 'Cruz Roja San Pedro'
        UNION ALL SELECT 'Prevención de accidentes en el hogar',
               'Identificar riesgos en casa y armar un botiquín básico.',
               12, '18:00:00', '1 hora 30 min', 40, 0.00, 'Cruz Roja Guadalupe'
       ) AS n
  JOIN delegacion d ON d.nombre = n.sede
 WHERE NOT EXISTS (SELECT 1 FROM curso c WHERE c.titulo = n.titulo);

-- Lugares ya ocupados (inscripciones de prueba), solo en los cursos que aún no tienen ninguna.
INSERT IGNORE INTO inscripcion_curso (curso_id, nombre, telefono)
WITH RECURSIVE numeros (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM numeros WHERE i < 40
)
SELECT c.id, CONCAT('Persona de prueba ', numeros.i), CONCAT('81000000', LPAD(numeros.i, 2, '0'))
  FROM (
        SELECT 'Primeros auxilios básicos' AS titulo, 12 AS ocupados
        UNION ALL SELECT 'RCP para adultos', 15
        UNION ALL SELECT 'Primeros auxilios pediátricos', 11
        UNION ALL SELECT 'Prevención de accidentes en el hogar', 15
       ) AS o
  JOIN curso c ON c.titulo = o.titulo
  JOIN numeros ON numeros.i <= o.ocupados
 WHERE NOT EXISTS (SELECT 1 FROM inscripcion_curso x WHERE x.curso_id = c.id);

-- Revisa el resultado: los cursos con sus lugares y las delegaciones activas.
SELECT c.id, c.titulo, d.nombre AS sede, c.inicio AS inicio_utc, c.duracion, c.costo_mxn,
       c.cupo, COUNT(i.id) AS inscritos
  FROM curso c
  JOIN delegacion d ON d.id = c.delegacion_id
  LEFT JOIN inscripcion_curso i ON i.curso_id = c.id
 WHERE c.activo = 1
 GROUP BY c.id
 ORDER BY c.inicio;

SELECT id, nombre, telefono_cecom, direccion FROM delegacion WHERE activa = 1 ORDER BY id;
