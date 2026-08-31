-- restricciones_negocio.sql
-- TPI Base de Datos - Food Store
-- Reglas de negocio implementadas con constraints y triggers
--
-- Requiere: schema.sql, objects.sql y data.sql ya ejecutados en ese orden.
--

-- 
-- 1. Transición de estado de pedido válida
--

CREATE OR REPLACE FUNCTION fn_validar_transicion_estado()
RETURNS TRIGGER AS $$
BEGIN
    -- Permite un UPDATE "sin cambios" (mismo estado)
    IF NEW.estado_pedido = OLD.estado_pedido THEN
        RETURN NEW;
    END IF;

    -- Transiciones válidas:
    --   PENDIENTE -> CONFIRMADO
    --   CONFIRMADO -> TERMINADO
    --   PENDIENTE -> CANCELADO
    --   CONFIRMADO -> CANCELADO
    IF NOT (
        (OLD.estado_pedido = 'PENDIENTE'  AND NEW.estado_pedido = 'CONFIRMADO') OR
        (OLD.estado_pedido = 'CONFIRMADO' AND NEW.estado_pedido = 'TERMINADO') OR
        (OLD.estado_pedido = 'PENDIENTE'  AND NEW.estado_pedido = 'CANCELADO') OR
        (OLD.estado_pedido = 'CONFIRMADO' AND NEW.estado_pedido = 'CANCELADO')
    ) THEN
        RAISE EXCEPTION 'Transición de estado de pedido inválida: % -> %', OLD.estado_pedido, NEW.estado_pedido;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_transicion_estado
BEFORE UPDATE OF estado_pedido ON pedido
FOR EACH ROW EXECUTE FUNCTION fn_validar_transicion_estado();

-- 
-- 2. Fecha de pedido no futura
--

ALTER TABLE pedido
    ADD CONSTRAINT chk_fecha_pedido_no_futura
    CHECK (fecha_pedido <= CURRENT_DATE);

-- 
-- 3. No asociar productos a categorías dadas de baja
--

CREATE OR REPLACE FUNCTION fn_validar_categoria_producto()
RETURNS TRIGGER AS $$
BEGIN
    -- La FK solo garantiza que el id exista; acá se valida además el flag eliminado
    IF NOT EXISTS (SELECT 1
                   FROM   categoria
                   WHERE  id_categoria = NEW.categoria_id AND eliminado = FALSE) THEN
        RAISE EXCEPTION 'Categoría % inexistente o dada de baja', NEW.categoria_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_categoria_producto
BEFORE INSERT OR UPDATE OF categoria_id ON producto
FOR EACH ROW EXECUTE FUNCTION fn_validar_categoria_producto();


COMMIT;
--
-- Pruebas (un BEGIN;...ROLLBACK; por caso, porque un RAISE EXCEPTION aborta la transacción)
--
-- Datos de data.sql asumidos:
--   pedido 1 = CONFIRMADO, pedido 3 = PENDIENTE, pedido 4 = CANCELADO, pedido 2 = TERMINADO
--   categoria 1 vigente, categoria 6 eliminada
--   usuario 2 existe y está vigente
--

-- Esperado: ERROR 'Transición de estado de pedido inválida: CONFIRMADO -> PENDIENTE'
BEGIN;
    UPDATE pedido SET estado_pedido = 'PENDIENTE' WHERE id_pedido = 1;
ROLLBACK;

-- Esperado: ERROR 'Transición de estado de pedido inválida: CANCELADO -> PENDIENTE' (estado final)
BEGIN;
    UPDATE pedido SET estado_pedido = 'PENDIENTE' WHERE id_pedido = 4;
ROLLBACK;

-- Esperado: OK (PENDIENTE -> CONFIRMADO, transición válida)
BEGIN;
    UPDATE pedido SET estado_pedido = 'CONFIRMADO' WHERE id_pedido = 3;
ROLLBACK;

-- Esperado: OK (CONFIRMADO -> CANCELADO, transición válida)
BEGIN;
    UPDATE pedido SET estado_pedido = 'CANCELADO' WHERE id_pedido = 1;
ROLLBACK;

-- Esperado: ERROR 'check constraint chk_fecha_pedido_no_futura' (fecha futura)
BEGIN;
    INSERT INTO pedido (fecha_pedido, total_pedido, forma_pago, usuario_id)
    VALUES (CURRENT_DATE + 1, 100.00, 'EFECTIVO', 2);
ROLLBACK;

-- Esperado: OK (fecha de hoy, insert + rollback)
BEGIN;
    INSERT INTO pedido (fecha_pedido, total_pedido, forma_pago, usuario_id)
    VALUES (CURRENT_DATE, 100.00, 'EFECTIVO', 2);
ROLLBACK;

-- Esperado: ERROR 'Categoría 6 inexistente o dada de baja'
BEGIN;
    INSERT INTO producto (nombre_producto, precio_producto, stock_producto, disponible, categoria_id)
    VALUES ('Producto de prueba', 100.00, 5, TRUE, 6);
ROLLBACK;

-- Esperado: OK (categoría 1 vigente, insert + rollback)
BEGIN;
    INSERT INTO producto (nombre_producto, precio_producto, stock_producto, disponible, categoria_id)
    VALUES ('Producto de prueba', 100.00, 5, TRUE, 1);
ROLLBACK;
