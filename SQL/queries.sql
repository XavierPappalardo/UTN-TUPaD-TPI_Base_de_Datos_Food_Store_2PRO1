-- QUERIES.SQL
-- FOOD STORE
-- PostgreSQL 16+

-- ------------------------------------------------------------
-- GESTION DE CATEGORIAS
-- ------------------------------------------------------------

-- LISTAR CATEGORÍAS
SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE eliminado = FALSE
ORDER BY id_categoria;

-- CREAR CATEGORIA
INSERT INTO categoria (
    nombre_categoria,
    descripcion_categoria
)
VALUES (
    'Empanadas',
    'Variedad de empanadas'
)
RETURNING id_categoria;

-- EDITAR CATEGORIA
UPDATE categoria
SET
    nombre_categoria = 'Pizzas y Empanadas',
    descripcion_categoria = 'Catálogo ampliado'
WHERE id_categoria = 1
  AND eliminado = FALSE
RETURNING id_categoria,
          nombre_categoria,
          descripcion_categoria;

-- ELIMINAR CATEGORIA (Se usa ID 4 para no romper los productos cargados en data.sql)
UPDATE categoria
SET eliminado = TRUE
WHERE id_categoria = 4
  AND eliminado = FALSE
RETURNING id_categoria,
          nombre_categoria,
          eliminado;


-- ------------------------------------------------------------
-- GESTION DE PRODUCTOS
-- ------------------------------------------------------------

-- LISTAR PRODUCTOS
SELECT
    p.id_producto,
    p.nombre_producto,
    p.precio_producto,
    p.stock_producto,
    c.nombre_categoria AS categoria
FROM producto p
JOIN categoria c
    ON c.id_categoria = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE
ORDER BY p.id_producto;

-- CREAR PRODUCTO
INSERT INTO producto (
    nombre_producto,
    descripcion_producto,
    precio_producto,
    stock_producto,
    imagen_producto,
    disponible,
    categoria_id
)
SELECT
    'Fugazzeta',
    'Pizza de cebolla',
    1800.00,
    10,
    NULL,
    TRUE,
    c.id_categoria
FROM categoria c
WHERE c.id_categoria = 1
  AND c.eliminado = FALSE
RETURNING id_producto,
          nombre_producto,
          precio_producto,
          stock_producto,
          categoria_id;

-- EDITAR PRODUCTO
UPDATE producto
SET
    precio_producto = COALESCE(2000.00, precio_producto),
    stock_producto = COALESCE(NULL, stock_producto)
WHERE id_producto = 1
  AND eliminado = FALSE
RETURNING id_producto,
          nombre_producto,
          precio_producto,
          stock_producto;


-- ------------------------------------------------------------
-- GESTION DE USUARIOS
-- ------------------------------------------------------------

-- LISTAR USUARIOS
SELECT
    id_usuario,
    nombre_usuario,
    apellido_usuario,
    mail_usuario,
    rol
FROM usuario
WHERE eliminado = FALSE
ORDER BY id_usuario;

-- CREAR USUARIO
INSERT INTO usuario (
    nombre_usuario,
    apellido_usuario,
    mail_usuario,
    celular_usuario,
    contrasena_usuario,
    rol
)
VALUES (
    'Juan',
    'Pérez',
    'juan.nuevo@foodstore.com',
    '2617654321',
    'hash_pass_nuevo',
    'USUARIO'
)
RETURNING id_usuario;

-- EDITAR USUARIO
UPDATE usuario
SET celular_usuario = '2617654321'
WHERE id_usuario = 1
  AND eliminado = FALSE
RETURNING id_usuario,
          nombre_usuario,
          apellido_usuario,
          mail_usuario,
          celular_usuario;


-- ------------------------------------------------------------
-- GESTION DE PEDIDOS Y DETALLES
-- ------------------------------------------------------------

