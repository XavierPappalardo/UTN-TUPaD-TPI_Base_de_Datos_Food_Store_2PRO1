# Food Store — Convenciones de Nombres y Estilo SQL

## Idioma

Todo el código SQL y los identificadores están en **español**. Los comentarios dentro de los scripts también están en español.

---

## Convenciones de nombres

### Tablas

- Nombres en **singular**, **snake_case**, **minúsculas**.
- Ejemplos: `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`.

### Columnas

Patrón: `<nombre_descriptivo>_<nombre_tabla_abreviado_o_completo>`.

| Tabla            | Patrón de columnas                                                                   |
|------------------|--------------------------------------------------------------------------------------|
| `categoria`      | `id_categoria`, `nombre_categoria`, `descripcion_categoria`                          |
| `producto`       | `id_producto`, `nombre_producto`, `precio_producto`, `stock_producto`, `imagen_producto`, `descripcion_producto` |
| `usuario`        | `id_usuario`, `nombre_usuario`, `apellido_usuario`, `mail_usuario`, `celular_usuario`, `contrasena_usuario` |
| `pedido`         | `id_pedido`, `fecha_pedido`, `estado_pedido`, `total_pedido`, `forma_pago`           |
| `detalle_pedido` | `id_detallepedido`, `cantidad_detallepedido`, `precio_unitario`, `subtotal_detallepedido` |

> **Excepción notable:** La PK de `detalle_pedido` es `id_detallepedido` (sin guion bajo antes de "pedido"), mientras que las demás columnas de esa tabla sí usan `_detallepedido`.

Columnas comunes a **todas** las tablas (sin sufijo de tabla):

| Columna      | Tipo        | Propósito                     |
|--------------|-------------|-------------------------------|
| `eliminado`  | BOOLEAN     | Soft delete (FALSE por defecto)|
| `created_at` | TIMESTAMPTZ | Fecha de creación del registro |

Las FK usan el patrón `<tabla_referenciada>_id` (ej.: `categoria_id`, `usuario_id`, `pedido_id`, `producto_id`).

### Tipos ENUM

Nombres en **minúsculas**, **snake_case**. Valores en **MAYÚSCULAS**.

```
rol           → 'ADMIN', 'USUARIO'
estado_pedido → 'PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO'
forma_pago    → 'TARJETA', 'TRANSFERENCIA', 'EFECTIVO'
```

### Vistas

Prefijo `v_`, nombre descriptivo en minúsculas y snake_case.

```
v_categorias_vigentes
v_productos_vigentes
v_pedidos_resumen
v_pedido_detalle
```

### Funciones (FUNCTION)

Prefijo `fn_`, nombre descriptivo en minúsculas y snake_case.

```
fn_set_subtotal()
fn_recalcular_total()
fn_soft_delete()
calcular_total_pedido(p_pedido_id BIGINT)   ← única función sin prefijo fn_; es pública/calculable
```

### Procedimientos (PROCEDURE)

Prefijo `sp_`, nombre descriptivo en minúsculas y snake_case.

```
sp_crear_pedido(p_usuario_id, p_forma_pago, p_items)
```

### Triggers

Prefijo `trg_`, nombre descriptivo en minúsculas y snake_case.  
Cuando es específico de una tabla, se agrega `_<nombre_tabla>` al final.

```
trg_subtotal
trg_total_ins
trg_total_upd
trg_soft_delete_categoria
trg_soft_delete_producto
trg_soft_delete_usuario
trg_soft_delete_pedido
trg_soft_delete_detalle_pedido
```

### Índices

Prefijo `idx_`, luego tabla y columna(s) involucradas.

```
idx_producto_categoria_id
idx_pedido_usuario_id
idx_producto_nombre_vigente
```

### Parámetros en funciones y procedimientos

Prefijo `p_` para parámetros, `v_` para variables locales.

```sql
p_pedido_id, p_usuario_id, p_forma_pago, p_items
v_pedido_id, v_item, v_producto_id, v_cantidad, v_stock, v_disponible, v_pk_column, v_pk_value
```

---

## Estilo de escritura SQL

- Las **palabras clave SQL** se escriben en **MAYÚSCULAS** (`SELECT`, `INSERT`, `UPDATE`, `CREATE`, `WHERE`, `FROM`, `JOIN`, etc.).
- Los identificadores (tablas, columnas, funciones) van en **minúsculas**.
- Las consultas usan **alias cortos y descriptivos** en minúsculas (`p`, `pr`, `dp`, `c`, `u`, `ped`).
- Los comentarios de sección usan el formato:

```sql
-- 
-- Título de sección
-- 
```

- Encabezado estándar en cada archivo:

```sql
-- nombre_archivo.sql
-- TPI Base de Datos - Food Store
-- [descripción breve opcional]
```

- Se usa `COALESCE(nuevo_valor, columna_actual)` en los UPDATE para permitir actualizaciones parciales conservando el valor existente cuando el nuevo es NULL.
- Se usa `RETURNING <pk>` en los INSERT cuando se necesita recuperar el ID generado.
- Las consultas filtran activos con `WHERE eliminado = FALSE` (nunca `eliminado <> TRUE` ni `NOT eliminado`).
