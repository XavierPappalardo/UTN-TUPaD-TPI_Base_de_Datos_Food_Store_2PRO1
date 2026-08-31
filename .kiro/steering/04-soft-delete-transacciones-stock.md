# Food Store — Soft Delete, Transacciones y Manejo de Stock

---

## Soft Delete

### Mecanismo

Todas las tablas tienen una columna `eliminado BOOLEAN NOT NULL DEFAULT FALSE`.  
Un registro "eliminado" es aquel con `eliminado = TRUE`; nunca se borra físicamente.

### Cómo se aplica

**Opción 1 — UPDATE explícito (método principal en queries.sql y data.sql):**

```sql
UPDATE <tabla> SET eliminado = TRUE WHERE <pk> = <valor> AND eliminado = FALSE;
```

La cláusula `AND eliminado = FALSE` evita re-eliminar un registro ya dado de baja (devuelve 0 filas en lugar de error).

**Opción 2 — Trigger BEFORE DELETE (mecanismo de seguridad en objects.sql):**

Cualquier `DELETE FROM <tabla> WHERE ...` es interceptado por el trigger `trg_soft_delete_<tabla>`, que lo convierte en un `UPDATE SET eliminado = TRUE`. El DELETE físico nunca se ejecuta.

### Filtrado en consultas

Todas las consultas y vistas filtran registros activos con:

```sql
WHERE eliminado = FALSE
```

Nunca se usa `eliminado <> TRUE`, `NOT eliminado`, ni `eliminado IS FALSE`.

### Baja de pedidos (caso especial — doble UPDATE)

Al dar de baja un pedido se deben eliminar también sus detalles en la misma transacción:

```sql
BEGIN;
  UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = <id>;
  UPDATE pedido         SET eliminado = TRUE WHERE id_pedido = <id>;
COMMIT;
```

Este patrón está presente tanto en `queries.sql` (HU-PED-04) como en `data.sql`.

### Observación sobre el trigger de soft delete y los totales

Cuando se da de baja un detalle vía `UPDATE eliminado = TRUE`, el trigger `trg_total_upd` se dispara y recalcula el total del pedido. Esto es consistente.  
Sin embargo, si se usa el trigger de soft delete (DELETE físico interceptado), la función `fn_soft_delete` ejecuta un `UPDATE` interno, lo que también dispara `trg_total_upd`.

---

## Transacciones

### Principios

- El procedimiento `sp_crear_pedido` es implícitamente transaccional (PL/pgSQL): cualquier falla hace rollback completo.
- Las operaciones manuales críticas (como dar de baja un pedido con sus detalles) se envuelven explícitamente en `BEGIN; ... COMMIT;`.
- El archivo `data.sql` completo está envuelto en una única transacción (`BEGIN; ... COMMIT;`).

### Escenario de atomicidad documentado

`transacciones.sql` contiene los siguientes escenarios de prueba:

1. **Atomicidad con producto inexistente:** `sp_crear_pedido` con `producto_id = 999999` → ROLLBACK; el contador de pedidos no aumenta.
2. **Atomicidad con cantidad inválida:** `sp_crear_pedido` con `cantidad = 0` → ROLLBACK; la restricción `CHECK (cantidad_detallepedido > 0)` rechaza la inserción.
3. **Transacción manual con ROLLBACK:** INSERT en `categoria` seguido de ROLLBACK; la fila no persiste.
4. **Transacción manual con COMMIT:** INSERT en `categoria` seguido de COMMIT; la fila persiste.
5. **Creación correcta de pedido:** `sp_crear_pedido` con datos válidos → COMMIT; se verifica pedido, detalles y descuento de stock.

### Concurrencia (documentada en transacciones.sql)

Se documenta un escenario de dos sesiones simultáneas:

- **SESIÓN A** hace `SELECT ... FOR UPDATE` sobre `producto WHERE id_producto = 1` y mantiene la transacción abierta.
- **SESIÓN B** intenta el mismo `SELECT ... FOR UPDATE` y queda **bloqueada** hasta que SESIÓN A haga COMMIT.
- Esto garantiza que `sp_crear_pedido` (que usa `FOR UPDATE` internamente) serializa el acceso al stock por producto.

---

## Manejo de Stock

### Dónde se descuenta

El descuento de stock ocurre **dentro de `sp_crear_pedido`**, en la misma transacción que crea el pedido:

```sql
UPDATE producto
SET    stock_producto = stock_producto - v_cantidad
WHERE  id_producto = v_producto_id;
```

### Validaciones previas al descuento

Antes de descontar, `sp_crear_pedido` valida (en orden):

1. Que el producto exista y `eliminado = FALSE`.
2. Que `disponible = TRUE`.
3. Que `stock_producto >= cantidad` solicitada.

Si cualquiera falla, se lanza una excepción y toda la transacción hace rollback (ningún descuento parcial queda aplicado).

### Bloqueo pesimista

El `SELECT ... FOR UPDATE` sobre la fila del producto previene la sobreventa en escenarios concurrentes: ninguna otra transacción puede leer con `FOR UPDATE` ni modificar esa fila hasta que la primera transacción termine.

### Restricción de stock en el esquema

```sql
stock_producto INTEGER NOT NULL DEFAULT 0 CHECK (stock_producto >= 0)
```

El stock nunca puede quedar negativo; la restricción actúa como barrera adicional de integridad.

### Reposición de stock

No existe un procedimiento o función dedicada a reponer stock en el código actual. La reposición se haría directamente con `UPDATE producto SET stock_producto = ... WHERE id_producto = ...`.

---

## Campos de auditoría

Todos los registros tienen `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.  
No existe un campo `updated_at`; las modificaciones no se auditan con timestamp en el esquema actual.
