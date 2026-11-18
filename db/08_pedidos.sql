-- =====================================================================
-- 08_pedidos.sql  (MySQL 8.0 o superior)
-- Pagos con Stripe de "Productos con causa": pedidos con envío a domicilio.
-- Necesita 01_esquema.sql ya corrido (usa las tablas producto y dispositivo).
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin o como tu usuario dev:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--   Después corre 03_permisos_app.sql otra vez: ahí se le dan a cruzroja_app los permisos
--   sobre las dos tablas nuevas (03 se puede repetir las veces que quieras).
--
-- Se puede correr varias veces: lo que ya existe no se toca. Para volver a empezar solo con
-- los pedidos (borra TODOS los pedidos), usa el bloque comentado al final.
--
-- Qué guarda cada tabla
--   pedido         Una compra: qué producto, cuántos, cuánto costó y a dónde se envía.
--                  Guarda COPIA del nombre y del precio del momento (si el catálogo cambia
--                  después, el pedido no cambia). NO guarda ningún dato de tarjeta: eso solo lo
--                  ve Stripe. Empieza 'pendiente' y pasa a 'pagado' cuando Stripe avisa al backend.
--   evento_stripe  Los avisos (webhooks) que Stripe ya mandó. Evita procesar dos veces el mismo.
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

-- MySQL no tiene secuencias: cada fila de esta tabla reparte un número de folio.
CREATE TABLE IF NOT EXISTS pedido_folio_seq (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS pedido (
    id                       CHAR(36)      NOT NULL DEFAULT (LOWER(CONCAT_WS('-', HEX(RANDOM_BYTES(4)), HEX(RANDOM_BYTES(2)), CONCAT('4', SUBSTR(HEX(RANDOM_BYTES(2)), 2)), CONCAT(SUBSTR('89ab', 1 + (ORD(RANDOM_BYTES(1)) & 3), 1), SUBSTR(HEX(RANDOM_BYTES(2)), 2)), HEX(RANDOM_BYTES(6))))),
    folio                    VARCHAR(16)   NOT NULL DEFAULT '',        -- lo asigna el disparador: PC-000001, PC-000002...
    dispositivo_id           CHAR(36)      NOT NULL,
    producto_id              INT           NOT NULL,
    producto_nombre          VARCHAR(150)  NOT NULL,                   -- copia del nombre al comprar
    cantidad                 SMALLINT      NOT NULL,
    precio_unitario_mxn      DECIMAL(10,2) NOT NULL,                   -- copia del precio al comprar
    envio_mxn                DECIMAL(10,2) NOT NULL,
    total_mxn                DECIMAL(10,2) NOT NULL,
    estado                   ENUM('pendiente', 'pagado', 'cancelado') NOT NULL DEFAULT 'pendiente',
    stripe_payment_intent_id VARCHAR(100)  NULL,                       -- "pi_..." del cobro en Stripe
    nombre                   VARCHAR(120)  NOT NULL,
    telefono                 VARCHAR(16)   NOT NULL,
    calle_numero             VARCHAR(150)  NOT NULL,
    colonia                  VARCHAR(100)  NOT NULL,
    ciudad                   VARCHAR(100)  NOT NULL,
    entidad                  VARCHAR(60)   NOT NULL,                   -- estado de la república
    codigo_postal            CHAR(5)       NOT NULL,
    referencias              VARCHAR(200)  NULL,
    creado_en                DATETIME(3)   NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    pagado_en                DATETIME(3)   NULL,
    PRIMARY KEY (id),
    UNIQUE KEY pedido_folio_uq (folio),
    UNIQUE KEY pedido_stripe_uq (stripe_payment_intent_id),            -- los null no chocan entre sí
    KEY pedido_dispositivo_idx (dispositivo_id, creado_en),
    CONSTRAINT pedido_dispositivo_fk FOREIGN KEY (dispositivo_id) REFERENCES dispositivo (id),
    CONSTRAINT pedido_producto_fk    FOREIGN KEY (producto_id)    REFERENCES producto (id),
    CONSTRAINT pedido_cantidad       CHECK (cantidad BETWEEN 1 AND 10),
    CONSTRAINT pedido_importes       CHECK (precio_unitario_mxn >= 0 AND envio_mxn >= 0
                                            AND total_mxn = precio_unitario_mxn * cantidad + envio_mxn),
    CONSTRAINT pedido_telefono       CHECK (telefono REGEXP '^[+]?[0-9]{10,15}$'),
    CONSTRAINT pedido_codigo_postal  CHECK (codigo_postal REGEXP '^[0-9]{5}$'),
    CONSTRAINT pedido_pagado_en      CHECK ((estado = 'pagado') = (pagado_en IS NOT NULL))
) ENGINE=InnoDB COMMENT='Datos personales (nombre, teléfono y domicilio): solo para enviar el pedido. El folio es consecutivo y adivinable: la API nunca debe devolver un pedido solo por su folio, siempre comprobar el dispositivo.';

CREATE TABLE IF NOT EXISTS evento_stripe (
    id          VARCHAR(100) NOT NULL,                                 -- "evt_..." que manda Stripe
    tipo        VARCHAR(80)  NOT NULL,                                 -- por ejemplo payment_intent.succeeded
    recibido_en DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    PRIMARY KEY (id)
) ENGINE=InnoDB COMMENT='Solo se agregan filas. Si un evento ya está aquí, el backend no lo procesa otra vez.';

DROP TRIGGER IF EXISTS pedido_folio_antes_de_insertar;

DELIMITER //

CREATE TRIGGER pedido_folio_antes_de_insertar BEFORE INSERT ON pedido
FOR EACH ROW
BEGIN
    IF NEW.folio IS NULL OR NEW.folio = '' THEN
        INSERT INTO pedido_folio_seq () VALUES ();
        SET NEW.folio = CONCAT('PC-', IF(LAST_INSERT_ID() < 1000000, LPAD(LAST_INSERT_ID(), 6, '0'), LAST_INSERT_ID()));
    END IF;
END//

DELIMITER ;

-- Revisa el resultado: deben aparecer las dos tablas nuevas y el disparador.
SELECT table_name AS tabla FROM information_schema.TABLES
 WHERE table_schema = 'cruzroja' AND table_name IN ('pedido', 'pedido_folio_seq', 'evento_stripe')
 ORDER BY table_name;

-- ---------------------------------------------------------------------
-- SOLO DESARROLLO — borrar los pedidos y empezar de cero (quita el "-- " de estas líneas):
-- DROP TABLE IF EXISTS evento_stripe;
-- DROP TABLE IF EXISTS pedido;
-- DROP TABLE IF EXISTS pedido_folio_seq;
-- ---------------------------------------------------------------------
