-- =====================================================================
-- 09_pedidos_admin.sql  (MySQL 8.0.16 o superior)
-- Sitio web de administración de pedidos: estado del envío, número de guía y reembolsos.
-- Necesita 01_esquema.sql y 08_pedidos.sql ya corridos (agrega columnas a la tabla pedido).
--
-- CÓMO CORRERLO (MySQL Workbench), conectado como avnadmin o como tu usuario dev:
--   File > Open SQL Script... > este archivo > rayo amarillo solo (Execute all).
--   NO hace falta correr 03_permisos_app.sql otra vez: la cuenta cruzroja_app ya puede leer y
--   actualizar `pedido`, leer `personal` e insertar en `bitacora` (lo da el 03 original).
--
-- Se puede correr varias veces: si las columnas ya existen, no hace nada. Los pedidos que ya
-- existan se conservan; quedan con el envío en 'por_preparar'.
--
-- Qué agrega a la tabla pedido
--   estado           ahora también puede ser 'reembolsado' (el dinero ya se devolvió por Stripe).
--   estado_envio     por_preparar > preparando > enviado > entregado. Solo avanza, y solo si el
--                    pedido está pagado (o reembolsado después de pagarse).
--   guia_envio       número de guía de la paquetería (opcional).
--   enviado_en / entregado_en   cuándo pasó cada cosa.
--   stripe_refund_id, reembolsado_en, reembolso_motivo   datos del reembolso.
-- Quién hizo cada cambio queda en la tabla `bitacora` que ya existe (solo se agrega, no se edita).
-- =====================================================================
USE cruzroja;
SET NAMES utf8mb4;

-- ¿Ya está aplicado? (la columna estado_envio es la señal)
SET @zz_ya := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE table_schema = 'cruzroja' AND table_name = 'pedido' AND column_name = 'estado_envio');

-- Todo en una sola sentencia: o se aplica completo o no se aplica nada.
SET @zz_sql := IF(@zz_ya > 0, 'DO 0', '
ALTER TABLE pedido
    MODIFY COLUMN estado ENUM(''pendiente'', ''pagado'', ''cancelado'', ''reembolsado'')
        NOT NULL DEFAULT ''pendiente'',
    ADD COLUMN estado_envio     ENUM(''por_preparar'', ''preparando'', ''enviado'', ''entregado'')
                                NOT NULL DEFAULT ''por_preparar'' AFTER estado,
    ADD COLUMN guia_envio       VARCHAR(40)  NULL AFTER estado_envio,
    ADD COLUMN enviado_en       DATETIME(3)  NULL,
    ADD COLUMN entregado_en     DATETIME(3)  NULL,
    ADD COLUMN stripe_refund_id VARCHAR(100) NULL,
    ADD COLUMN reembolsado_en   DATETIME(3)  NULL,
    ADD COLUMN reembolso_motivo VARCHAR(200) NULL,
    DROP CHECK pedido_pagado_en,
    ADD CONSTRAINT pedido_pagado_en_v2 CHECK ((estado IN (''pagado'', ''reembolsado'')) = (pagado_en IS NOT NULL)),
    ADD CONSTRAINT pedido_reembolso CHECK ((estado = ''reembolsado'') = (reembolsado_en IS NOT NULL)),
    ADD CONSTRAINT pedido_envio_fechas CHECK (
        ((estado_envio IN (''enviado'', ''entregado'')) = (enviado_en IS NOT NULL))
        AND ((estado_envio = ''entregado'') = (entregado_en IS NOT NULL))),
    ADD CONSTRAINT pedido_envio_solo_pagados CHECK (estado_envio = ''por_preparar'' OR estado IN (''pagado'', ''reembolsado'')),
    ADD CONSTRAINT pedido_guia_formato CHECK (guia_envio IS NULL OR guia_envio REGEXP ''^[A-Za-z0-9][A-Za-z0-9 -]{2,39}$''),
    ADD UNIQUE KEY pedido_refund_uq (stripe_refund_id),
    ADD KEY pedido_estado_idx (estado, creado_en)');

PREPARE zz_s FROM @zz_sql;
EXECUTE zz_s;
DEALLOCATE PREPARE zz_s;

-- Revisa el resultado: debe aparecer `estado` (con "reembolsado") y las 7 columnas nuevas.
SELECT column_name AS columna, column_type AS tipo
  FROM information_schema.COLUMNS
 WHERE table_schema = 'cruzroja' AND table_name = 'pedido'
   AND column_name IN ('estado', 'estado_envio', 'guia_envio', 'enviado_en', 'entregado_en',
                       'stripe_refund_id', 'reembolsado_en', 'reembolso_motivo')
 ORDER BY ordinal_position;
