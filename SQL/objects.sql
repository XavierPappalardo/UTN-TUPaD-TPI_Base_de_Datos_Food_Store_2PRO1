-- ============================================================
-- OBJECTS.SQL - FOOD STORE
-- PostgreSQL 16+
-- ============================================================

-- ------------------------------------------------------------
-- 1. VISTAS OBLIGATORIAS
-- ------------------------------------------------------------

-- Categorías Vigentes
CREATE OR REPLACE VIEW v_categorias_vigentes AS
SELECT
    id_categoria,
    nombre_categoria,
    descripcion_categoria
FROM categoria
WHERE eliminado = FALSE;

-- Productos Vigentes
CREATE OR REPLACE VIEW v_productos_vigentes AS
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
  AND c.eliminado = FALSE;

-- Resumen de Pedidos
CREATE OR REPLACE VIEW v_pedidos_resumen AS
SELECT
    ped.id_pedido,
    u.nombre_usuario || ' ' || u.apellido_usuario AS usuario,
    ped.fecha_pedido,
    ped.estado_pedido,
    ped.forma_pago,
    ped.total_pedido
FROM pedido ped
JOIN usuario u
    ON u.id_usuario = ped.usuario_id
WHERE ped.eliminado = FALSE;

-- Detalle de Pedidos
CREATE OR REPLACE VIEW v_pedido_detalle AS
SELECT
    dp.pedido_id,
    pr.nombre_producto AS producto,
    dp.cantidad_detallepedido,
    dp.precio_unitario,
    dp.subtotal_detallepedido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id_producto = dp.producto_id
WHERE dp.eliminado = FALSE;


-- ------------------------------------------------------------
-- 2. FUNCIÓN DE CÁLCULO DE TOTAL
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION calcular_total_pedido(
    p_pedido_id BIGINT
)
RETURNS NUMERIC(12,2)
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        SUM(subtotal_detallepedido),
        0.00
    )
    FROM detalle_pedido
    WHERE pedido_id = p_pedido_id
      AND eliminado = FALSE;
$$;


-- ------------------------------------------------------------
-- 3. TRIGGER SUBTOTAL AUTOMÁTICO
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_set_subtotal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_precio_producto NUMERIC(10,2);
BEGIN
    -- Si no se proporcionó el precio unitario, se busca el actual del producto
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio_producto
        INTO v_precio_producto
        FROM producto
        WHERE id_producto = NEW.producto_id
          AND eliminado = FALSE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % inexistente o eliminado', NEW.producto_id;
        END IF;

        NEW.precio_unitario := v_precio_producto;
    END IF;

    -- Se calcula/asegura el subtotal
    NEW.subtotal_detallepedido := NEW.cantidad_detallepedido * NEW.precio_unitario;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subtotal ON detalle_pedido;
CREATE TRIGGER trg_subtotal
BEFORE INSERT OR UPDATE
ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_set_subtotal();


-- ------------------------------------------------------------
-- 4. TRIGGERS DE ACTUALIZACIÓN DE TOTAL DE PEDIDO
-- ------------------------------------------------------------

-- AFTER INSERT
CREATE OR REPLACE FUNCTION fn_recalcular_total()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pedido p
    SET total_pedido = calcular_total_pedido(p.id_pedido)
    WHERE p.id_pedido IN (
        SELECT pedido_id FROM afectados
    );
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_total_ins ON detalle_pedido;
CREATE TRIGGER trg_total_ins
AFTER INSERT
ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total();

-- AFTER UPDATE
CREATE OR REPLACE FUNCTION fn_recalcular_total_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pedido p
    SET total_pedido = calcular_total_pedido(p.id_pedido)
    WHERE p.id_pedido IN (
        SELECT pedido_id FROM afectados_nuevos
        UNION
        SELECT pedido_id FROM afectados_viejos
    );
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_total_upd ON detalle_pedido;
CREATE TRIGGER trg_total_upd
AFTER UPDATE
ON detalle_pedido
REFERENCING
    OLD TABLE AS afectados_viejos
    NEW TABLE AS afectados_nuevos
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total_update();

-- AFTER DELETE
CREATE OR REPLACE FUNCTION fn_recalcular_total_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pedido p
    SET total_pedido = calcular_total_pedido(p.id_pedido)
    WHERE p.id_pedido IN (
        SELECT pedido_id FROM afectados_viejos
    );
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_total_del ON detalle_pedido;
CREATE TRIGGER trg_total_del
AFTER DELETE
ON detalle_pedido
REFERENCING OLD TABLE AS afectados_viejos
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total_delete();


-- ------------------------------------------------------------
-- 5. PROCEDIMIENTO TRANSACCIONAL CREAR PEDIDO
-- ------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    IN p_usuario_id BIGINT,
    IN p_forma_pago forma_pago,
    IN p_items JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pedido_id BIGINT;
    v_item JSONB;
    v_producto_id BIGINT;
    v_cantidad INTEGER;
    v_stock INTEGER;
    v_disponible BOOLEAN;
    v_precio_actual NUMERIC(10,2);
BEGIN
    -- Validar existencia de Usuario activo
    IF NOT EXISTS (
        SELECT 1
        FROM usuario
        WHERE id_usuario = p_usuario_id
          AND eliminado = FALSE
    ) THEN
        RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_usuario_id;
    END IF;

    -- Crear cabecera del pedido
    INSERT INTO pedido (
        usuario_id,
        forma_pago
    )
    VALUES (
        p_usuario_id,
        p_forma_pago
    )
    RETURNING id_pedido INTO v_pedido_id;

    -- Iterar sobre items en formato JSONB
    FOR v_item IN
        SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_producto_id := (v_item ->> 'producto_id')::BIGINT;
        v_cantidad    := (v_item ->> 'cantidad')::INTEGER;

        -- Validar cantidad recibida
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RAISE EXCEPTION 'La cantidad del producto % debe ser mayor a cero', v_producto_id;
        END IF;

        -- Bloquear fila del producto para evitar concurrencia
        SELECT
            stock_producto,
            disponible,
            precio_producto
        INTO
            v_stock,
            v_disponible,
            v_precio_actual
        FROM producto
        WHERE id_producto = v_producto_id
          AND eliminado = FALSE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % inexistente o eliminado', v_producto_id;
        END IF;

        IF NOT v_disponible THEN
            RAISE EXCEPTION 'Producto % no disponible', v_producto_id;
        END IF;

        IF v_stock < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para producto %. Disponible: %, solicitado: %',
                            v_producto_id, v_stock, v_cantidad;
        END IF;

        -- Insertar detalle (El trigger fn_set_subtotal calculará automáticamente el subtotal)
        INSERT INTO detalle_pedido (
            pedido_id,
            producto_id,
            cantidad_detallepedido,
            precio_unitario
        )
        VALUES (
            v_pedido_id,
            v_producto_id,
            v_cantidad,
            v_precio_actual
        );

        -- Descontar Stock
        UPDATE producto
        SET stock_producto = stock_producto - v_cantidad
        WHERE id_producto = v_producto_id;

    END LOOP;
END;
$$;