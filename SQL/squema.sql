CREATE DATABASE IF NOT EXISTS food_store;
USE food_store;

-- 1. Tabla Categoria
CREATE TABLE categoria (
    id_categoria          BIGINT AUTO_INCREMENT PRIMARY KEY,
    nombre_categoria      VARCHAR(80) NOT NULL UNIQUE,
    descripcion_categoria VARCHAR(255),
    eliminado             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Tabla Producto
CREATE TABLE producto (
    id_producto           BIGINT AUTO_INCREMENT PRIMARY KEY,
    nombre_producto       VARCHAR(120) NOT NULL,
    precio_producto       DECIMAL(10,2) NOT NULL CHECK (precio_producto >= 0),
    descripcion_producto  VARCHAR(255),
    stock_producto        INT NOT NULL DEFAULT 0 CHECK (stock_producto >= 0),
    imagen_producto       VARCHAR(255),
    disponible            BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id          BIGINT NOT NULL,
    eliminado             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_producto_categoria FOREIGN KEY (categoria_id) REFERENCES categoria(id_categoria)
);

-- 3. Tabla Usuario
CREATE TABLE usuario (
    id_usuario          BIGINT AUTO_INCREMENT PRIMARY KEY,
    nombre_usuario      VARCHAR(80) NOT NULL,
    apellido_usuario    VARCHAR(80) NOT NULL,
    mail_usuario        VARCHAR(120) NOT NULL UNIQUE,
    celular_usuario     VARCHAR(30),
    contrasena_usuario  VARCHAR(255) NOT NULL,
    rol                 ENUM('ADMIN', 'USUARIO') NOT NULL DEFAULT 'USUARIO',
    eliminado           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. Tabla Pedido
CREATE TABLE pedido (
    id_pedido         BIGINT AUTO_INCREMENT PRIMARY KEY,
    fecha_pedido      DATE NOT NULL DEFAULT (CURRENT_DATE),
    estado_pedido     ENUM('PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO') NOT NULL DEFAULT 'PENDIENTE',
    total_pedido      DECIMAL(12,2) NOT NULL DEFAULT 0.00 CHECK (total_pedido >= 0),
    forma_pago        ENUM('TARJETA', 'TRANSFERENCIA', 'EFECTIVO') NOT NULL,
    usuario_id        BIGINT NOT NULL,
    eliminado         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pedido_usuario FOREIGN KEY (usuario_id) REFERENCES usuario(id_usuario)
);

-- 5. Tabla Detalle Pedido
CREATE TABLE detalle_pedido (
    id_detallepedido        BIGINT AUTO_INCREMENT PRIMARY KEY,
    cantidad_detallepedido  INT NOT NULL CHECK (cantidad_detallepedido > 0),
    precio_unitario         DECIMAL(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal_detallepedido  DECIMAL(12,2) NOT NULL CHECK (subtotal_detallepedido >= 0),
    pedido_id               BIGINT NOT NULL,
    producto_id             BIGINT NOT NULL,
    eliminado               BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT idx_pedido_producto UNIQUE (pedido_id, producto_id),
    CONSTRAINT fk_detalle_pedido FOREIGN KEY (pedido_id) REFERENCES pedido(id_pedido) ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (producto_id) REFERENCES producto(id_producto)
);

-- Índices requeridos
CREATE INDEX idx_producto_categoria ON producto(categoria_id);
CREATE INDEX idx_pedido_usuario ON pedido(usuario_id);