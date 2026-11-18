-- =====================================================================
-- 11_cursos_demo.sql  (MySQL 8.0 o superior)   OPCIONAL
-- SOLO PARA DESARROLLO Y PRUEBAS. Cursos ficticios para mostrar Capacitación
-- (HU14) en la app: tres con lugares y uno lleno, para ver los dos casos.
--
-- El 02 solo trae un curso. Este archivo agrega los que usa la demostración.
-- Se puede repetir: no duplica cursos (los reconoce por su título) y, si un
-- curso de estos ya pasó, lo mueve otra vez a los próximos días.
-- Córrelo con avnadmin o con tu usuario dev, después del 01 y del 02.
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

START TRANSACTION;

-- Título, descripción, en cuántos días es, a qué hora (UTC) y cupo.
-- 16:00 UTC = 10:00 en Monterrey.
DROP TEMPORARY TABLE IF EXISTS zz_cursos_demo;
CREATE TEMPORARY TABLE zz_cursos_demo (
    titulo      VARCHAR(200) NOT NULL,
    descripcion TEXT         NOT NULL,
    dias        INT          NOT NULL,
    hora_utc    TIME         NOT NULL,
    cupo        INT          NOT NULL
);
INSERT INTO zz_cursos_demo VALUES
    ('RCP para adultos (prueba)',
     'Reanimación cardiopulmonar paso a paso y uso del desfibrilador (DEA).', 6, '15:00:00', 15),
    ('Primeros auxilios pediátricos (prueba)',
     'Atragantamiento, fiebre, caídas y RCP en bebés y niños.', 9, '22:00:00', 12),
    ('Prevención de accidentes en el hogar (prueba)',
     'Identificar riesgos en casa y armar un botiquín básico.', 12, '00:00:00', 40),
    ('Control de hemorragias (prueba, lleno)',
     'Presión directa, vendaje y torniquete. Curso de ejemplo sin lugares.', 4, '16:00:00', 1);

-- Alta de los que falten, en la delegación de Monterrey de los datos de prueba.
INSERT INTO curso (delegacion_id, titulo, descripcion, inicio, cupo)
SELECT d.id, z.titulo, z.descripcion, TIMESTAMP(UTC_DATE() + INTERVAL z.dias DAY, z.hora_utc), z.cupo
  FROM zz_cursos_demo z
  JOIN delegacion d ON d.nombre = 'Cruz Roja Monterrey (prueba)'
 WHERE NOT EXISTS (SELECT 1 FROM curso c WHERE c.titulo = z.titulo);

-- Los que ya existían pero ya pasaron vuelven a quedar como próximos.
UPDATE curso c
  JOIN zz_cursos_demo z ON z.titulo = c.titulo
   SET c.inicio = TIMESTAMP(UTC_DATE() + INTERVAL z.dias DAY, z.hora_utc), c.activo = 1
 WHERE c.inicio <= UTC_TIMESTAMP(3);

-- El curso "lleno" ocupa su único lugar con una persona ficticia.
INSERT INTO inscripcion_curso (curso_id, nombre, telefono)
SELECT c.id, 'Persona de prueba', '+520000000001'
  FROM curso c
 WHERE c.titulo = 'Control de hemorragias (prueba, lleno)'
   AND NOT EXISTS (SELECT 1 FROM inscripcion_curso i WHERE i.curso_id = c.id);

DROP TEMPORARY TABLE zz_cursos_demo;

COMMIT;

-- Revisa el resultado: próximos cursos con sus lugares.
SELECT c.id, c.titulo, c.inicio, c.cupo,
       (SELECT COUNT(*) FROM inscripcion_curso i WHERE i.curso_id = c.id) AS inscritos
  FROM curso c
 WHERE c.activo = 1 AND c.inicio > UTC_TIMESTAMP(3)
 ORDER BY c.inicio;
