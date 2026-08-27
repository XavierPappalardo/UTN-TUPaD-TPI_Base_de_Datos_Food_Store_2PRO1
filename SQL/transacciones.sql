-- transacciones.sql
-- TPI Base de Datos - Food Store
--
-- Requiere:
--   1. schema.sql
--   2. objects.sql
--   3. data.sql
--
-- IMPORTANTE:
-- El escenario de concurrencia requiere DOS SESIONES
-- independientes de PostgreSQL/DBeaver.
--


--
-- 1. ATOMICIDAD
-- 


SELECT COUNT(*) AS pedidos_antes
FROM pedido
WHERE usuario_id = 2;

BEGIN;

CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[{"producto_id":999999,"cantidad":1}]'::jsonb
);

ROLLBACK;



SELECT COUNT(*) AS pedidos_despues_rollback
FROM pedido
WHERE usuario_id = 2;

SELECT COUNT(*) AS detalles_pedidos_usuario_2
FROM detalle_pedido dp
JOIN pedido p ON p.id_pedido = dp.pedido_id
WHERE p.usuario_id = 2;


--
-- ATOMICIDAD CON CANTIDAD INVÁLIDA
-- 

BEGIN;

CALL sp_crear_pedido(
    2,
    'TARJETA',
    '[{"producto_id":1,"cantidad":0}]'::jsonb
);

ROLLBACK;


-- Verificación del estado posterior.

SELECT id_pedido,
       usuario_id,
       estado_pedido,
       total_pedido
FROM pedido
WHERE usuario_id = 2
ORDER BY id_pedido DESC;


--
-- TRANSACCIÓN MANUAL CON ROLLBACK
--

-- Comprobamos que no exista previamente.

SELECT id_categoria, nombre_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria Demo ROLLBACK';


BEGIN;

INSERT INTO categoria(
    nombre_categoria,
    descripcion_categoria
)
VALUES (
    'Categoria Demo ROLLBACK',
    'Categoria creada para demostrar ROLLBACK'
);

-- La fila existe dentro de la transacción.

SELECT id_categoria,
       nombre_categoria,
       descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria Demo ROLLBACK';

-- Cancelamos la transacción.

ROLLBACK;


SELECT id_categoria,
       nombre_categoria,
       descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria Demo ROLLBACK';


-- 
-- TRANSACCIÓN MANUAL CON COMMIT
-- 

BEGIN;

INSERT INTO categoria(
    nombre_categoria,
    descripcion_categoria
)
VALUES (
    'Categoria Demo COMMIT',
    'Categoria creada para demostrar COMMIT'
)
RETURNING id_categoria;


COMMIT;

SELECT id_categoria,
       nombre_categoria,
       descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria Demo COMMIT';


--
-- TRANSACCIÓN REAL: CREAR PEDIDO CORRECTAMENTE
-- 

BEGIN;

CALL sp_crear_pedido(
    2,
    'TRANSFERENCIA',
    '[{"producto_id":1,"cantidad":1},
      {"producto_id":9,"cantidad":1}]'::jsonb
);

-- Comprobamos el pedido creado dentro de la transacción.

SELECT p.id_pedido,
       p.usuario_id,
       p.estado_pedido,
       p.forma_pago,
       p.total_pedido
FROM pedido p
WHERE p.usuario_id = 2
ORDER BY p.id_pedido DESC
LIMIT 1;


-- Comprobamos sus detalles.

SELECT dp.id_detallepedido,
       dp.pedido_id,
       dp.producto_id,
       dp.cantidad_detallepedido,
       dp.precio_unitario,
       dp.subtotal_detallepedido
FROM detalle_pedido dp
WHERE dp.pedido_id = (
    SELECT MAX(id_pedido)
    FROM pedido
    WHERE usuario_id = 2
);


-- Confirmamos la transacción.

COMMIT;


-- 
-- VERIFICACIÓN DEL DESCUENTO DE STOCK
--
-- El procedimiento descuenta el stock dentro de la misma
-- transacción.
--

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto IN (1, 9)
ORDER BY id_producto;


