-- ============================================================
-- INDICES.SQL - FOOD STORE
-- PostgreSQL 16+
-- Semana 5: Plan de indexado justificado con mediciones
-- ============================================================

-- ============================================================
-- A1: Q1 — Pedidos confirmados de un año (642 filas)
-- Consulta: SELECT id_pedido, fecha_pedido, total_pedido
-- FROM pedido WHERE fecha_pedido BETWEEN CURRENT_DATE - 365
-- AND CURRENT_DATE AND estado_pedido = 'CONFIRMADO'
-- AND eliminado = FALSE
-- Índice: idx_pedido_estado_fecha (estado_pedido, fecha_pedido)
-- WHERE eliminado = FALSE
-- Regla B-tree: igualdad antes que rango; parcial por borrado lógico.
-- ANTES: Seq Scan on pedido, filtra 4363 filas, Buffers hit=150,
-- Execution Time mediana 0.258 ms
-- DESPUÉS: Bitmap Heap Scan + Bitmap Index Scan, mediana 0.084 ms (~3x)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pedido_estado_fecha
    ON pedido (estado_pedido, fecha_pedido)
    WHERE eliminado = FALSE;

-- ============================================================
-- A2: Q2 — Top 5 productos más vendidos (agregado sobre 10007 filas)
-- Índice: idx_detalle_producto (producto_id) WHERE eliminado = FALSE
-- ANTES: Seq Scan + Hash Join + HashAggregate, 2.203 ms
-- DESPUÉS: mismo plan, 2.177 ms — SIN cambio esperado
-- El índice se CONSERVA porque su caso de uso es el acceso SELECTIVO (A2b)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_detalle_producto
    ON detalle_pedido (producto_id)
    WHERE eliminado = FALSE;

-- ============================================================
-- A2b: Complementaria selectiva — ventas de un producto (770 filas)
-- Consulta: SELECT pedido_id, cantidad, subtotal
-- FROM detalle_pedido WHERE producto_id = 4 AND eliminado = FALSE
-- ORDER BY pedido_id
-- ANTES: Seq Scan + Sort, 0.629 ms
-- DESPUÉS: Bitmap Heap + Bitmap Index, 0.208 ms (~3x)
-- ============================================================

-- Ya creado arriba como idx_detalle_producto (comparte el mismo índice)

-- ============================================================
-- A3: Q3 — Productos de categoría 1 ordenados por precio (2003 filas)
-- Consulta: WHERE categoria_id = 1 AND eliminado = FALSE ORDER BY precio_producto ASC
-- Índice covering: idx_producto_categoria_precio (categoria_id, precio_producto ASC)
-- INCLUDE (nombre_producto, stock_producto) WHERE eliminado = FALSE
-- SIN índice: Seq Scan + Sort (quicksort 158 kB), 0.485 ms
-- CON índice: Index Scan, nodo Sort eliminado, 0.235 ms (~2x)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_producto_categoria_precio
    ON producto (categoria_id, precio_producto ASC)
    INCLUDE (nombre_producto, stock_producto)
    WHERE eliminado = FALSE;

-- ============================================================
-- ÍNDICES DESCARTADOS (documentados, NO figuran en este archivo)
-- ============================================================
-- Se descartó idx_producto_disponible ON producto (disponible):
-- booleana de cardinalidad 2; sin parcial selectivo el optimizador
-- elige Seq Scan igual y solo encarece INSERT/UPDATE.
-- Se descartó idx_pedido_usuario ON pedido (usuario_id):
-- redundante con idx_pedido_usuario_id de Semana 3.
-- Ver specs/spec_indice_descartado_disponible.md y duia.md fila 3.
