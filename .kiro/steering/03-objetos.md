# Food Store — Objetos de la Base de Datos

Todos los objetos están definidos en `objects.sql` y dependen de que `schema.sql` ya haya sido ejecutado.

---

## Vistas

### `v_categorias_vigentes`

Expone categorías con `eliminado = FALSE`.  
Columnas proyectadas: `id`, `nombre`, `descripcion`.

```sql
SELECT id_categoria AS id, nombre_categoria AS nombre, descripcion_categoria AS descripcion
FROM   categoria
WHERE  eliminado = FALSE;
```

### `v_productos_vigentes`

Expone productos activos cuya categoría también está activa (doble filtro de soft delete).  
Columnas proyectadas: `id`, `nombre`, `precio`, `stock`, `categoria`.

```sql
FROM producto p
JOIN categoria c ON c.id_categoria = p.categoria_id
WHERE p.eliminado = FALSE AND c.eliminado = FALSE;
```

> Tanto el producto como su categoría deben estar vigentes para aparecer en esta vista.

### `v_pedidos_resumen`

Expone pedidos activos con el nombre completo del usuario.  
Columnas proyectadas: `id`, `usuario` (nombre || ' ' || apellido), `fecha`, `estado`, `forma_pago`, `total`.

```sql
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.usuario_id
WHERE ped.eliminado = FALSE;
```

> No filtra `eliminado` del usuario; solo filtra el pedido.

### `v_pedido_detalle`

Expone detalles activos de pedidos con el nombre del producto.  
Columnas proyectadas: `pedido_id`, `producto`, `cantidad`, `precio_unitario`, `subtotal`.

```sql
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.producto_id
WHERE dp.eliminado = FALSE;
```

---

## Función: `calcular_total_pedido`

```sql
CREATE OR REPLACE FUNCTION calcular_total_pedido(p_pedido_id BIGINT)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE;
```

- Suma `subtotal_detallepedido` de todos los detalles vigentes (`eliminado = FALSE`) de un pedido.
- Devuelve `0` si no hay detalles (via `COALESCE`).
- Marcada `STABLE` (no modifica datos, resultado consistente dentro de la transacción).
- Usada internamente por `fn_recalcular_total`.

---

## Triggers y sus funciones

### `trg_subtotal` → `fn_set_subtotal()`

- **Evento:** `BEFORE INSERT OR UPDATE ON detalle_pedido`
- **Granularidad:** `FOR EACH ROW`
- **Propósito:** Calcula automáticamente `subtotal_detallepedido`.
  - Si `precio_unitario` es NULL, lo obtiene desde `producto.precio_producto` (congela el precio en el momento de la inserción).
  - Siempre calcula: `subtotal = cantidad * precio_unitario`.
- Permite insertar en `detalle_pedido` sin pasar `precio_unitario` ni `subtotal_detallepedido`.

### `trg_total_ins` y `trg_total_upd` → `fn_recalcular_total()`

- **Evento:** `AFTER INSERT` y `AFTER UPDATE ON detalle_pedido` (un trigger por evento)
- **Granularidad:** `FOR EACH STATEMENT` con **transition table** (`REFERENCING NEW TABLE AS afectados`)
- **Propósito:** Recalcula `pedido.total_pedido` para todos los pedidos afectados por la operación.
  - Llama a `calcular_total_pedido(p.id_pedido)` por cada pedido en la transition table.
- Se usan dos triggers separados porque PostgreSQL no permite declarar múltiples eventos (`INSERT OR UPDATE`) cuando se usan transition tables.

> **Importante:** No existe un `trg_total_del`; el recálculo no se dispara al borrar físicamente. El soft delete (UPDATE) sí dispara `trg_total_upd`.

### `trg_soft_delete_*` → `fn_soft_delete()`

Un trigger por tabla, todos con el mismo patrón:

- **Evento:** `BEFORE DELETE ON <tabla>`
- **Granularidad:** `FOR EACH ROW`
- **Propósito:** Intercepta los DELETE físicos y los convierte en `UPDATE ... SET eliminado = TRUE`.
- Usa `TG_TABLE_NAME` y `to_jsonb(OLD)` para detectar la PK dinámicamente.
- Tablas soportadas: `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`.
- Lanza `RAISE EXCEPTION` si se invoca sobre una tabla no listada en el CASE.
- Devuelve `NULL` (cancela el DELETE físico).

Tabla de nombres de triggers de soft delete:

| Trigger                         | Tabla            |
|---------------------------------|------------------|
| `trg_soft_delete_categoria`     | `categoria`      |
| `trg_soft_delete_producto`      | `producto`       |
| `trg_soft_delete_usuario`       | `usuario`        |
| `trg_soft_delete_pedido`        | `pedido`         |
| `trg_soft_delete_detalle_pedido`| `detalle_pedido` |

---

## Procedimiento: `sp_crear_pedido`

```sql
CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_usuario_id BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB    -- [{"producto_id": N, "cantidad": N}, ...]
)
LANGUAGE plpgsql;
```

### Flujo interno

1. Verifica que el usuario exista y no esté eliminado → lanza excepción si falla.
2. Inserta un nuevo `pedido` con `estado_pedido = 'PENDIENTE'` (default) y `total_pedido = 0` (default; se recalcula por trigger).
3. Itera sobre cada elemento del array JSONB `p_items`:
   a. Hace `SELECT ... FOR UPDATE` sobre `producto` para bloquear la fila (previene sobreventa concurrente).
   b. Valida que el producto exista y no esté eliminado.
   c. Valida que `disponible = TRUE`.
   d. Valida que `stock_producto >= cantidad` solicitada.
   e. Inserta en `detalle_pedido` (solo `pedido_id`, `producto_id`, `cantidad_detallepedido`; `precio_unitario` y `subtotal` los calcula el trigger `trg_subtotal`).
   f. Descuenta stock: `UPDATE producto SET stock_producto = stock_producto - v_cantidad`.
4. Si cualquier paso falla, toda la transacción hace rollback automático.

### Invocación

```sql
CALL sp_crear_pedido(
    <usuario_id>,
    '<FORMA_PAGO>',
    '[{"producto_id": N, "cantidad": N}, ...]'::jsonb
);
```

### Mensajes de excepción

| Condición                       | Mensaje                                                                          |
|---------------------------------|----------------------------------------------------------------------------------|
| Usuario inexistente/eliminado   | `'Usuario % inexistente o eliminado'`                                            |
| Producto inexistente/eliminado  | `'Producto % inexistente o eliminado'`                                           |
| Producto no disponible          | `'Producto % no disponible'`                                                     |
| Stock insuficiente              | `'Stock insuficiente (producto %): hay %, se piden %'`                           |
