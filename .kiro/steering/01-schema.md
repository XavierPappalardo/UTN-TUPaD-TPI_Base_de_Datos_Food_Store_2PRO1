# Food Store — Esquema y Estructura de la Base de Datos

## Contexto general

Proyecto académico (TPI) de la UTN TUPaD, comisión 2PRO1.
Base de datos PostgreSQL 16+ llamada **Food Store** para gestionar categorías, productos, usuarios, pedidos y detalles de pedidos.
Grupo: Xavier Damiano Pappalardo, Lautaro Gómez Cánovas, Nicolás Ibáñez, Maximiliano Reinoso, Benjamín Arrollo y Martín Sisterna.

---

## Tipos ENUM definidos

```sql
CREATE TYPE rol           AS ENUM ('ADMIN', 'USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO');
CREATE TYPE forma_pago    AS ENUM ('TARJETA', 'TRANSFERENCIA', 'EFECTIVO');
```

- Los tres tipos son globales al esquema y se usan directamente como tipos de columna.
- No existe un ENUM para `disponible`; es un campo `BOOLEAN`.

---

## Tablas

### `categoria`

| Columna                | Tipo           | Restricciones                                  |
|------------------------|----------------|------------------------------------------------|
| `id_categoria`         | BIGINT IDENTITY| PRIMARY KEY                                    |
| `nombre_categoria`     | VARCHAR(80)    | NOT NULL, UNIQUE                               |
| `descripcion_categoria`| VARCHAR(255)   | —                                              |
| `eliminado`            | BOOLEAN        | NOT NULL, DEFAULT FALSE                        |
| `created_at`           | TIMESTAMPTZ    | NOT NULL, DEFAULT now()                        |

### `producto`

| Columna               | Tipo           | Restricciones                                            |
|-----------------------|----------------|----------------------------------------------------------|
| `id_producto`         | BIGINT IDENTITY| PRIMARY KEY                                              |
| `nombre_producto`     | VARCHAR(120)   | NOT NULL                                                 |
| `precio_producto`     | NUMERIC(10,2)  | NOT NULL, CHECK >= 0                                     |
| `descripcion_producto`| VARCHAR(255)   | —                                                        |
| `stock_producto`      | INTEGER        | NOT NULL, DEFAULT 0, CHECK >= 0                          |
| `imagen_producto`     | VARCHAR(255)   | — (puede ser NULL)                                       |
| `disponible`          | BOOLEAN        | NOT NULL, DEFAULT TRUE                                   |
| `categoria_id`        | BIGINT         | NOT NULL, FK → `categoria(id_categoria)`                 |
| `eliminado`           | BOOLEAN        | NOT NULL, DEFAULT FALSE                                  |
| `created_at`          | TIMESTAMPTZ    | NOT NULL, DEFAULT now()                                  |

> **Nota:** `nombre_producto` no tiene restricción UNIQUE a nivel de tabla.

### `usuario`

| Columna              | Tipo           | Restricciones                                |
|----------------------|----------------|----------------------------------------------|
| `id_usuario`         | BIGINT IDENTITY| PRIMARY KEY                                  |
| `nombre_usuario`     | VARCHAR(80)    | NOT NULL                                     |
| `apellido_usuario`   | VARCHAR(80)    | NOT NULL                                     |
| `mail_usuario`       | VARCHAR(120)   | NOT NULL, UNIQUE                             |
| `celular_usuario`    | VARCHAR(30)    | — (puede ser NULL)                           |
| `contrasena_usuario` | VARCHAR(255)   | NOT NULL                                     |
| `rol`                | rol (ENUM)     | NOT NULL, DEFAULT 'USUARIO'                  |
| `eliminado`          | BOOLEAN        | NOT NULL, DEFAULT FALSE                      |
| `created_at`         | TIMESTAMPTZ    | NOT NULL, DEFAULT now()                      |

### `pedido`

| Columna        | Tipo              | Restricciones                                          |
|----------------|-------------------|--------------------------------------------------------|
| `id_pedido`    | BIGINT IDENTITY   | PRIMARY KEY                                            |
| `fecha_pedido` | DATE              | NOT NULL, DEFAULT CURRENT_DATE                         |
| `estado_pedido`| estado_pedido ENUM| NOT NULL, DEFAULT 'PENDIENTE'                          |
| `total_pedido` | NUMERIC(12,2)     | NOT NULL, DEFAULT 0, CHECK >= 0                        |
| `forma_pago`   | forma_pago ENUM   | NOT NULL                                               |
| `usuario_id`   | BIGINT            | NOT NULL, FK → `usuario(id_usuario)`                   |
| `eliminado`    | BOOLEAN           | NOT NULL, DEFAULT FALSE                                |
| `created_at`   | TIMESTAMPTZ       | NOT NULL, DEFAULT now()                                |

> `total_pedido` se calcula automáticamente via trigger; no debe setearse manualmente en `sp_crear_pedido`.

### `detalle_pedido`

| Columna                  | Tipo           | Restricciones                                                |
|--------------------------|----------------|--------------------------------------------------------------|
| `id_detallepedido`       | BIGINT IDENTITY| PRIMARY KEY                                                  |
| `cantidad_detallepedido` | INTEGER        | NOT NULL, CHECK > 0                                          |
| `precio_unitario`        | NUMERIC(10,2)  | NOT NULL, CHECK >= 0                                         |
| `subtotal_detallepedido` | NUMERIC(12,2)  | NOT NULL, CHECK >= 0                                         |
| `pedido_id`              | BIGINT         | NOT NULL, FK → `pedido(id_pedido)` ON DELETE RESTRICT        |
| `producto_id`            | BIGINT         | NOT NULL, FK → `producto(id_producto)`                       |
| `eliminado`              | BOOLEAN        | NOT NULL, DEFAULT FALSE                                      |
| `created_at`             | TIMESTAMPTZ    | NOT NULL, DEFAULT now()                                      |
| UNIQUE                   | —              | `(pedido_id, producto_id)` — un producto una vez por pedido  |

---

## Claves primarias

Todas las tablas usan `BIGINT GENERATED ALWAYS AS IDENTITY` como PK. El patrón es `id_<nombre_tabla>`, con la excepción de `detalle_pedido` cuya PK es `id_detallepedido` (sin guion bajo entre "detalle" y "pedido").

---

## Claves foráneas

| Tabla            | Columna FK      | Referencia                    | ON DELETE     |
|------------------|-----------------|-------------------------------|---------------|
| `producto`       | `categoria_id`  | `categoria(id_categoria)`     | RESTRICT (def)|
| `pedido`         | `usuario_id`    | `usuario(id_usuario)`         | RESTRICT (def)|
| `detalle_pedido` | `pedido_id`     | `pedido(id_pedido)`           | RESTRICT      |
| `detalle_pedido` | `producto_id`   | `producto(id_producto)`       | RESTRICT (def)|

---

## Índices

```sql
-- FK producto -> categoria
CREATE INDEX idx_producto_categoria_id ON producto(categoria_id);

-- FK pedido -> usuario
CREATE INDEX idx_pedido_usuario_id ON pedido(usuario_id);

-- Índice parcial: solo filas vigentes (eliminado = FALSE)
CREATE INDEX idx_producto_nombre_vigente
    ON producto(nombre_producto) WHERE eliminado = FALSE;
```

---

## Diagrama de relaciones (texto)

```
categoria (1) ──< producto (N)
usuario   (1) ──< pedido   (N)
pedido    (1) ──< detalle_pedido (N)
producto  (1) ──< detalle_pedido (N)
```
