-- 
-- BASE DE DATOS FOOD STORE
-- PostgreSQL 16+
-- 

-- TIPOS ENUM

CREATE TYPE rol_usuario AS ENUM (
    'ADMIN',
    'USUARIO'
);

CREATE TYPE estado_pedido AS ENUM (
    'PENDIENTE',
    'CONFIRMADO',
    'TERMINADO',
    'CANCELADO'
);

CREATE TYPE forma_pago AS ENUM (
    'TARJETA',
    'TRANSFERENCIA',
    'EFECTIVO'
);


-- 
-- CATEGORIA
--

CREATE TABLE categoria (
    id_categoria          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_categoria      VARCHAR(80) NOT NULL UNIQUE,
    descripcion_categoria VARCHAR(255),
    eliminado             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 
-- PRODUCTO
-- 

CREATE TABLE producto (
    id_producto           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_producto       VARCHAR(120) NOT NULL,
    precio_producto       NUMERIC(10,2) NOT NULL
                          CHECK (precio_producto >= 0),
    descripcion_producto  VARCHAR(255),
    stock_producto        INTEGER NOT NULL DEFAULT 0
                          CHECK (stock_producto >= 0),
    imagen_producto       VARCHAR(255),
    disponible            BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id          BIGINT NOT NULL,

    eliminado             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (categoria_id)
        REFERENCES categoria(id_categoria)
);


-- 
-- USUARIO
-- 

CREATE TABLE usuario (
    id_usuario          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_usuario      VARCHAR(80) NOT NULL,
    apellido_usuario    VARCHAR(80) NOT NULL,
    mail_usuario        VARCHAR(120) NOT NULL UNIQUE,
    celular_usuario     VARCHAR(30),
    contrasena_usuario  VARCHAR(255) NOT NULL,

    rol                 rol_usuario NOT NULL DEFAULT 'USUARIO',

    eliminado           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 
-- PEDIDO
-- 

CREATE TABLE pedido (
    id_pedido         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    fecha_pedido      DATE NOT NULL DEFAULT CURRENT_DATE,

    estado_pedido     estado_pedido NOT NULL DEFAULT 'PENDIENTE',

    total_pedido      NUMERIC(12,2) NOT NULL DEFAULT 0.00
                      CHECK (total_pedido >= 0),

    forma_pago        forma_pago NOT NULL,

    usuario_id        BIGINT NOT NULL,

    eliminado         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_pedido_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuario(id_usuario)
);


--
-- DETALLE PEDIDO
-- 

CREATE TABLE detalle_pedido (
    id_detallepedido        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    cantidad_detallepedido  INTEGER NOT NULL
                            CHECK (cantidad_detallepedido > 0),

    precio_unitario         NUMERIC(10,2) NOT NULL
                            CHECK (precio_unitario >= 0),

    subtotal_detallepedido  NUMERIC(12,2) NOT NULL
                            CHECK (subtotal_detallepedido >= 0),

    pedido_id               BIGINT NOT NULL,

    producto_id             BIGINT NOT NULL,

    eliminado               BOOLEAN NOT NULL DEFAULT FALSE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT idx_pedido_producto
        UNIQUE (pedido_id, producto_id),

    CONSTRAINT fk_detalle_pedido
        FOREIGN KEY (pedido_id)
        REFERENCES pedido(id_pedido)
        ON DELETE RESTRICT,

    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id)
        REFERENCES producto(id_producto)
);


-- 
-- ÍNDICES REQUERIDOS
-- 

CREATE INDEX idx_producto_categoria
    ON producto(categoria_id);

CREATE INDEX idx_pedido_usuario
    ON pedido(usuario_id);

-- Índice parcial solicitado por el TPI
CREATE INDEX idx_producto_nombre_vigente
    ON producto(nombre_producto)
    WHERE eliminado = FALSE;