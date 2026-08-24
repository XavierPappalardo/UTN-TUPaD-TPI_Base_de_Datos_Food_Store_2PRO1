-- ============================================================
-- TRANSACCIONES.SQL
-- FOOD STORE
-- PostgreSQL 16+
-- 


-- ============================================================
-- 1. ATOMICIDAD
-- ============================================================
--
-- El procedimiento sp_crear_pedido debe ser atómico.
--
-- Si uno de los productos es inválido, la operación completa
-- debe fallar.
--
-- No debe quedar:
--   - el pedido creado
--   - ni los detalles anteriores
--
-- El TPI exige demostrar este comportamiento.
-- ============================================================


-- ------------------------------------------------------------
-- 1.1. CONSULTAR ESTADO ANTES
-- ------------------------------------------------------------

SELECT
    id_pedido,
    usuario_id,
    estado_pedido,
    forma_pago,
    total_pedido
FROM pedido
ORDER BY id_pedido DESC;


-- ------------------------------------------------------------
-- 1.2. INTENTAR CREAR PEDIDO CON PRODUCTO INEXISTENTE
-- ------------------------------------------------------------
--
-- El producto 999999 no existe.
--
-- El procedimiento debe lanzar una excepción.
-- ============================================================

CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[
        {"producto_id": 1, "cantidad": 1},
        {"producto_id": 999999, "cantidad": 1}
    ]'::jsonb
);


-- ------------------------------------------------------------
-- 1.3. VERIFICAR QUE NO QUEDÓ EL PEDIDO
-- ------------------------------------------------------------
--
-- Si la llamada anterior falla dentro de una transacción,
-- PostgreSQL revierte las operaciones realizadas.
-- ============================================================

SELECT
    id_pedido,
    usuario_id,
    estado_pedido,
    forma_pago,
    total_pedido
FROM pedido
ORDER BY id_pedido DESC;


-- ------------------------------------------------------------
-- 1.4. VERIFICAR DETALLES
-- ------------------------------------------------------------

SELECT
    id_detallepedido,
    pedido_id,
    producto_id,
    cantidad_detallepedido,
    precio_unitario,
    subtotal_detallepedido
FROM detalle_pedido
ORDER BY id_detallepedido DESC;


-- ============================================================
-- 2. TRANSACCIÓN MANUAL CON COMMIT
-- ============================================================
--
-- Las operaciones realizadas dentro de BEGIN quedan
-- confirmadas definitivamente cuando se ejecuta COMMIT.
-- ============================================================


BEGIN;


-- Crear una categoría temporal de prueba.

INSERT INTO categoria (
    nombre_categoria,
    descripcion_categoria
)
VALUES (
    'Categoria COMMIT',
    'Prueba de transacción confirmada'
);


-- Verificar que existe dentro de la transacción.

SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria COMMIT';


-- Confirmar la transacción.

COMMIT;


-- ------------------------------------------------------------
-- Verificar después del COMMIT
-- ------------------------------------------------------------

SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria COMMIT';


-- ============================================================
-- 3. TRANSACCIÓN MANUAL CON ROLLBACK
-- ============================================================
--
-- Las operaciones realizadas después de BEGIN se deshacen
-- cuando se ejecuta ROLLBACK.
-- ============================================================


BEGIN;


-- Crear una categoría temporal.

INSERT INTO categoria (
    nombre_categoria,
    descripcion_categoria
)
VALUES (
    'Categoria ROLLBACK',
    'Prueba de transacción revertida'
);


-- Verificar que existe dentro de la transacción.

SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria ROLLBACK';


-- Deshacer la operación.

ROLLBACK;


-- ------------------------------------------------------------
-- Verificar después del ROLLBACK
-- ------------------------------------------------------------
--
-- Esta consulta debe devolver 0 filas.
-- ------------------------------------------------------------

SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE nombre_categoria = 'Categoria ROLLBACK';


-- ============================================================
-- 4. AISLAMIENTO — READ COMMITTED
-- ============================================================
--
-- Esta prueba debe realizarse utilizando DOS SESIONES
-- simultáneas de DBeaver.
--
-- SESIÓN A y SESIÓN B deben estar conectadas a la misma
-- base food_store.
--
-- PostgreSQL utiliza READ COMMITTED como nivel de aislamiento
-- por defecto.
-- ============================================================


-- ============================================================
-- SESIÓN A
-- ============================================================

BEGIN;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;


-- Consultar el stock actual de un producto.

SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1;


-- NO ejecutar COMMIT todavía.
--
-- Mantener abierta esta transacción.


-- ============================================================
-- SESIÓN B
-- ============================================================

