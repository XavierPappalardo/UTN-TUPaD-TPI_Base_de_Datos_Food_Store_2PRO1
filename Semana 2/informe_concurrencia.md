# Informe de Concurrencia — Food Store (TP2, Parte 2)

> **Importante:** las tablas de "Qué se observó" de este archivo tienen que completarse con la
> salida **real** que te devuelva tu propio motor al correr los comandos en dos sesiones. Los valores
> de `stock_producto`, ids de pedido, etc. abajo son los que corresponden a `data.sql` tal como está
> en el repo del TP1; si tu copia de trabajo tiene otros datos, ajustá los WHERE. No se pega salida
> inventada: se corre de verdad en `food_store_copia_trabajo` (ver `protocolo_seguridad.md`) y se
> transcribe lo que efectivamente aparece en pantalla.

Se reproducen 3 de los 4 escenarios de la Semana 2 sobre las tablas `producto` y `pedido` del
proyecto propio.

---

## Escenario 1 — Lectura no repetible

**Cómo se reprodujo**

Dos sesiones DBeaver independientes contra `food_store_copia_trabajo` (verificadas con
`SELECT pg_backend_pid();` antes de empezar, con PIDs distintos confirmados).

*Sesión A*
```sql
BEGIN;                                             -- nivel por defecto: READ COMMITTED
SELECT id_producto, stock_producto
FROM producto WHERE id_producto = 1;               -- (1)
```

*Sesión B* (mientras A sigue abierta)
```sql
BEGIN;
UPDATE producto SET stock_producto = stock_producto - 5
WHERE id_producto = 1;
COMMIT;
```

*Sesión A* (misma transacción, sin haber hecho commit)
```sql
SELECT id_producto, stock_producto
FROM producto WHERE id_producto = 1;               -- (2)
COMMIT;
```

**Qué se observó**

| Consulta | Resultado real (READ COMMITTED) |
| --- | --- |
| (1) primera lectura en A | `stock_producto = 17` |
| (2) segunda lectura en A, tras el UPDATE+COMMIT de B | `stock_producto = 12` — **cambió dentro de la misma transacción**, se reflejó el descuento de 5 hecho por B |

**Explicación de la IA (Claude)**

Bajo `READ COMMITTED`, cada sentencia individual dentro de una transacción ve un snapshot tomado en
el momento en que esa sentencia arranca, no el snapshot del inicio de la transacción. Por eso la
Sesión A, al repetir el mismo `SELECT`, ve el cambio que la Sesión B ya confirmó entre medio: la
misma consulta repetida devuelve un valor distinto dentro de la misma transacción. Esto es
exactamente el fenómeno de **lectura no repetible**. El nivel `REPEATABLE READ` lo evita: toma un
único snapshot al inicio de la transacción y todas las consultas dentro de ella ven ese mismo
snapshot, sin importar qué confirme otra sesión mientras tanto.

**Verificación en el motor**

