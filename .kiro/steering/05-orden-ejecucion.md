# Food Store — Orden de Ejecución y Dependencias entre Scripts

## Orden obligatorio

```
1. schema.sql
2. objects.sql
3. data.sql
4. queries.sql        (solo consultas/demostraciones; no modifica estructura)
5. transacciones.sql  (solo escenarios de prueba; no modifica estructura)
```

Este orden está documentado explícitamente en los encabezados de los archivos:

- `data.sql`: `-- Orden de ejecución recomendado: schema.sql -> objects.sql -> data.sql`
- `queries.sql`: `-- Requiere: schema.sql, objects.sql y data.sql ya ejecutados en ese orden.`
- `transacciones.sql`: `-- Requiere: 1. schema.sql / 2. objects.sql / 3. data.sql`

---

## Dependencias detalladas

### `schema.sql` (sin dependencias)

Crea los fundamentos de la base de datos:
- Tipos ENUM: `rol`, `estado_pedido`, `forma_pago`
- Tablas: `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`
- Índices: `idx_producto_categoria_id`, `idx_pedido_usuario_id`, `idx_producto_nombre_vigente`

**Debe ejecutarse primero.** No depende de ningún otro script.

---

### `objects.sql` (depende de schema.sql)

Crea todos los objetos que referencian las tablas definidas en `schema.sql`:

| Objeto               | Tipo           | Depende de                                  |
|----------------------|----------------|---------------------------------------------|
| `v_categorias_vigentes` | Vista       | tabla `categoria`                           |
| `v_productos_vigentes`  | Vista       | tablas `producto`, `categoria`              |
| `v_pedidos_resumen`     | Vista       | tablas `pedido`, `usuario`                  |
| `v_pedido_detalle`      | Vista       | tablas `detalle_pedido`, `producto`         |
| `calcular_total_pedido` | Función     | tabla `detalle_pedido`                      |
| `fn_set_subtotal`       | Función trigger | tabla `producto`                        |
| `trg_subtotal`          | Trigger     | función `fn_set_subtotal`, tabla `detalle_pedido` |
| `fn_recalcular_total`   | Función trigger | función `calcular_total_pedido`, tabla `pedido` |
| `trg_total_ins`         | Trigger     | función `fn_recalcular_total`, tabla `detalle_pedido` |
| `trg_total_upd`         | Trigger     | función `fn_recalcular_total`, tabla `detalle_pedido` |
| `fn_soft_delete`        | Función trigger | tablas `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido` |
| `trg_soft_delete_*`     | Triggers (×5)| función `fn_soft_delete`, cada tabla respectiva |
| `sp_crear_pedido`       | Procedimiento | tablas `usuario`, `pedido`, `detalle_pedido`, `producto`; tipo ENUM `forma_pago` |

**Debe ejecutarse después de `schema.sql` y antes de `data.sql`**, porque `data.sql` inserta datos que activan los triggers definidos aquí.

---

### `data.sql` (depende de schema.sql + objects.sql)

Inserta datos de ejemplo en el siguiente orden (respetando FK):

```
1. categoria      (sin dependencias de FK)
2. producto       (FK → categoria)
3. usuario        (sin dependencias de FK)
4. pedido         (FK → usuario)
5. detalle_pedido (FK → pedido, producto)
```

Toda la inserción está envuelta en una única transacción (`BEGIN; ... COMMIT;`).

Incluye:
- 5 categorías activas + 1 dada de baja (para probar soft delete).
- 13 productos activos + 1 eliminado + 1 sin stock/no disponible.
- 4 usuarios activos + 1 eliminado.
- 5 pedidos (CONFIRMADO, TERMINADO, PENDIENTE, CANCELADO, CONFIRMADO) + el quinto dado de baja junto con sus detalles.

---

### `queries.sql` (depende de schema.sql + objects.sql + data.sql)

Contiene únicamente consultas DML de ejemplo organizadas por épica:

- **Épica 1:** Gestión de Categorías (HU-CAT-01 a HU-CAT-04)
- **Épica 2:** Gestión de Productos (HU-PROD-01 a HU-PROD-04)
- **Épica 3:** Gestión de Usuarios (HU-USR-01 a HU-USR-04)
- **Épica 4:** Gestión de Pedidos y Detalles (HU-PED-01 a HU-PED-04)
- **Consultas analíticas adicionales** (A a E): top productos, facturación por categoría/mes, ranking de usuarios, pedidos sobre el promedio, productos sin ventas.

> Algunas sentencias en `queries.sql` modifican datos (INSERT, UPDATE). Ejecutar con cuidado si la base ya tiene datos de producción o de otras pruebas.

---

### `transacciones.sql` (depende de schema.sql + objects.sql + data.sql)

Contiene escenarios de prueba de ACID y concurrencia. No modifica la estructura.

> Los escenarios de **concurrencia** (sección "SESIÓN A / SESIÓN B") requieren **dos conexiones simultáneas** a la misma base de datos y no pueden ejecutarse en una única sesión secuencial.

---

## Resumen visual de dependencias

```
schema.sql
    └── objects.sql
            └── data.sql
                    ├── queries.sql
                    └── transacciones.sql
```

---

## Observaciones sobre inconsistencias detectadas

Las siguientes observaciones se documentan únicamente como referencia. **No se modificó ningún archivo.**

1. **Comentario en `objects.sql` (`sp_crear_pedido`):** Hay dos comentarios inline que dicen `-- corregido: id -> id_pedido` e `-- corregido: id -> id_usuario`, lo que sugiere que el procedimiento fue editado durante el desarrollo para corregir nombres de columna incorrectos. El código actual usa los nombres correctos.

2. **`trg_total_del` ausente:** No existe un trigger que recalcule `total_pedido` cuando se hace un DELETE físico en `detalle_pedido`. Sin embargo, dado que el soft delete intercepta todos los DELETEs físicos convirtiéndolos en UPDATEs, y los UPDATEs sí disparan `trg_total_upd`, el total se recalcula correctamente en el flujo normal.

3. **`v_pedidos_resumen` no filtra `usuario.eliminado`:** La vista muestra pedidos de usuarios eliminados si esos pedidos no están eliminados. Esto puede ser un comportamiento intencional (preservar historial de pedidos de usuarios dados de baja).

4. **`v_pedido_detalle` no filtra `producto.eliminado`:** La vista puede mostrar nombres de productos que fueron dados de baja lógicamente si el detalle en sí no está eliminado.

5. **`data.sql` inserta IDs de pedidos y detalles con valores fijos** (ej.: `WHERE id_pedido = 5`). En una base limpia recién poblada los IDs coinciden, pero si se ejecuta `data.sql` varias veces o sobre una base con datos previos, los IDs podrían no coincidir.
