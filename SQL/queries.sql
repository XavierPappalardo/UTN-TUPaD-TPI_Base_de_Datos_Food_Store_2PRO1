-- queries.sql
-- TPI Base de Datos - Food Store
-- 
-- Requiere: schema.sql, objects.sql y data.sql ya ejecutados en ese orden.

--
-- ÉPICA 1 — Gestión de Categorías
-- 

-- HU-CAT-01 — Listar categorías vigentes
SELECT id_categoria      AS id,
       nombre_categoria  AS nombre,
       descripcion_categoria AS descripcion
FROM   categoria
WHERE  eliminado = FALSE
ORDER  BY id_categoria;

-- HU-CAT-02 — Crear categoría
INSERT INTO categoria(nombre_categoria, descripcion_categoria)
VALUES ('Sushi', 'Rolls y piezas de sushi')
RETURNING id_categoria;   -- UNIQUE(nombre_categoria) lanza error si el nombre ya existe

-- HU-CAT-03 — Editar categoría
UPDATE categoria
SET    nombre_categoria = 'Pizzas Artesanales', descripcion_categoria = 'Catálogo ampliado'
WHERE  id_categoria = 1 AND eliminado = FALSE;   -- 0 filas si no existe/está eliminada

-- HU-CAT-04 — Eliminar categoría (baja lógica)
UPDATE categoria
SET    eliminado = TRUE
WHERE  id_categoria = 6 AND eliminado = FALSE;   

--
-- ÉPICA 2 — Gestión de Productos
--

-- HU-PROD-01 — Listar productos con stock y categoría
SELECT p.id_producto AS id, p.nombre_producto AS nombre,
       p.precio_producto AS precio, p.stock_producto AS stock,
       c.nombre_categoria AS categoria
FROM   producto p
JOIN   categoria c ON c.id_categoria = p.categoria_id
WHERE  p.eliminado = FALSE
-- AND  p.categoria_id = 1            -- filtro opcional por categoría
ORDER  BY p.id_producto;

-- HU-PROD-02 — Crear producto asociado a una categoría vigente
INSERT INTO producto(nombre_producto, descripcion_producto, precio_producto,
                      stock_producto, imagen_producto, disponible, categoria_id)
SELECT 'Pizza especial de la casa', 'Receta de la casa', 5500.00, 8, NULL, TRUE, c.id_categoria
FROM   categoria c
WHERE  c.id_categoria = 1 AND c.eliminado = FALSE   -- garantiza categoría vigente
RETURNING id_producto;

-- HU-PROD-03 — Editar producto (UPDATE parcial con COALESCE)
UPDATE producto
SET    precio_producto = COALESCE(2000.00, precio_producto),  -- NULL conserva el valor actual
       stock_producto  = COALESCE(NULL,    stock_producto)
WHERE  id_producto = 1 AND eliminado = FALSE;

-- HU-PROD-04 — Eliminar producto (baja lógica)
UPDATE producto
SET    eliminado = TRUE
WHERE  id_producto = 6 AND eliminado = FALSE; 

--
-- ÉPICA 3 — Gestión de Usuarios
-- 

-- HU-USR-01 — Listar usuarios vigentes

SELECT id_usuario AS id, nombre_usuario AS nombre, apellido_usuario AS apellido,
       mail_usuario AS mail, rol
FROM   usuario
WHERE  eliminado = FALSE
ORDER  BY id_usuario;

-- HU-USR-02 — Crear usuario
INSERT INTO usuario(nombre_usuario, apellido_usuario, mail_usuario, celular_usuario, contrasena_usuario)
VALUES ('Lucía', 'Fernández', 'lucia@x.com', '2615551234', 'hash_lucia')
RETURNING id_usuario;   -- UNIQUE(mail_usuario) lanza error si el mail ya existe

-- HU-USR-03 — Editar usuario
UPDATE usuario
SET    celular_usuario = '2617654321'
WHERE  id_usuario = 2 AND eliminado = FALSE; 

-- HU-USR-04 — Eliminar usuario (baja lógica)
UPDATE usuario
SET    eliminado = TRUE
WHERE  id_usuario = 4 AND eliminado = FALSE; 

-- 
-- ÉPICA 4 — Gestión de Pedidos y Detalles
-- 

-- HU-PED-01 — Listar pedidos (usa la vista v_pedidos_resumen)
SELECT id, usuario, fecha, estado, forma_pago, total
FROM   v_pedidos_resumen
-- 
ORDER  BY id;

-- HU-PED-02 — Crear pedido con detalles
CALL sp_crear_pedido(
     2,                 
     'EFECTIVO',
     '[{"producto_id":1,"cantidad":1},
       {"producto_id":9,"cantidad":2}]'::jsonb);

-- HU-PED-03 — Actualizar estado / forma de pago
UPDATE pedido
SET    estado_pedido = 'CONFIRMADO', forma_pago = 'TARJETA'
WHERE  id_pedido = 3 AND eliminado = FALSE;

-- HU-PED-04 — Eliminar pedido (baja lógica, pedido + detalles en una transacción)
BEGIN;
  UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 4;
  UPDATE pedido         SET eliminado = TRUE WHERE id_pedido = 4;
COMMIT;

--
-- Consultas analíticas adicionales
-- 

-- A) Top 5 productos más vendidos
SELECT pr.id_producto AS id, pr.nombre_producto AS nombre,
       SUM(dp.cantidad_detallepedido) AS unidades
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id_producto = dp.producto_id
WHERE  dp.eliminado = FALSE
GROUP  BY pr.id_producto, pr.nombre_producto
ORDER  BY unidades DESC
LIMIT  5;

-- B) Facturación por categoría y por mes
SELECT c.nombre_categoria AS categoria,
       date_trunc('month', ped.fecha_pedido) AS mes,
       SUM(dp.subtotal_detallepedido) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id_pedido = dp.pedido_id AND ped.eliminado = FALSE
JOIN   producto pr  ON pr.id_producto = dp.producto_id
JOIN   categoria c  ON c.id_categoria = pr.categoria_id
WHERE  dp.eliminado = FALSE
GROUP  BY c.nombre_categoria, date_trunc('month', ped.fecha_pedido)
ORDER  BY mes, facturado DESC;

-- C) Ranking de usuarios por gasto acumulado
SELECT u.id_usuario AS id, u.nombre_usuario || ' ' || u.apellido_usuario AS usuario,
       SUM(ped.total_pedido) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total_pedido) DESC) AS puesto
FROM   pedido ped
JOIN   usuario u ON u.id_usuario = ped.usuario_id
WHERE  ped.eliminado = FALSE
GROUP  BY u.id_usuario, u.nombre_usuario, u.apellido_usuario
ORDER  BY puesto;

-- D) Pedidos cuyo total supera el promedio general
SELECT id_pedido AS id, total_pedido AS total
FROM   pedido
WHERE  eliminado = FALSE
  AND  total_pedido > (SELECT AVG(total_pedido) FROM pedido WHERE eliminado = FALSE)
ORDER  BY total_pedido DESC;

-- E) Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id_producto AS id, pr.nombre_producto AS nombre
FROM   producto pr
LEFT   JOIN detalle_pedido dp
       ON dp.producto_id = pr.id_producto AND dp.eliminado = FALSE
WHERE  pr.eliminado = FALSE
  AND  dp.id_detallepedido IS NULL
ORDER  BY pr.id_producto;