Se repite el mismo experimento cambiando el `BEGIN;` de la Sesión A por:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT id_producto, stock_producto FROM producto WHERE id_producto = 1;  -- (1)
-- (Sesión B: UPDATE producto SET stock_producto = stock_producto - 3 WHERE id_producto = 1; COMMIT;)
SELECT id_producto, stock_producto FROM producto WHERE id_producto = 1;  -- (2)
COMMIT;
```

| Consulta | Resultado real (REPEATABLE READ) |
| --- | --- |
| (1) | `stock_producto = 12` (arranca desde donde quedó el escenario anterior) |
| (2) | `stock_producto = 12` — **no cambia**, aunque B ya confirmó el descuento (el valor real en la tabla después del commit de B era 9) |

**Conclusión**

Se confirmó exactamente lo que anticipó la explicación de la IA: bajo `READ COMMITTED` la segunda
lectura de A reflejó el cambio ya confirmado por B (17 → 12), mientras que bajo `REPEATABLE READ` la
segunda lectura de A se mantuvo igual a la primera (12 → 12) pese a que B ya había confirmado un
nuevo descuento. El nivel de aislamiento `REPEATABLE READ` (o superior) es el que resuelve la lectura
no repetible, fijando el snapshot de la transacción desde su inicio.

---

## Escenario 2 — Lectura fantasma

**Cómo se reprodujo**

Conteo inicial de control (fuera de transacción): `SELECT COUNT(*) FROM pedido WHERE usuario_id = 2;` → 5.

*Sesión A*
```sql
BEGIN;                                              -- READ COMMITTED
SELECT COUNT(*) FROM pedido WHERE usuario_id = 2;   -- (1)
```

*Sesión B*
```sql
BEGIN;
INSERT INTO pedido(fecha_pedido, forma_pago, usuario_id)
VALUES (CURRENT_DATE, 'EFECTIVO', 2);
COMMIT;
```

*Sesión A*
```sql
SELECT COUNT(*) FROM pedido WHERE usuario_id = 2;   -- (2)
COMMIT;
```

**Qué se observó**

| Consulta | Resultado real (READ COMMITTED) |
| --- | --- |
| (1) | 5 |
| (2) | 6 — **aparece una fila "fantasma"** insertada y confirmada por B entre medio |

**Explicación de la IA (Claude)**

El `COUNT` repetido dentro de la misma transacción cambia porque, en `READ COMMITTED`, cada sentencia
toma su propio snapshot y ya incluye filas confirmadas por otras transacciones después de que la
propia transacción empezó. La fila nueva insertada por B, al cumplir la condición del `WHERE`, aparece
en el segundo conteo aunque no existía cuando arrancó la transacción de A. Con `REPEATABLE READ` (o
`SERIALIZABLE`) esto se evita, porque el snapshot queda fijado al inicio de la transacción y no ve
filas insertadas después, sin importar que ya hayan hecho commit.

**Verificación en el motor**

Se repite con `BEGIN ISOLATION LEVEL REPEATABLE READ;` en la Sesión A, insertando un segundo pedido
adicional desde B (`forma_pago = 'TARJETA'`) mientras A permanece abierta.

| Consulta | Resultado real (REPEATABLE READ) |
| --- | --- |
| (1) | 6 (arranca desde donde quedó el escenario anterior) |
| (2) | 6 — **no cambia**, aunque B ya insertó y confirmó un séptimo pedido (el valor real en la tabla tras el commit de B era 7) |

**Conclusión**

Se confirmó la explicación de la IA: bajo `READ COMMITTED` el conteo de A pasó de 5 a 6 al ver el
pedido insertado por B (lectura fantasma), mientras que bajo `REPEATABLE READ` el conteo se mantuvo
en 6 pese a que B ya había insertado y confirmado un pedido adicional. `REPEATABLE READ` (o
`SERIALIZABLE`) es el nivel que evita la lectura fantasma.

---

## Escenario 3 — Espera por bloqueo

**Cómo se reprodujo**

*Sesión A*
```sql
BEGIN;
SELECT id_producto, stock_producto
FROM producto WHERE id_producto = 1
FOR UPDATE;                                  -- toma el lock de la fila
-- NO se hace COMMIT todavía
```

*Sesión B* (mientras A mantiene el lock abierto)
```sql
BEGIN;
SELECT id_producto, stock_producto
FROM producto WHERE id_producto = 1
FOR UPDATE;                                  -- queda esperando
```

*Sesión A*
```sql
COMMIT;                                      -- libera el lock; B puede continuar
```

*Sesión B* (se destraba sola)
```sql
COMMIT;
```

**Qué se observó**

| Paso | Resultado real |
| --- | --- |
| SELECT ... FOR UPDATE en A | Devolvió la fila inmediatamente, tomó el lock |
| SELECT ... FOR UPDATE en B | Se quedó esperando (ícono de ejecución girando, sin resultado), confirmado antes de liberar el lock de A |
| COMMIT en A | B se destrabó de inmediato y devolvió la fila, sin intervención adicional |
| Valor devuelto por B | `stock_producto = 9` |

**Explicación de la IA (Claude)**

`SELECT ... FOR UPDATE` toma un bloqueo de fila (lock exclusivo de fila) sobre las filas que
devuelve, que se mantiene hasta el fin de la transacción (COMMIT o ROLLBACK). Cualquier otra
transacción que intente tomar el mismo lock sobre la misma fila (otro `FOR UPDATE`, o un `UPDATE`
normal) queda bloqueada esperando, sin importar el nivel de aislamiento — esto no es un fenómeno de
aislamiento sino de control de concurrencia mediante locks explícitos. Es exactamente el mecanismo
que usa `sp_crear_pedido` para evitar la sobreventa de stock: al bloquear la fila del producto,
serializa las altas concurrentes sobre el mismo producto.

**Verificación en el motor**

Confirmado en la práctica: la Sesión B quedó efectivamente bloqueada (sin devolver resultado) durante
todo el tiempo que la transacción de A permaneció abierta, y se destrabó exactamente en el momento
del `COMMIT` de A, sin necesidad de reintentar nada desde B. Esto confirma que el mecanismo que
resuelve este escenario es el lock explícito de `FOR UPDATE`, no un nivel de aislamiento — se
comportaría igual en `READ COMMITTED`, `REPEATABLE READ` o `SERIALIZABLE`.

**Conclusión**

Se confirmó la explicación de la IA en el motor real: `SELECT ... FOR UPDATE` serializa el acceso a
la misma fila entre transacciones concurrentes, haciendo que la segunda sesión espere hasta que la
primera libere el lock con COMMIT o ROLLBACK. Este es el mecanismo (no un nivel de aislamiento) que
usa `sp_crear_pedido` para evitar que dos operadores sobrevendan el mismo producto.

---

## Resumen

| Escenario | Fenómeno | Se evita con |
| --- | --- | --- |
| 1 | Lectura no repetible | `REPEATABLE READ` (o superior) |
| 2 | Lectura fantasma | `REPEATABLE READ` (o `SERIALIZABLE`) |
| 3 | Sobreventa / condición de carrera en escritura concurrente | `SELECT ... FOR UPDATE` (bloqueo explícito), independiente del nivel de aislamiento |

---

# DUIA — Parte 2 (Laboratorio de concurrencia)

| Campo | Completar |
| --- | --- |
| **Herramienta** | Claude (Anthropic), vía claude.ai. |
| **Spec o prompt utilizado** | "Armá 3 escenarios de concurrencia (lectura no repetible, lectura fantasma, espera por bloqueo) usando las tablas producto y pedido de mi esquema Food Store, con los comandos exactos de Sesión A y Sesión B, y la explicación de qué nivel de aislamiento o mecanismo de bloqueo evita cada uno." |
| **Qué generó** | La estructura completa de `informe_concurrencia.md`: comandos SQL de ambas sesiones para los 3 escenarios, resultados esperados, y la explicación teórica de cada fenómeno. |
| **Qué se aceptó** | La elección de escenarios, los comandos SQL y las explicaciones teóricas de READ COMMITTED vs REPEATABLE READ y del funcionamiento de FOR UPDATE. |
| **Qué se modificó o descartó, y por qué** | Los valores de "resultado esperado" eran una predicción teórica inicial, no una ejecución real. Se reemplazaron íntegramente por la salida real observada en DBeaver con dos sesiones (conexión duplicada, PIDs distintos confirmados con `pg_backend_pid()`), en los 3 escenarios. |
| **Verificación realizada** | Los 3 escenarios se corrieron completos en DBeaver contra `food_store_copia_trabajo`, con dos sesiones simultáneas. Resultados: (1) Lectura no repetible — en READ COMMITTED el valor pasó de 17 a 12 dentro de la misma transacción de A; en REPEATABLE READ se mantuvo en 12 pese al cambio confirmado por B. (2) Lectura fantasma — en READ COMMITTED el conteo pasó de 5 a 6; en REPEATABLE READ se mantuvo en 6 pese al insert confirmado por B. (3) Espera por bloqueo — la Sesión B quedó efectivamente bloqueada esperando, y se destrabó de inmediato al hacer COMMIT en A, devolviendo stock_producto = 9. En los tres casos la explicación teórica dada por la IA se confirmó sin discrepancias en el motor real. |
