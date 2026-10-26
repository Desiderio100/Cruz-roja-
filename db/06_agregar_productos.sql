-- =====================================================================
-- 06_agregar_productos.sql  (MySQL 8.0 o superior)
-- Agrega productos al catálogo "Productos con causa" de la app.
-- Se puede correr las veces que quieras: cada corrida AGREGA lo que escribas abajo.
--
-- CÓMO USARLO (MySQL Workbench), conectado como avnadmin o como tu usuario dev:
--   1. Edita la parte de abajo que dice  <== EDITA: una línea por producto.
--   2. File > Open SQL Script... > este archivo > primer rayo amarillo (Execute all).
--   3. Al final aparece la tabla con todos los productos y su número (id).
--
-- REGLAS DE CADA COLUMNA
--   nombre         Texto, máximo 150 letras.
--   precio_mxn     Número en pesos, sin signo $ ni comas. Ejemplo: 199.00. No puede ser negativo.
--   causa          Texto corto de qué apoya la compra, máximo 200 letras.
--   imagen_url     Dirección https de la foto, o NULL si todavía no hay (la app pone una cruz roja).
--   enlace_compra  Dirección https del canal OFICIAL de Cruz Roja donde se compra.
--                  Si no empieza con https://, el servidor no se lo entrega a la app.
--
-- PARA QUITAR UN PRODUCTO DE LA APP (sin borrarlo): cambia el 5 por su id y corre
--     UPDATE producto SET activo = 0 WHERE id = 5;
-- PARA VOLVER A MOSTRARLO:
--     UPDATE producto SET activo = 1 WHERE id = 5;
-- =====================================================================
USE cruzroja;

INSERT INTO producto (nombre, precio_mxn, causa, imagen_url, enlace_compra) VALUES
    ('Nombre del producto 1', 199.00, 'Apoya ...', NULL, 'https://tienda.ejemplo.invalid/producto-1'),   -- <== EDITA
    ('Nombre del producto 2', 99.50,  'Apoya ...', NULL, 'https://tienda.ejemplo.invalid/producto-2');  -- <== EDITA (agrega más líneas igual; la última termina en ;)

SELECT id, nombre, precio_mxn, causa, imagen_url, enlace_compra, activo
  FROM producto
 ORDER BY id;
