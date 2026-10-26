-- =====================================================================
-- App Cruz Roja Mexicana - Base de datos para MySQL 8.0 o superior
-- (probado en 8.0; Aiven usa 8.4)
-- 01_esquema.sql  (versión 2 para MySQL)
--
-- Basado en el documento "Diseño de backend y ciberseguridad" y en los
-- requerimientos no funcionales corregidos (RNF02, RNF07, RNF08, RNF14,
-- RNF20 y RNF21 del Análisis de Requerimientos).
--
-- CÓMO CORRERLO (MySQL Workbench):
--   1. Conéctate con el usuario administrador (en Aiven, avnadmin).
--   2. Menú File > Open SQL Script... y elige este archivo.
--   3. Pulsa el rayo amarillo solo (Execute all). Tarda unos segundos.
-- Se corre UNA sola vez. Si algo falla a la mitad, corre
-- 99_borrar_todo_SOLO_DESARROLLO.sql y vuelve a empezar.
--
-- DIFERENCIAS CON LA VERSIÓN DE POSTGRESQL (el diseño es el mismo):
--   * Las fechas son DATETIME(3) y siempre en UTC (el backend debe leerlas
--     y escribirlas como UTC y convertir a hora local al mostrarlas).
--   * Los identificadores uuid son CHAR(36) con un UUID versión 4 aleatorio.
--   * No hay índices parciales ni secuencias: se simulan con columnas
--     generadas y una tabla auxiliar (ver cita).
--   * Los disparadores de MySQL son por fila: una instrucción que cambie N
--     delegaciones sube la versión del directorio N veces (solo importa que cambie).
--   * Las funciones que modifican datos son procedimientos (CALL ...).
--   * La bitácora se protege con permisos y con disparadores. TRUNCATE no
--     activa disparadores, pero exige el permiso DROP, que la app no tiene.
--   * Las rutinas y disparadores se crean con DEFINER = el usuario que corre
--     este script. Si migras la base a otro servidor, ese usuario debe existir
--     allá o hay que quitar el DEFINER del volcado (ver el PDF de diseño).
-- =====================================================================

-- Si la base ya existe (por ejemplo, la creaste en Aiven), solo se ajusta su juego de caracteres.
CREATE DATABASE IF NOT EXISTS cruzroja CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE cruzroja CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cruzroja;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Directorio de delegaciones (RF17, RF18, RF34)
-- ---------------------------------------------------------------------

-- Una sola fila. Sube cuando cambia cualquier delegación (alta, cambio o baja),
-- para que la app sepa si su copia sin internet está vieja.
CREATE TABLE directorio_meta (
    id      TINYINT(1) NOT NULL DEFAULT 1,
    version INT        NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    CONSTRAINT directorio_meta_una_fila CHECK (id = 1)
) ENGINE=InnoDB;
INSERT INTO directorio_meta (id) VALUES (1);

CREATE TABLE delegacion (
    id             INT          NOT NULL AUTO_INCREMENT,
    nombre         VARCHAR(120) NOT NULL,
    telefono_cecom VARCHAR(16)  NOT NULL,
    latitud        DECIMAL(9,6) NOT NULL,
    longitud       DECIMAL(9,6) NOT NULL,
    estado         VARCHAR(60)  NOT NULL,                       -- estado de la república
    activa         TINYINT(1)   NOT NULL DEFAULT 1,             -- una baja se marca aquí, no se borra
    version        INT          NOT NULL DEFAULT 1,
    actualizada_en DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    UNIQUE KEY delegacion_nombre_uq (nombre),
    CONSTRAINT delegacion_telefono CHECK (telefono_cecom REGEXP '^[+]?[0-9]{10,15}$'),
    CONSTRAINT delegacion_latitud  CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT delegacion_longitud CHECK (longitud BETWEEN -180 AND 180)
) ENGINE=InnoDB COMMENT='Directorio de delegaciones. La app guarda una copia para el respaldo sin internet (RF18).';

DELIMITER //

CREATE TRIGGER delegacion_antes_de_actualizar BEFORE UPDATE ON delegacion
FOR EACH ROW
BEGIN
    SET NEW.version        = OLD.version + 1;
    SET NEW.actualizada_en = UTC_TIMESTAMP(3);
END//

-- Estos tres disparadores corren con los permisos de quien creó el esquema (DEFINER),
-- así el usuario de la app no necesita permiso de escritura sobre directorio_meta.
-- El WHERE id = 1 es a propósito: MySQL Workbench trae activado el "modo seguro"
-- (Safe Updates) y rechaza cualquier UPDATE sin WHERE sobre una llave.
CREATE TRIGGER delegacion_directorio_alta AFTER INSERT ON delegacion
FOR EACH ROW UPDATE directorio_meta SET version = version + 1 WHERE id = 1//

