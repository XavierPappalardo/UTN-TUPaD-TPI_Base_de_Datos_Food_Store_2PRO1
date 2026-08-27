-- Schema.sql
-- TPI Base de Datos - Food Store
-- 

-- 
-- Tipos enumerados
-- 

CREATE TYPE rol           AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO',
                                   'TERMINADO','CANCELADO');
CREATE TYPE forma_pago    AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');

-- 
-- Tabla: categoria
-- 

CREATE TABLE categoria (
    id_categoria          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_categoria      VARCHAR(80)  NOT NULL UNIQUE,
    descripcion_categoria VARCHAR(255),
    eliminado             BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 
-- Tabla: producto
-- 

CREATE TABLE producto (
    id_producto          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_producto      VARCHAR(120) NOT NULL,
    precio_producto      NUMERIC(10,2) NOT NULL CHECK (precio_producto >= 0),
    descripcion_producto VARCHAR(255),
    stock_producto       INTEGER      NOT NULL DEFAULT 0 CHECK (stock_producto >= 0),
    imagen_producto      VARCHAR(255),
    disponible           BOOLEAN      NOT NULL DEFAULT TRUE,
    categoria_id         BIGINT       NOT NULL REFERENCES categoria(id_categoria),
    eliminado            BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 
-- Tabla: usuario
-- 

CREATE TABLE usuario (
    id_usuario         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_usuario     VARCHAR(80)  NOT NULL,
    apellido_usuario   VARCHAR(80)  NOT NULL,
    mail_usuario       VARCHAR(120) NOT NULL UNIQUE,
    celular_usuario    VARCHAR(30),
    contrasena_usuario VARCHAR(255) NOT NULL,
    rol                rol          NOT NULL DEFAULT 'USUARIO',
    eliminado          BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 
-- Tabla: pedido
-- 

CREATE TABLE pedido (
    id_pedido     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_pedido  DATE          NOT NULL DEFAULT CURRENT_DATE,
    estado_pedido estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total_pedido  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_pedido >= 0), 
    forma_pago    forma_pago    NOT NULL,
    usuario_id    BIGINT        NOT NULL REFERENCES usuario(id_usuario),     
    eliminado     BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- 
-- Tabla: detalle_pedido
-- 

CREATE TABLE detalle_pedido (
    id_detallepedido       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad_detallepedido INTEGER       NOT NULL CHECK (cantidad_detallepedido > 0),
    precio_unitario        NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal_detallepedido NUMERIC(12,2) NOT NULL CHECK (subtotal_detallepedido >= 0),
    pedido_id              BIGINT        NOT NULL REFERENCES pedido(id_pedido)
                                          ON DELETE RESTRICT,
    producto_id            BIGINT        NOT NULL REFERENCES producto(id_producto),
    eliminado              BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (pedido_id, producto_id)
);

--
-- Índices requeridos
--

-- Soporta el listado de productos por categoría (FK producto -> categoria)
CREATE INDEX idx_producto_categoria_id ON producto(categoria_id);

-- Soporta el historial de pedidos por usuario (FK pedido -> usuario)
CREATE INDEX idx_pedido_usuario_id ON pedido(usuario_id);

-- Índice parcial: acelera búsquedas por nombre de producto solo entre
-- las filas vigentes (no eliminadas), que son las que consultan las vistas
CREATE INDEX idx_producto_nombre_vigente
    ON producto(nombre_producto) WHERE eliminado = FALSE;