-- ============================================================
-- DATA.SQL
-- DATOS DE PRUEBA FOOD STORE
-- ============================================================


-- ============================================================
-- 1. CATEGORIAS
-- ============================================================

INSERT INTO categoria (
    nombre_categoria,
    descripcion_categoria
)
VALUES
(
    'Hamburguesas',
    'Hamburguesas artesanales y simples'
),
(
    'Pizzas',
    'Pizzas a la piedra y al molde'
),
(
    'Bebidas',
    'Gaseosas y aguas sin alcohol'
),
(
    'Postres',
    'Helados y postres caseros'
);


-- ============================================================
-- 2. PRODUCTOS
-- ============================================================

INSERT INTO producto (
    nombre_producto,
    precio_producto,
    descripcion_producto,
    stock_producto,
    categoria_id
)
VALUES
(
    'Hamburguesa Clásica',
    4500.00,
    'Carne, queso y lechuga',
    50,
    1
),
(
    'Hamburguesa Doble',
    6200.00,
    'Doble carne, doble cheddar y bacon',
    30,
    1
),
(
    'Pizza Muzarella',
    7500.00,
    'Salsa de tomate, muzarella y orégano',
    20,
    2
),
(
    'Pizza Especial',
    9000.00,
    'Muzarella, jamón y morrones',
    15,
    2
),
(
    'Gaseosa Cola 500ml',
    1500.00,
    'Lata de gaseosa',
    100,
    3
),
(
    'Helado Choco-Almendra',
    2500.00,
    'Pote individual',
    25,
    4
);


-- ============================================================
-- 3. USUARIOS
-- ============================================================

INSERT INTO usuario (
    nombre_usuario,
    apellido_usuario,
    mail_usuario,
    celular_usuario,
    contrasena_usuario,
    rol
)
VALUES
(
    'Admin',
    'General',
    'admin@foodstore.com',
    '261000000',
    'hash_pass_admin',
    'ADMIN'
),
(
    'Juan',
    'Pérez',
    'juan.perez@email.com',
    '261111111',
    'hash_pass_1',
    'USUARIO'
),
(
    'Ana',
    'Garis',
    'ana.garis@email.com',
    '261222222',
    'hash_pass_2',
    'USUARIO'
);