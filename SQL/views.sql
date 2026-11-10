-- ============================================================
-- VIEWS.SQL - FOOD STORE
-- PostgreSQL 16+
-- Semana 5: Vistas y vista materializada (Partes B y C)
-- ============================================================

-- ============================================================
-- PARTE B — VISTAS
-- ============================================================

-- ------------------------------------------------------------
-- B1: v_reporte_productos_categorias
-- Productos vigentes con su categoría (id, nombre, precio,
-- stock + nombre_categoría; filtra p.eliminado y c.eliminado)
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW v_reporte_productos_categorias AS
SELECT
    p.id_producto,
    p.nombre_producto,
    p.precio_producto,
    p.stock_producto,
    c.nombre_categoria
FROM producto p
JOIN categoria c
    ON c.id_categoria = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE;

-- ------------------------------------------------------------
-- B2: v_seguridad_pedidos_usuarios
-- Pedidos con datos del usuario aplicando seguridad.
-- Expone: id_pedido, fecha, estado, total, forma_pago +
-- id/nombre/apellido/mail de usuario.
-- OCULTA: contraseña_usuario y celular.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW v_seguridad_pedidos_usuarios AS
SELECT
    ped.id_pedido,
    ped.fecha_pedido,
    ped.estado_pedido,
    ped.total_pedido,
    ped.forma_pago,
    u.id_usuario,
    u.nombre_usuario,
    u.apellido_usuario,
    u.mail_usuario
FROM pedido ped
JOIN usuario u
    ON ped.usuario_id = u.id_usuario
WHERE ped.eliminado = FALSE
  AND u.eliminado = FALSE;

-- ------------------------------------------------------------
-- B3: v_reporte_detalle_pedido_producto
-- Detalle con nombre del producto (pedido_id, nombre, cantidad,
-- precio unitario, subtotal).
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW v_reporte_detalle_pedido_producto AS
SELECT
    dp.pedido_id,
    pr.nombre_producto,
    dp.cantidad_detallepedido,
    dp.precio_unitario,
    dp.subtotal_detallepedido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id_producto = dp.producto_id
WHERE dp.eliminado = FALSE;

-- ============================================================
-- VERIFICACIÓN DE EQUIVALENCIA (EXCEPT bidireccional)
-- Ver en mediciones.sql §B
-- B1a v EXCEPT manual: 0 filas — B1b manual EXCEPT v: 0 filas
-- B2a: 0 filas — B2b: 0 filas
-- B3a: 0 filas — B3b: 0 filas
-- Seguridad B2: information_schema.columns de la vista NO
-- lista contraseña_usuario (contraseña_expuesta=False)
-- ============================================================

-- ============================================================
-- PARTE C — VISTA MATERIALIZADA
-- ============================================================

-- ------------------------------------------------------------
-- Reporte: facturación por categoría y mes
-- Consulta original (queries.sql B): 4 JOINs + GROUP BY sobre
-- 10007 filas → 125 grupos
-- Objeto: mv_facturacion_categoria_mes
-- Mejora: ~167x (7.027 ms → 0.042 ms)
-- UNIQUE (id_categoria, mes) habilita REFRESH CONCURRENTLY
-- Frecuencia de refresco: Diaria nocturna tras cierre de caja
-- ------------------------------------------------------------

CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.id_categoria,
    c.nombre_categoria,
    date_trunc('month', ped.fecha_pedido) AS mes,
    SUM(dp.subtotal_detallepedido) AS facturacion_total
FROM detalle_pedido dp
JOIN pedido ped
    ON dp.pedido_id = ped.id_pedido
JOIN producto pr
    ON dp.producto_id = pr.id_producto
JOIN categoria c
    ON pr.categoria_id = c.id_categoria
WHERE dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.id_categoria, c.nombre_categoria, date_trunc('month', ped.fecha_pedido)
WITH DATA;

CREATE UNIQUE INDEX idx_mv_facturacion_unico
    ON mv_facturacion_categoria_mes (id_categoria, mes);

-- Para refresco sin bloquear lecturas:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