CREATE TRIGGER delegacion_directorio_cambio AFTER UPDATE ON delegacion
FOR EACH ROW UPDATE directorio_meta SET version = version + 1 WHERE id = 1//

CREATE TRIGGER delegacion_directorio_baja AFTER DELETE ON delegacion
FOR EACH ROW UPDATE directorio_meta SET version = version + 1 WHERE id = 1//

DELIMITER ;

-- ---------------------------------------------------------------------
-- Personal de Cruz Roja (RF31, RNF07, RNF20)
-- ---------------------------------------------------------------------
CREATE TABLE personal (
    id                CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    delegacion_id     INT          NOT NULL,                     -- cada cuenta pertenece a una sola delegación
    usuario           VARCHAR(60)  NOT NULL,
    hash_contrasena   VARCHAR(255) NOT NULL,                     -- hash lento (argon2id o bcrypt) calculado por el backend; nunca la contraseña
    rol               ENUM('operador', 'administrativo') NOT NULL,
    permiso_contenido TINYINT(1)   NOT NULL DEFAULT 0,           -- (propuesta) marca para editar directorio, catálogo y tutoriales
    activo            TINYINT(1)   NOT NULL DEFAULT 1,           -- una baja desactiva la cuenta, no la borra
    ultimo_acceso     DATETIME(3)  NULL,
    intentos_fallidos SMALLINT     NOT NULL DEFAULT 0,           -- RNF07: bloqueo por intentos
    bloqueado_hasta   DATETIME(3)  NULL,
    creado_en         DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    UNIQUE KEY personal_usuario_uq (usuario),
    KEY personal_delegacion_idx (delegacion_id),
    CONSTRAINT personal_delegacion_fk FOREIGN KEY (delegacion_id) REFERENCES delegacion (id),
    -- El usuario va en minúsculas (la comparación binaria distingue mayúsculas) y de 3 a 60 caracteres.
    CONSTRAINT personal_usuario_formato
        CHECK (CAST(usuario AS BINARY) = CAST(LOWER(usuario) AS BINARY) AND CHAR_LENGTH(usuario) BETWEEN 3 AND 60),
    CONSTRAINT personal_permiso_contenido_solo_administrativo
        CHECK (NOT permiso_contenido OR rol = 'administrativo'),
    CONSTRAINT personal_intentos_no_negativos CHECK (intentos_fallidos >= 0),
    -- RNF20: el campo solo acepta hashes argon2id o bcrypt, nunca una contraseña en texto plano.
    CONSTRAINT personal_hash_formato
        CHECK (hash_contrasena REGEXP '^[$](argon2id[$]v=[0-9]+[$]|2[aby][$][0-9]{2}[$])')
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Dispositivos y consentimiento (RF01 a RF03, RNF08)
-- ---------------------------------------------------------------------

-- El usuario no tiene cuenta: se identifica por dispositivo para recibir
-- recordatorios y avisos de cita (RF23, RF25) y para registrar su consentimiento.
CREATE TABLE dispositivo (
    id         CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    token_apns VARCHAR(200) NULL,                                 -- null si el usuario no aceptó notificaciones
    telefono   VARCHAR(16)  NULL,
    creado_en  DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    UNIQUE KEY dispositivo_token_uq (token_apns),
    CONSTRAINT dispositivo_telefono CHECK (telefono IS NULL OR telefono REGEXP '^[+]?[0-9]{10,15}$')
) ENGINE=InnoDB;

-- Versiones del aviso de privacidad. Cada versión nueva se agrega con la cuenta
-- de administración, después de la revisión de Cruz Roja (RNF08).
CREATE TABLE aviso_privacidad (
    version      VARCHAR(20) NOT NULL,                            -- por ejemplo: '1.0'
    publicado_en DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (version),
    CONSTRAINT aviso_version_no_vacia CHECK (CHAR_LENGTH(version) >= 1)
) ENGINE=InnoDB;

-- Cada respuesta del usuario es un registro nuevo con fecha y versión del aviso
-- (RNF08). No se edita ni se borra: si cambia de opinión, se agrega otro registro.
CREATE TABLE consentimiento (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    dispositivo_id CHAR(36)    NOT NULL,
    permiso        ENUM('ubicacion', 'microfono', 'camara', 'notificaciones') NOT NULL,
    aceptado       TINYINT(1)  NOT NULL,
    version_aviso  VARCHAR(20) NOT NULL,
    registrado_en  DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    KEY consentimiento_dispositivo_idx (dispositivo_id, permiso, registrado_en),
    CONSTRAINT consentimiento_dispositivo_fk FOREIGN KEY (dispositivo_id) REFERENCES dispositivo (id),
    CONSTRAINT consentimiento_aviso_fk FOREIGN KEY (version_aviso) REFERENCES aviso_privacidad (version)
) ENGINE=InnoDB;

-- La respuesta más reciente de cada dispositivo para cada permiso.
CREATE VIEW consentimiento_vigente AS
SELECT dispositivo_id, permiso, aceptado, version_aviso, registrado_en
FROM (
    SELECT c.*,
           ROW_NUMBER() OVER (PARTITION BY c.dispositivo_id, c.permiso
                              ORDER BY c.registrado_en DESC, c.id DESC) AS orden
    FROM consentimiento c
) t
WHERE orden = 1;

DELIMITER //

-- El backend la consulta antes de guardar la ubicación u otro dato del dispositivo.
CREATE FUNCTION tiene_consentimiento(p_dispositivo CHAR(36), p_permiso VARCHAR(20))
RETURNS TINYINT(1)
READS SQL DATA
BEGIN
    RETURN COALESCE((SELECT v.aceptado FROM consentimiento_vigente v
                      WHERE v.dispositivo_id = p_dispositivo AND v.permiso = p_permiso), 0);
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- Llamadas y fichas de emergencia (RF05 a RF16)
-- ---------------------------------------------------------------------
CREATE TABLE llamada (
    id                   CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    delegacion_id        INT          NOT NULL,
    operador_id          CHAR(36)     NULL,                       -- null hasta que un operador contesta
    dispositivo_id       CHAR(36)     NULL,                       -- null si la llamada llegó sin datos del dispositivo (RF08)
    canal                ENUM('internet', 'telefonica') NOT NULL DEFAULT 'internet',
    estado               ENUM('entrante', 'en_curso', 'finalizada', 'cortada', 'perdida') NOT NULL DEFAULT 'entrante',
    solicitante_nombre   VARCHAR(120) NULL,
    solicitante_telefono VARCHAR(16)  NULL,
    telefono_verificado  TINYINT(1)   NOT NULL DEFAULT 0,
    latitud              DECIMAL(9,6) NULL,
    longitud             DECIMAL(9,6) NULL,
    precision_m          DECIMAL(8,1) NULL,
    video_aceptado       TINYINT(1)   NOT NULL DEFAULT 0,         -- el video solo inicia si el usuario aceptó (RF09)
    inicio               DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    conectada_en         DATETIME(3)  NULL,                       -- cuando la llamada conecta con el panel (para medir RNF02)
    datos_recibidos_en   DATETIME(3)  NULL,                       -- cuando el panel recibe ubicación y datos del solicitante (RNF02)
    fin                  DATETIME(3)  NULL,
    PRIMARY KEY (id),
    KEY llamada_delegacion_inicio_idx (delegacion_id, inicio DESC),
    KEY llamada_delegacion_estado_idx (delegacion_id, estado),    -- llamadas activas de una delegación
    KEY llamada_operador_idx (operador_id),
    KEY llamada_dispositivo_idx (dispositivo_id),
    CONSTRAINT llamada_delegacion_fk  FOREIGN KEY (delegacion_id)  REFERENCES delegacion (id),
    CONSTRAINT llamada_operador_fk    FOREIGN KEY (operador_id)    REFERENCES personal (id),
    CONSTRAINT llamada_dispositivo_fk FOREIGN KEY (dispositivo_id) REFERENCES dispositivo (id),
    CONSTRAINT llamada_telefono CHECK (solicitante_telefono IS NULL OR solicitante_telefono REGEXP '^[+]?[0-9]{10,15}$'),
    CONSTRAINT llamada_latitud  CHECK (latitud  IS NULL OR latitud  BETWEEN -90  AND 90),
    CONSTRAINT llamada_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
    CONSTRAINT llamada_precision CHECK (precision_m IS NULL OR precision_m >= 0),
    CONSTRAINT llamada_ubicacion_completa CHECK ((latitud IS NULL) = (longitud IS NULL)),
    CONSTRAINT llamada_verificado_requiere_telefono CHECK (NOT telefono_verificado OR solicitante_telefono IS NOT NULL),
    CONSTRAINT llamada_fin_despues_de_inicio CHECK (fin IS NULL OR fin >= inicio),
    CONSTRAINT llamada_datos_despues_de_conectar
        CHECK (datos_recibidos_en IS NULL OR (conectada_en IS NOT NULL AND datos_recibidos_en >= conectada_en))
) ENGINE=InnoDB COMMENT='Metadatos de la llamada. No se guarda audio, video ni transcripción (propuesta, sección 5 del diseño).';

-- Tiempo de entrega de los datos al operador, para comprobar RNF02 (menos de 5 s
-- en al menos 95 % de las pruebas) y RNF18 (10 llamadas simultáneas).
CREATE VIEW llamada_tiempos AS
SELECT id AS llamada_id,
       delegacion_id,
       conectada_en,
       ROUND(TIMESTAMPDIFF(MICROSECOND, conectada_en, datos_recibidos_en) / 1000000, 3) AS segundos_hasta_datos,
       (TIMESTAMPDIFF(MICROSECOND, conectada_en, datos_recibidos_en) < 5000000)        AS cumple_5s
FROM llamada
WHERE datos_recibidos_en IS NOT NULL;

CREATE TABLE ficha (
    id               CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    llamada_id       CHAR(36)     NOT NULL,                       -- una por llamada
    nombre           VARCHAR(120) NULL,                           -- los campos siguen el orden del CECOM (RF13)
    celular          VARCHAR(20)  NULL,
    motivo           VARCHAR(500) NULL,
    num_lesionados   SMALLINT     NULL,
    lesion_principal VARCHAR(200) NULL,
    lugar            VARCHAR(300) NULL,
    ubicacion        VARCHAR(300) NULL,
    comentarios      TEXT         NULL,
    editado_por      CHAR(36)     NULL,
    actualizada      DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    UNIQUE KEY ficha_llamada_uq (llamada_id),
    CONSTRAINT ficha_llamada_fk FOREIGN KEY (llamada_id) REFERENCES llamada (id) ON DELETE CASCADE,
    CONSTRAINT ficha_editado_por_fk FOREIGN KEY (editado_por) REFERENCES personal (id),
    CONSTRAINT ficha_lesionados CHECK (num_lesionados IS NULL OR num_lesionados >= 0)
) ENGINE=InnoDB COMMENT='Un campo vacío (null o texto en blanco) es un campo pendiente (RF16); ver la vista ficha_pendientes.';

DELIMITER //

CREATE TRIGGER ficha_antes_de_actualizar BEFORE UPDATE ON ficha
FOR EACH ROW
BEGIN
    SET NEW.actualizada = UTC_TIMESTAMP(3);
END//

DELIMITER ;

-- Campos que la IA todavía no capta, para que el operador sepa qué preguntar (RF16).
-- campos_pendientes es una lista separada por comas (por ejemplo: 'motivo,lugar');
-- total_pendientes es cuántos son. Un 0 en num_lesionados es un dato, no un pendiente.
CREATE VIEW ficha_pendientes AS
SELECT f.id AS ficha_id,
       f.llamada_id,
       CONCAT_WS(',',
           CASE WHEN NULLIF(TRIM(f.nombre), '')           IS NULL THEN 'nombre'           END,
           CASE WHEN NULLIF(TRIM(f.celular), '')          IS NULL THEN 'celular'          END,
           CASE WHEN NULLIF(TRIM(f.motivo), '')           IS NULL THEN 'motivo'           END,
           CASE WHEN f.num_lesionados                     IS NULL THEN 'num_lesionados'   END,
           CASE WHEN NULLIF(TRIM(f.lesion_principal), '') IS NULL THEN 'lesion_principal' END,
           CASE WHEN NULLIF(TRIM(f.lugar), '')            IS NULL THEN 'lugar'            END,
           CASE WHEN NULLIF(TRIM(f.ubicacion), '')        IS NULL THEN 'ubicacion'        END,
           CASE WHEN NULLIF(TRIM(f.comentarios), '')      IS NULL THEN 'comentarios'      END
       ) AS campos_pendientes,
       ( (NULLIF(TRIM(f.nombre), '')           IS NULL)
       + (NULLIF(TRIM(f.celular), '')          IS NULL)
       + (NULLIF(TRIM(f.motivo), '')           IS NULL)
       + (f.num_lesionados                     IS NULL)
       + (NULLIF(TRIM(f.lesion_principal), '') IS NULL)
       + (NULLIF(TRIM(f.lugar), '')            IS NULL)
       + (NULLIF(TRIM(f.ubicacion), '')        IS NULL)
       + (NULLIF(TRIM(f.comentarios), '')      IS NULL) ) AS total_pendientes
FROM ficha f;

-- ---------------------------------------------------------------------
-- Especialistas y citas (RF19 a RF26)
-- ---------------------------------------------------------------------
CREATE TABLE especialista (
    id            INT          NOT NULL AUTO_INCREMENT,
    delegacion_id INT          NOT NULL,
    nombre        VARCHAR(120) NOT NULL,
    servicio      ENUM('nutricion', 'psicologia', 'capacitacion') NOT NULL,
    activo        TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    UNIQUE KEY especialista_id_servicio_uq (id, servicio),        -- permite que cita compruebe que el servicio coincide
    KEY especialista_delegacion_servicio_idx (delegacion_id, servicio),
    CONSTRAINT especialista_delegacion_fk FOREIGN KEY (delegacion_id) REFERENCES delegacion (id)
) ENGINE=InnoDB;

-- Horario de atención por servicio, en bloques de 1 hora (RF20).
-- Nutrición 9:00 a 16:00 (7 bloques); psicología 9:00 a 17:00 (8 bloques).
-- Capacitación no tiene horarios: se atiende con cursos (RF26).
CREATE TABLE servicio_horario (
    servicio    ENUM('nutricion', 'psicologia', 'capacitacion') NOT NULL,
    hora_inicio TINYINT UNSIGNED NOT NULL,
    hora_fin    TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (servicio),
    CONSTRAINT servicio_horario_inicio CHECK (hora_inicio BETWEEN 0 AND 23),
    CONSTRAINT servicio_horario_fin    CHECK (hora_fin    BETWEEN 1 AND 24),
    CONSTRAINT servicio_horario_orden  CHECK (hora_fin > hora_inicio)
) ENGINE=InnoDB;
INSERT INTO servicio_horario (servicio, hora_inicio, hora_fin) VALUES
    ('nutricion',  9, 16),
    ('psicologia', 9, 17);

-- MySQL no tiene secuencias: cada fila de esta tabla reparte un número de folio.
CREATE TABLE cita_folio_seq (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE cita (
    id              CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    folio           VARCHAR(16)  NOT NULL DEFAULT '',              -- lo asigna el disparador: CR-000001, CR-000002...
    especialista_id INT          NOT NULL,
    servicio        ENUM('nutricion', 'psicologia', 'capacitacion') NOT NULL,
    inicio          DATETIME(3)  NOT NULL,                         -- en UTC
    estado          ENUM('confirmada', 'cancelada', 'pospuesta') NOT NULL DEFAULT 'confirmada',
    nombre          VARCHAR(120) NOT NULL,
    telefono        VARCHAR(16)  NOT NULL,
    dispositivo_id  CHAR(36)     NULL,
    aviso_aceptado  TINYINT(1)   NOT NULL,
    creado_en       DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    -- Sustituye al índice parcial de PostgreSQL: vale 1 solo en las citas confirmadas; en las
    -- demás es null, y los null no chocan entre sí. Una cita cancelada o pospuesta libera el horario.
    -- (Es un número y no una fecha a propósito: MySQL falla al combinar una columna calculada
    -- de fecha con el disparador del folio.)
    confirmada      TINYINT      GENERATED ALWAYS AS (IF(estado = 'confirmada', 1, NULL)) STORED,
    PRIMARY KEY (id),
    UNIQUE KEY cita_folio_uq (folio),
    UNIQUE KEY cita_sin_empalme (especialista_id, inicio, confirmada),
    KEY cita_inicio_idx (inicio),
    KEY cita_dispositivo_idx (dispositivo_id),
    -- El servicio de la cita debe ser el del especialista.
    CONSTRAINT cita_especialista_fk FOREIGN KEY (especialista_id, servicio) REFERENCES especialista (id, servicio),
    CONSTRAINT cita_dispositivo_fk  FOREIGN KEY (dispositivo_id) REFERENCES dispositivo (id),
    CONSTRAINT cita_telefono CHECK (telefono REGEXP '^[+]?[0-9]{10,15}$'),
    -- RF22: no se confirma sin aceptar el aviso de posible reprogramación.
    CONSTRAINT cita_aviso_obligatorio CHECK (aviso_aceptado = 1),
    -- Bloques de 1 hora exactos (consulta de 50 minutos).
    CONSTRAINT cita_bloque_de_una_hora CHECK (MINUTE(inicio) = 0 AND SECOND(inicio) = 0 AND MICROSECOND(inicio) = 0)
) ENGINE=InnoDB COMMENT='El folio es consecutivo y adivinable: la API nunca debe devolver una cita solo por su folio, siempre comprobar el dispositivo.';

DELIMITER //

CREATE TRIGGER cita_folio_antes_de_insertar BEFORE INSERT ON cita
FOR EACH ROW
BEGIN
    IF NEW.folio IS NULL OR NEW.folio = '' THEN
        INSERT INTO cita_folio_seq () VALUES ();
        SET NEW.folio = CONCAT('CR-', IF(LAST_INSERT_ID() < 1000000, LPAD(LAST_INSERT_ID(), 6, '0'), LAST_INSERT_ID()));
    END IF;
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- Contenido de baja prioridad (RF26 a RF30, RF34)
-- Cada tabla guarda actualizado_en para que la app sepa si su copia está vieja (RNF14).
-- ---------------------------------------------------------------------
CREATE TABLE curso (
    id             INT          NOT NULL AUTO_INCREMENT,
    delegacion_id  INT          NOT NULL,
    titulo         VARCHAR(200) NOT NULL,
    descripcion    TEXT         NULL,
    inicio         DATETIME(3)  NOT NULL,
    cupo           INT          NOT NULL,
    activo         TINYINT(1)   NOT NULL DEFAULT 1,
    actualizado_en DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    KEY curso_delegacion_idx (delegacion_id),
    CONSTRAINT curso_delegacion_fk FOREIGN KEY (delegacion_id) REFERENCES delegacion (id),
    CONSTRAINT curso_cupo CHECK (cupo > 0)
) ENGINE=InnoDB;

-- El cupo lo comprueba el backend dentro de una transacción
-- (SELECT ... FROM curso WHERE id = ? FOR UPDATE, y luego contar inscripciones).
CREATE TABLE inscripcion_curso (
    id             CHAR(36)     NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    curso_id       INT          NOT NULL,
    nombre         VARCHAR(120) NOT NULL,
    telefono       VARCHAR(16)  NOT NULL,
    dispositivo_id CHAR(36)     NULL,
    creado_en      DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    UNIQUE KEY inscripcion_curso_telefono_uq (curso_id, telefono),
    KEY inscripcion_dispositivo_idx (dispositivo_id),
    CONSTRAINT inscripcion_curso_fk FOREIGN KEY (curso_id) REFERENCES curso (id) ON DELETE CASCADE,
    CONSTRAINT inscripcion_dispositivo_fk FOREIGN KEY (dispositivo_id) REFERENCES dispositivo (id),
    CONSTRAINT inscripcion_telefono CHECK (telefono REGEXP '^[+]?[0-9]{10,15}$')
) ENGINE=InnoDB;

CREATE TABLE producto (
    id             INT           NOT NULL AUTO_INCREMENT,
    nombre         VARCHAR(150)  NOT NULL,
    precio_mxn     DECIMAL(10,2) NOT NULL,
    causa          VARCHAR(200)  NOT NULL,
    imagen_url     VARCHAR(500)  NULL,
    enlace_compra  VARCHAR(500)  NOT NULL,                        -- canal oficial de Cruz Roja; la compra no ocurre en la app
    activo         TINYINT(1)    NOT NULL DEFAULT 1,
    actualizado_en DATETIME(3)   NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    CONSTRAINT producto_precio CHECK (precio_mxn >= 0)
) ENGINE=InnoDB;

CREATE TABLE tutorial (
    id             INT          NOT NULL AUTO_INCREMENT,
    tema           VARCHAR(100) NOT NULL,
    titulo         VARCHAR(150) NOT NULL,
    descripcion    TEXT         NULL,
    duracion_seg   INT          NULL,
    video_url      VARCHAR(500) NOT NULL,
    miniatura_url  VARCHAR(500) NULL,
    orden          SMALLINT     NOT NULL DEFAULT 0,
    activo         TINYINT(1)   NOT NULL DEFAULT 1,
    actualizado_en DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    CONSTRAINT tutorial_duracion CHECK (duracion_seg IS NULL OR duracion_seg > 0)
) ENGINE=InnoDB;

DELIMITER //

-- RNF14: una baja es un UPDATE (activo = 0), así que también cambia la fecha.
CREATE TRIGGER curso_actualizado BEFORE UPDATE ON curso
FOR EACH ROW SET NEW.actualizado_en = UTC_TIMESTAMP(3)//

CREATE TRIGGER producto_actualizado BEFORE UPDATE ON producto
FOR EACH ROW SET NEW.actualizado_en = UTC_TIMESTAMP(3)//

CREATE TRIGGER tutorial_actualizado BEFORE UPDATE ON tutorial
FOR EACH ROW SET NEW.actualizado_en = UTC_TIMESTAMP(3)//

DELIMITER ;

CREATE VIEW contenido_ultima_actualizacion AS
SELECT 'delegacion' AS tipo, MAX(actualizada_en)  AS actualizado_en FROM delegacion
UNION ALL SELECT 'curso',    MAX(actualizado_en) FROM curso
UNION ALL SELECT 'producto', MAX(actualizado_en) FROM producto
UNION ALL SELECT 'tutorial', MAX(actualizado_en) FROM tutorial;

-- ---------------------------------------------------------------------
-- Bitácora: quién abrió o cambió qué (RNF21).
-- La cuenta de la app solo puede insertar y leer (ver 03_permisos_app.sql) y
-- además los disparadores rechazan cualquier UPDATE o DELETE.
-- ---------------------------------------------------------------------
CREATE TABLE bitacora (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    personal_id CHAR(36)    NULL,
    accion      VARCHAR(60) NOT NULL,       -- por ejemplo: ver_ficha, editar_ficha, editar_delegacion, login_ok, login_fallido
    entidad     VARCHAR(60) NULL,
    entidad_id  VARCHAR(80) NULL,
    detalle     JSON        NULL,
    creada_en   DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id),
    KEY bitacora_personal_idx (personal_id, creada_en DESC),
    KEY bitacora_entidad_idx (entidad, entidad_id),
    CONSTRAINT bitacora_personal_fk FOREIGN KEY (personal_id) REFERENCES personal (id)
) ENGINE=InnoDB;

DELIMITER //

CREATE TRIGGER bitacora_sin_cambios BEFORE UPDATE ON bitacora
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la bitacora es de solo agregar';
END//

CREATE TRIGGER bitacora_sin_borrado BEFORE DELETE ON bitacora
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la bitacora es de solo agregar';
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- Bloqueo por intentos fallidos (RNF07)
-- ---------------------------------------------------------------------
DELIMITER //

-- El backend la llama cada vez que una contraseña es incorrecta:
--     CALL personal_login_fallido('usuario', 5, 15, @hasta);  SELECT @hasta;
-- Al llegar a p_max intentos bloquea la cuenta p_bloqueo_min minutos (la propuesta es
-- 5 intentos y 15 minutos). Si un bloqueo anterior ya venció, el conteo empieza de
-- nuevo en 1. Mientras la cuenta está bloqueada no se alarga el bloqueo, así nadie
-- puede mantener bloqueada una cuenta ajena. p_hasta queda en null si todavía no
-- está bloqueada, o si el usuario no existe o está dado de baja.
-- Todo ocurre en un solo UPDATE; MySQL evalúa las asignaciones de izquierda a
-- derecha, por eso intentos_fallidos va antes que bloqueado_hasta.
CREATE PROCEDURE personal_login_fallido(
    IN  p_usuario      VARCHAR(60),
    IN  p_max          INT,
    IN  p_bloqueo_min  INT,
    OUT p_hasta        DATETIME(3)
)
BEGIN
    UPDATE personal
       SET intentos_fallidos = IF(bloqueado_hasta IS NOT NULL AND bloqueado_hasta <= UTC_TIMESTAMP(3),
                                  1, intentos_fallidos + 1),
           bloqueado_hasta   = CASE
                                  WHEN bloqueado_hasta IS NOT NULL AND bloqueado_hasta <= UTC_TIMESTAMP(3)
                                       THEN IF(intentos_fallidos >= p_max,
                                               UTC_TIMESTAMP(3) + INTERVAL p_bloqueo_min MINUTE, NULL)
                                  WHEN bloqueado_hasta IS NULL AND intentos_fallidos >= p_max
                                       THEN UTC_TIMESTAMP(3) + INTERVAL p_bloqueo_min MINUTE
                                  ELSE bloqueado_hasta
                               END
     WHERE usuario = LOWER(p_usuario) AND activo = 1;

    SET p_hasta = NULL;
    SELECT bloqueado_hasta INTO p_hasta
      FROM personal
     WHERE usuario = LOWER(p_usuario) AND activo = 1;
END//

-- El backend la llama cuando la contraseña es correcta y la cuenta no está bloqueada.
CREATE PROCEDURE personal_login_exitoso(IN p_id CHAR(36))
BEGIN
    UPDATE personal
       SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = UTC_TIMESTAMP(3)
     WHERE id = p_id;
END//

-- ---------------------------------------------------------------------
-- Funciones de consulta
-- ---------------------------------------------------------------------

-- Distancia en km entre dos puntos (Haversine, RF17). La app implementa la misma
-- fórmula para el respaldo sin internet.
CREATE FUNCTION distancia_km(lat1 DOUBLE, lon1 DOUBLE, lat2 DOUBLE, lon2 DOUBLE)
RETURNS DOUBLE
DETERMINISTIC NO SQL
BEGIN
    RETURN 2 * 6371 * ASIN(LEAST(1.0, SQRT(
        POW(SIN(RADIANS(lat2 - lat1) / 2), 2) +
        COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
        POW(SIN(RADIANS(lon2 - lon1) / 2), 2)
    )));
END//

-- Id de la delegación activa más cercana (RF17). Falla con SQLSTATE 22023 si las
-- coordenadas son nulas o están fuera de rango.
CREATE FUNCTION delegacion_cercana_id(p_lat DOUBLE, p_lon DOUBLE)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_id INT DEFAULT NULL;
    IF p_lat IS NULL OR p_lon IS NULL
       OR p_lat NOT BETWEEN -90 AND 90
       OR p_lon NOT BETWEEN -180 AND 180 THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'coordenadas fuera de rango';
    END IF;
    SELECT d.id INTO v_id
      FROM delegacion d
     WHERE d.activa = 1
     ORDER BY distancia_km(p_lat, p_lon, d.latitud, d.longitud), d.id
     LIMIT 1;
    RETURN v_id;
END//

-- Delegación activa más cercana, con la distancia, para que la API decida si está
-- "fuera de cobertura" (ofrecer el 911):  CALL delegacion_mas_cercana(25.68, -100.31);
CREATE PROCEDURE delegacion_mas_cercana(IN p_lat DOUBLE, IN p_lon DOUBLE)
BEGIN
    DECLARE v_id INT;
    SET v_id = delegacion_cercana_id(p_lat, p_lon);
    SELECT d.id, d.nombre, d.telefono_cecom,
           distancia_km(p_lat, p_lon, d.latitud, d.longitud) AS distancia_km
      FROM delegacion d
     WHERE d.id = v_id;
END//

-- Calcula los horarios con al menos un especialista libre en una fecha (RF20) y deja
-- el resultado en la tabla temporal cr_horarios (solo existe en tu sesión).
-- p_fecha es la fecha local; p_zona es la zona horaria de esa fecha: un desfase como
-- '-06:00' o un nombre como 'America/Monterrey' (este necesita las tablas de zonas
-- horarias del servidor). Los inicios quedan en UTC. Nunca incluye horas que ya pasaron.
CREATE PROCEDURE horarios_calcular(
    IN p_delegacion_id INT,
    IN p_servicio      VARCHAR(20),
    IN p_fecha         DATE,
    IN p_zona          VARCHAR(40)
)
BEGIN
    IF CONVERT_TZ('2026-01-01 12:00:00', p_zona, '+00:00') IS NULL THEN
        SIGNAL SQLSTATE '22023' SET MESSAGE_TEXT = 'zona horaria desconocida: usa un desfase como -06:00';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS cr_horarios;
    CREATE TEMPORARY TABLE cr_horarios (
        inicio              DATETIME(3) NOT NULL,
        especialistas_libres INT        NOT NULL,
        PRIMARY KEY (inicio)
    );

    INSERT INTO cr_horarios (inicio, especialistas_libres)
    SELECT s.inicio, COUNT(*)
      FROM (SELECT CONVERT_TZ(TIMESTAMP(p_fecha, MAKETIME(n.hr, 0, 0)), p_zona, '+00:00') AS inicio
              FROM servicio_horario h
              JOIN (SELECT 0 AS hr UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
                    UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11
                    UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
                    UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19
                    UNION ALL SELECT 20 UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL SELECT 23) n
                ON n.hr >= h.hora_inicio AND n.hr < h.hora_fin
             WHERE h.servicio = p_servicio) s
      JOIN especialista e
        ON e.delegacion_id = p_delegacion_id
       AND e.servicio      = p_servicio
       AND e.activo        = 1
     WHERE s.inicio > UTC_TIMESTAMP(3)
       AND NOT EXISTS (SELECT 1 FROM cita c
                        WHERE c.especialista_id = e.id
                          AND c.inicio          = s.inicio
                          AND c.confirmada      = 1)
     GROUP BY s.inicio;
END//

-- Lo mismo, devuelto como resultado:
--     CALL horarios_disponibles(1, 'nutricion', '2026-11-03', '-06:00');
CREATE PROCEDURE horarios_disponibles(
    IN p_delegacion_id INT,
    IN p_servicio      VARCHAR(20),
    IN p_fecha         DATE,
    IN p_zona          VARCHAR(40)
)
BEGIN
    CALL horarios_calcular(p_delegacion_id, p_servicio, p_fecha, p_zona);
    SELECT inicio, especialistas_libres FROM cr_horarios ORDER BY inicio;
END//

DELIMITER ;
