-- =====================================================================
-- 02_datos_prueba.sql  (MySQL 8.0 o superior)
-- SOLO PARA DESARROLLO Y PRUEBAS. Nombres y teléfonos ficticios: no los
-- cargues en una base real. Las coordenadas son aproximadas, del centro de
-- cada ciudad.
--
-- CÓMO CORRERLO (MySQL Workbench): File > Open SQL Script... > este archivo >
-- rayo amarillo solo (Execute all). Se corre una sola vez, después de 01_esquema.sql.
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

START TRANSACTION;

INSERT INTO delegacion (nombre, telefono_cecom, latitud, longitud, estado) VALUES
    ('Cruz Roja Centro (prueba)',      '+525500000001', 19.432600,  -99.133200, 'Ciudad de México'),
    ('Cruz Roja Monterrey (prueba)',   '+528100000002', 25.686600, -100.316100, 'Nuevo León'),
    ('Cruz Roja Guadalajara (prueba)', '+523300000003', 20.659700, -103.349600, 'Jalisco'),
    ('Cruz Roja Puebla (prueba)',      '+522200000004', 19.041400,  -98.206300, 'Puebla'),
    ('Cruz Roja Mérida (prueba)',      '+529900000005', 20.967400,  -89.592600, 'Yucatán'),
    ('Cruz Roja Tijuana (prueba)',     '+526600000006', 32.514900, -117.038200, 'Baja California');

-- Especialistas como en RF20: 2 de nutrición y 3 de psicología por delegación
-- (solo en Centro y Monterrey, que bastan para probar).
INSERT INTO especialista (delegacion_id, nombre, servicio)
SELECT d.id, s.nombre, s.servicio
FROM delegacion d
CROSS JOIN (
    SELECT 'Nutrición 1 (prueba)'  AS nombre, 'nutricion'  AS servicio
    UNION ALL SELECT 'Nutrición 2 (prueba)',  'nutricion'
    UNION ALL SELECT 'Psicología 1 (prueba)', 'psicologia'
    UNION ALL SELECT 'Psicología 2 (prueba)', 'psicologia'
    UNION ALL SELECT 'Psicología 3 (prueba)', 'psicologia'
) AS s
WHERE d.nombre IN ('Cruz Roja Centro (prueba)', 'Cruz Roja Monterrey (prueba)');

-- Versión de ejemplo del aviso de privacidad. En la base real, la primera versión la
-- agrega la cuenta de administración cuando Cruz Roja apruebe el texto (RNF08).
INSERT INTO aviso_privacidad (version) VALUES ('1.0-prueba');

-- Contenido de ejemplo, tomado de los mockups. Los enlaces usan el dominio
-- reservado .invalid, que nunca resuelve.
INSERT INTO producto (nombre, precio_mxn, causa, enlace_compra) VALUES
    ('Bolsa solidaria',   150.00, 'Apoya atención prehospitalaria',          'https://tienda.ejemplo.invalid/bolsa'),
    ('Termo solidario',   220.00, 'Apoya programas de salud',                'https://tienda.ejemplo.invalid/termo'),
    ('Botiquín personal', 250.00, 'Apoya capacitación en primeros auxilios', 'https://tienda.ejemplo.invalid/botiquin'),
    ('Playera solidaria', 180.00, 'Apoya ayuda en desastres',                'https://tienda.ejemplo.invalid/playera');

INSERT INTO tutorial (tema, titulo, descripcion, duracion_seg, video_url, orden) VALUES
    ('Primeros auxilios', 'Primeros auxilios', 'Aprende a brindar ayuda inmediata',      275, 'https://videos.ejemplo.invalid/primeros-auxilios', 1),
    ('RCP',               'RCP',               'Reanimación cardiopulmonar paso a paso', 380, 'https://videos.ejemplo.invalid/rcp',               2);

INSERT INTO curso (delegacion_id, titulo, descripcion, inicio, cupo)
SELECT d.id, 'Primeros auxilios básicos (prueba)', 'Curso de ejemplo',
       TIMESTAMP(UTC_DATE() + INTERVAL 30 DAY, '10:00:00'), 20
FROM delegacion d
WHERE d.nombre = 'Cruz Roja Monterrey (prueba)';

COMMIT;
