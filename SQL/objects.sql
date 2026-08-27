-- objects.sql
-- TPI Base de Datos - Food Store

-- 
-- Vistas obligatorias
-- 

CREATE VIEW v_categorias_vigentes AS
SELECT id_categoria          AS id,
       nombre_categoria      AS nombre,
       descripcion_categoria AS descripcion
FROM   categoria
WHERE  eliminado = FALSE;

CREATE VIEW v_productos_vigentes AS
SELECT p.id_producto     AS id,
       p.nombre_producto AS nombre,
       p.precio_producto AS precio,
       p.stock_producto  AS stock,
       c.nombre_categoria AS categoria
FROM   producto p
JOIN   categoria c ON c.id_categoria = p.categoria_id
WHERE  p.eliminado = FALSE AND c.eliminado = FALSE;

CREATE VIEW v_pedidos_resumen AS
SELECT  ped.id_pedido AS id,
        u.nombre_usuario || ' ' || u.apellido_usuario AS usuario,
        ped.fecha_pedido  AS fecha,
        ped.estado_pedido AS estado,
        ped.forma_pago,
        ped.total_pedido  AS total
FROM    pedido ped
JOIN    usuario u ON u.id_usuario = ped.usuario_id
WHERE   ped.eliminado = FALSE;

CREATE VIEW v_pedido_detalle AS
SELECT  dp.pedido_id,
        pr.nombre_producto AS producto,
        dp.cantidad_detallepedido AS cantidad,
        dp.precio_unitario,
        dp.subtotal_detallepedido AS subtotal
FROM    detalle_pedido dp
JOIN    producto pr ON pr.id_producto = dp.producto_id
WHERE   dp.eliminado = FALSE;

--
-- Función de cálculo de total (analogía con Calculable)
-- 

CREATE OR REPLACE FUNCTION calcular_total_pedido(p_pedido_id BIGINT)
RETURNS NUMERIC(12,2) AS $$
    SELECT COALESCE(SUM(subtotal_detallepedido), 0)  
    FROM   detalle_pedido
    WHERE  pedido_id = p_pedido_id AND eliminado = FALSE;
$$ LANGUAGE sql STABLE;

-- 
-- Trigger: subtotal automático
-- 

CREATE OR REPLACE FUNCTION fn_set_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    -- Si no se pasó precio_unitario, se congela el precio actual del producto
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio_producto INTO NEW.precio_unitario  
        FROM producto WHERE id_producto = NEW.producto_id; 
    END IF;
    NEW.subtotal_detallepedido := NEW.cantidad_detallepedido * NEW.precio_unitario; 
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_subtotal
BEFORE INSERT OR UPDATE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_set_subtotal();

-- 
-- Trigger: total del pedido automático (AFTER ... FOR EACH STATEMENT)
-- 

CREATE OR REPLACE FUNCTION fn_recalcular_total()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalcula el total de cada pedido afectado
    UPDATE pedido p
    SET    total_pedido = calcular_total_pedido(p.id_pedido)  
    WHERE  p.id_pedido IN (SELECT pedido_id FROM afectados);   
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Un trigger por evento: la transition table no admite declarar varios eventos en un mismo CREATE TRIGGER
CREATE TRIGGER trg_total_ins
AFTER INSERT ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();

CREATE TRIGGER trg_total_upd
AFTER UPDATE ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();

--
-- Trigger genérico: soft delete (DELETE físico -> UPDATE eliminado = TRUE)
--

CREATE OR REPLACE FUNCTION fn_soft_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_pk_column TEXT;
    v_pk_value  BIGINT;
BEGIN
    v_pk_column := CASE TG_TABLE_NAME
        WHEN 'categoria'      THEN 'id_categoria'
        WHEN 'producto'       THEN 'id_producto'
        WHEN 'usuario'        THEN 'id_usuario'
        WHEN 'pedido'         THEN 'id_pedido'
        WHEN 'detalle_pedido' THEN 'id_detallepedido'
        ELSE NULL
    END;

    IF v_pk_column IS NULL THEN
        RAISE EXCEPTION 'fn_soft_delete: tabla % no soportada', TG_TABLE_NAME;
    END IF;

    v_pk_value := (to_jsonb(OLD) ->> v_pk_column)::BIGINT;

    EXECUTE format(
        'UPDATE %I SET eliminado = TRUE WHERE %I = $1 AND eliminado = FALSE',
        TG_TABLE_NAME, v_pk_column
    ) USING v_pk_value;

    RETURN NULL;  
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_soft_delete_categoria
BEFORE DELETE ON categoria
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete();

CREATE TRIGGER trg_soft_delete_producto
BEFORE DELETE ON producto
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete();

CREATE TRIGGER trg_soft_delete_usuario
BEFORE DELETE ON usuario
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete();

CREATE TRIGGER trg_soft_delete_pedido
BEFORE DELETE ON pedido
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete();

CREATE TRIGGER trg_soft_delete_detalle_pedido
BEFORE DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_soft_delete();

-- 
-- Procedimiento transaccional: alta de pedido + detalles
-- 

CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_usuario_id BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB   -- [{"producto_id":1,"cantidad":2}, ...]
) AS $$
DECLARE
    v_pedido_id   BIGINT;
    v_item        JSONB;
    v_producto_id BIGINT;
    v_cantidad    INTEGER;
    v_stock       INTEGER;
    v_disponible  BOOLEAN;
BEGIN
    -- El usuario debe existir y no estar eliminado
    IF NOT EXISTS (SELECT 1 FROM usuario
                  WHERE id_usuario = p_usuario_id AND eliminado = FALSE) THEN  -- corregido: id -> id_usuario
        RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_usuario_id;
    END IF;

    INSERT INTO pedido(usuario_id, forma_pago)
    VALUES (p_usuario_id, p_forma_pago)
    RETURNING id_pedido INTO v_pedido_id;   -- corregido: id -> id_pedido

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_producto_id := (v_item->>'producto_id')::BIGINT;
        v_cantidad    := (v_item->>'cantidad')::INTEGER;

        -- Bloquea la fila del producto para evitar sobreventa concurrente
        SELECT stock_producto, disponible INTO v_stock, v_disponible  
        FROM producto WHERE id_producto = v_producto_id AND eliminado = FALSE  
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % inexistente o eliminado', v_producto_id;
        END IF;
        IF NOT v_disponible THEN
            RAISE EXCEPTION 'Producto % no disponible', v_producto_id;
        END IF;
        IF v_stock < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente (producto %): hay %, se piden %',
                            v_producto_id, v_stock, v_cantidad;
        END IF;

        INSERT INTO detalle_pedido(pedido_id, producto_id, cantidad_detallepedido) 
        VALUES (v_pedido_id, v_producto_id, v_cantidad);

        -- Descuenta stock dentro de la misma transacción
        UPDATE producto SET stock_producto = stock_producto - v_cantidad  
        WHERE id_producto = v_producto_id;  
    END LOOP;
    -- Si alguna inserción falla, toda la transacción se revierte (rollback).
END;
$$ LANGUAGE plpgsql;