--
-- CONCURRENCIA - PREPARACIÓN
--
-- IMPORTANTE:
-- Desde este punto se necesitan DOS SESIONES.
--
-- Abrir:
--
--   SESIÓN A
--   SESIÓN B
--
-- Ambas conectadas a la misma base de datos.
--
-- El objetivo es simular dos operadores intentando vender
-- simultáneamente un producto con stock limitado.
--


--
-- SESIÓN A
-- Ejecutar únicamente en la SESIÓN A.
--

-- SESIÓN A

BEGIN;

-- Consultamos el stock actual.

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto = 1;


-- Bloqueamos la fila del producto.
--
-- Mientras esta transacción permanezca abierta, otra sesión que
-- intente hacer SELECT ... FOR UPDATE sobre el mismo producto tendrá que esperar.

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto = 1
FOR UPDATE;


-- IMPORTANTE: No ejecutar COMMIT todavía.
-- Dejar esta sesión abierta y pasar a SESIÓN B.


-- 
-- SESIÓN B
-- Ejecutar en una segunda conexión mientras la SESIÓN A mantiene el bloqueo.
-- 

-- SESIÓN B

BEGIN;

-- Esta consulta puede ejecutarse normalmente.

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto = 1;

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto = 1
FOR UPDATE;


-- La SESIÓN B queda esperando porque la SESIÓN A mantiene bloqueada la fila.
--
-- Volvemos a SESIÓN A.


-- 
-- SESIÓN A
-- 

-- SESIÓN A

COMMIT;


-- Al hacer COMMIT en SESIÓN A, se libera el bloqueo.
--
-- La SESIÓN B puede continuar.


-- 
-- SESIÓN B
-- 

-- SESIÓN B

-- Una vez liberado el bloqueo, esta sesión continúa.

SELECT id_producto,
       nombre_producto,
       stock_producto
FROM producto
WHERE id_producto = 1;

COMMIT;


--
-- 8. CONCURRENCIA CON sp_crear_pedido
-- 


-- 
-- SESIÓN A
-- 

BEGIN;

CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[{"producto_id":1,"cantidad":1}]'::jsonb
);

-- NO hacer COMMIT todavía.

-- 
-- SESIÓN B
--
-- Ejecutar simultáneamente:
--
-- BEGIN;
--
-- CALL sp_crear_pedido(
--     3,
--     'TARJETA',
--     '[{"producto_id":1,"cantidad":1}]'::jsonb
-- );
--
-- La SESIÓN B deberá esperar al bloqueo de la SESIÓN A.
--

-- 
-- SESIÓN A
-- 

COMMIT;


-- 
-- SESIÓN B
-- 
-- VERIFICACIÓN FINAL DEL STOCK
-- 

SELECT id_producto,
       nombre_producto,
       stock_producto,
       disponible,
       eliminado
FROM producto
WHERE id_producto = 1;


-- 
-- VERIFICACIÓN DE PEDIDOS CREADOS
-- 

SELECT p.id_pedido,
       p.usuario_id,
       p.fecha_pedido,
       p.estado_pedido,
       p.forma_pago,
       p.total_pedido
FROM pedido p
WHERE p.usuario_id IN (2, 3)
ORDER BY p.id_pedido DESC;

-- 
-- VERIFICACIÓN DE DETALLES
--

SELECT dp.id_detallepedido,
       dp.pedido_id,
       dp.producto_id,
       dp.cantidad_detallepedido,
       dp.precio_unitario,
       dp.subtotal_detallepedido
FROM detalle_pedido dp
ORDER BY dp.id_detallepedido DESC
LIMIT 10;

-- 
-- VERIFICACIÓN DEL TOTAL CALCULADO
-- 
SELECT p.id_pedido,
       p.total_pedido AS total_guardado,
       calcular_total_pedido(p.id_pedido) AS total_calculado
FROM pedido p
WHERE p.eliminado = FALSE
ORDER BY p.id_pedido DESC;