BEGIN;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;


-- Modificar el stock del mismo producto.

UPDATE producto
SET stock_producto = stock_producto - 1
WHERE id_producto = 1;


-- Confirmar el cambio.

COMMIT;


-- ============================================================
-- VOLVER A SESIÓN A
-- ============================================================
--
-- En READ COMMITTED, cada sentencia puede observar datos
-- confirmados por otras transacciones.
-- ============================================================

SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1;


-- Finalizar la transacción de A.

COMMIT;


-- ============================================================
-- 5. AISLAMIENTO — SERIALIZABLE
-- ============================================================
--
-- Se repite el escenario utilizando SERIALIZABLE.
--
-- PostgreSQL puede abortar una de las transacciones con un
-- error de serialización si detecta una dependencia que no
-- puede mantenerse de forma serializable.
-- ============================================================


-- ============================================================
-- SESIÓN A
-- ============================================================

BEGIN;

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;


SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1;


-- Mantener abierta la transacción.


-- ============================================================
-- SESIÓN B
-- ============================================================

BEGIN;

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;


SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1;


-- Intentar modificar el mismo producto.

UPDATE producto
SET stock_producto = stock_producto - 1
WHERE id_producto = 1;


-- Intentar confirmar.

COMMIT;


-- ============================================================
-- VOLVER A SESIÓN A
-- ============================================================
--
-- Intentar modificar y confirmar.
--
-- Dependiendo del orden exacto de las operaciones, PostgreSQL
-- puede generar:
--
-- ERROR: could not serialize access due to concurrent update
--
-- Esto demuestra la protección del nivel SERIALIZABLE.
-- ============================================================

UPDATE producto
SET stock_producto = stock_producto - 1
WHERE id_producto = 1;

COMMIT;


-- ============================================================
-- 6. BLOQUEO CON SELECT ... FOR UPDATE
-- ============================================================
--
-- Esta es una de las pruebas más importantes del TPI.
--
-- Dos operadores intentan modificar el mismo producto.
--
-- FOR UPDATE bloquea la fila hasta que termine la transacción.
-- ============================================================


-- ============================================================
-- SESIÓN A
-- ============================================================


BEGIN;


SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1
FOR UPDATE;


-- IMPORTANTE:
-- NO ejecutar COMMIT todavía.
--
-- La fila queda bloqueada.


-- ============================================================
-- SESIÓN B
-- ============================================================
--
-- Ejecutar mientras A mantiene abierta la transacción.
-- ============================================================


BEGIN;


SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1
FOR UPDATE;


-- 
-- VOLVER A SESIÓN A
-- 


UPDATE producto
SET stock_producto = stock_producto - 1
WHERE id_producto = 1;


COMMIT;


-- 
-- VOLVER A SESIÓN B
--


SELECT
    id_producto,
    nombre_producto,
    stock_producto
FROM producto
WHERE id_producto = 1;


-- Realizar aquí las validaciones de stock necesarias.


COMMIT;

-- 
-- PRUEBA DE SOBREVENTA CON sp_crear_pedido
-- 

UPDATE producto
SET stock_producto = 1,
    disponible = TRUE
WHERE id_producto = 6;


-- Verificar.

SELECT
    id_producto,
    nombre_producto,
    stock_producto,
    disponible
FROM producto
WHERE id_producto = 6;


-- 
-- SESIÓN A
-- 

BEGIN;


-- Bloquear producto.

SELECT
    stock_producto,
    disponible
FROM producto
WHERE id_producto = 6
FOR UPDATE;


-- Crear pedido para el producto.

CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[
        {"producto_id": 6, "cantidad": 1}
    ]'::jsonb
);


-- Confirmar.

COMMIT;


-- 
-- SESIÓN B
-- 

BEGIN;


CALL sp_crear_pedido(
    3,
    'EFECTIVO',
    '[
        {"producto_id": 6, "cantidad": 1}
    ]'::jsonb
);


-- Si se produce la excepción:

ROLLBACK;

-- 
-- VERIFICACION FINAL
-- 

SELECT
    id_producto,
    nombre_producto,
    stock_producto,
    disponible
FROM producto
WHERE id_producto = 6;


-- Ver pedidos generados.

SELECT
    id_pedido,
    usuario_id,
    estado_pedido,
    forma_pago,
    total_pedido
FROM pedido
ORDER BY id_pedido DESC;


-- Ver detalles generados.

SELECT
    id_detallepedido,
    pedido_id,
    producto_id,
    cantidad_detallepedido,
    precio_unitario,
    subtotal_detallepedido
FROM detalle_pedido
ORDER BY id_detallepedido DESC;