-- CREAR PEDIDO CON DETALLES (Se usan IDs 2 y 3 que están vigentes)
CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[
        {"producto_id": 2, "cantidad": 2},
        {"producto_id": 3, "cantidad": 1}
    ]'::jsonb
);

-- LISTAR PEDIDOS
SELECT
    id_pedido,
    usuario,
    fecha_pedido,
    estado_pedido,
    forma_pago,
    total_pedido
FROM v_pedidos_resumen
ORDER BY id_pedido;

-- ACTUALIZAR ESTADO / FORMA DE PAGO
UPDATE pedido
SET
    estado_pedido = 'CONFIRMADO',
    forma_pago = 'TARJETA'
WHERE id_pedido = 1
  AND eliminado = FALSE
RETURNING id_pedido,
          estado_pedido,
          forma_pago;

-- ELIMINAR PRODUCTO (Soft Delete al final de las operaciones)
UPDATE producto
SET eliminado = TRUE
WHERE id_producto = 6
  AND eliminado = FALSE
RETURNING id_producto,
          nombre_producto,
          eliminado;

-- ELIMINAR PEDIDO
BEGIN;

UPDATE detalle_pedido
SET eliminado = TRUE
WHERE pedido_id = 1;

UPDATE pedido
SET eliminado = TRUE
WHERE id_pedido = 1;

COMMIT;


-- ------------------------------------------------------------
-- CONSULTAS ANALITICAS ADICIONALES
-- ------------------------------------------------------------

-- TOP 5 PRODUCTOS MÁS VENDIDOS
SELECT
    pr.id_producto,
    pr.nombre_producto,
    SUM(dp.cantidad_detallepedido) AS unidades_vendidas
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id_producto = dp.producto_id
WHERE dp.eliminado = FALSE
GROUP BY
    pr.id_producto,
    pr.nombre_producto
ORDER BY unidades_vendidas DESC
LIMIT 5;

-- FACTURACION POR CATEGORIA Y POR MES
SELECT
    c.nombre_categoria AS categoria,
    date_trunc('month', ped.fecha_pedido) AS mes,
    SUM(dp.subtotal_detallepedido) AS facturado
FROM detalle_pedido dp
JOIN pedido ped
    ON ped.id_pedido = dp.pedido_id
   AND ped.eliminado = FALSE
JOIN producto pr
    ON pr.id_producto = dp.producto_id
JOIN categoria c
    ON c.id_categoria = pr.categoria_id
WHERE dp.eliminado = FALSE
GROUP BY
    c.nombre_categoria,
    date_trunc('month', ped.fecha_pedido)
ORDER BY
    mes,
    facturado DESC;

-- RANKING DE USUARIOS POR GASTO ACUMULADO
SELECT
    u.id_usuario,
    u.nombre_usuario || ' ' || u.apellido_usuario AS usuario,
    SUM(ped.total_pedido) AS gasto_acumulado,
    RANK() OVER (ORDER BY SUM(ped.total_pedido) DESC) AS puesto
FROM pedido ped
JOIN usuario u
    ON u.id_usuario = ped.usuario_id
WHERE ped.eliminado = FALSE
GROUP BY
    u.id_usuario,
    u.nombre_usuario,
    u.apellido_usuario
ORDER BY puesto;

-- PEDIDOS CUYO TOTAL SUPERA EL PROMEDIO GENERAL
SELECT
    id_pedido,
    total_pedido
FROM pedido
WHERE eliminado = FALSE
  AND total_pedido > (
      SELECT AVG(total_pedido)
      FROM pedido
      WHERE eliminado = FALSE
  )
ORDER BY total_pedido DESC;

-- PRODUCTOS SIN VENTAS
SELECT
    pr.id_producto,
    pr.nombre_producto
FROM producto pr
LEFT JOIN detalle_pedido dp
    ON dp.producto_id = pr.id_producto
   AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE
  AND dp.id_detallepedido IS NULL
ORDER BY pr.id_producto;