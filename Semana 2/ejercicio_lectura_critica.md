# Ejercicio de Lectura Crítica — TP2, Parte 3

Análisis de los dos scripts del enunciado, generados "supuestamente" para dar de baja registros
vencidos, **antes de ejecutarlos**.

---

## Script 1

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

**Qué haría realmente**

No tiene cláusula `WHERE`. Un `UPDATE` sin `WHERE` afecta **todas las filas de la tabla**, no
solo las funciones retiradas de cartel. El resultado es que `activa` pasa a `FALSE` para
absolutamente todas las funciones, incluidas las que siguen vigentes — en la práctica, se da de baja
la cartelera completa.

**Por qué no coincide con la consigna**

La consigna dice "dar de baja las funciones **retiradas de cartel**", es decir, un subconjunto
identificable por algún criterio (una fecha de fin, un flag de vigencia, etc.). El script tal como
está escrito no filtra ese subconjunto: es sintácticamente válido y se ejecutaría sin ningún error,
pero hace algo completamente distinto de lo que dice hacer. Es exactamente el patrón de los casos
reales de la Parte 3 del TP: la sintaxis es correcta y la intención declarada es razonable, pero
falta la condición que acota el efecto.

**Versión corregida**

Falta conocer la columna exacta que marca "retirada de cartel" en la tabla `funcion` (por ejemplo,
una fecha de fin de exhibición). Con un criterio típico de fecha:

```sql
UPDATE funcion
SET activa = FALSE
WHERE fecha_fin < CURRENT_DATE
  AND activa = TRUE;   -- evita tocar filas que ya estaban en FALSE, ver filas realmente afectadas
```

El agregado de `WHERE ... AND activa = TRUE` no es estrictamente necesario para el resultado final,
pero deja más claro, al correr primero un `SELECT` con el mismo `WHERE`, cuántas filas se van a
afectar antes de aplicar el `UPDATE` — que es justamente el paso de "transacción" del protocolo:
correr esto dentro de `BEGIN; ... ROLLBACK;`, mirar el `UPDATE N` que devuelve, y recién ahí decidir
si se confirma.

---

## Script 2

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

**Qué haría realmente**

Esto tiene dos problemas independientes, cualquiera de los dos ya lo vuelve peligroso:

1. **`NOT IN` con NULL en la subconsulta.** Si `producto.categoria_id` tiene aunque sea **una sola
   fila con NULL**, la subconsulta `(SELECT categoria_id FROM producto)` incluye ese NULL, y en SQL
   `x NOT IN (a, b, NULL)` no se evalúa como verdadero ni como falso para ningún `x`: se evalúa como
   `UNKNOWN`, que en un `WHERE` se trata como "no cumple la condición". El resultado práctico es que
   el `DELETE` **no borra ninguna fila**, silenciosamente, sin ningún error — lo cual parece "seguro"
   pero en realidad es que el script simplemente no hace lo que dice que hace, y nadie se entera.
   En el esquema de este proyecto (Food Store) `producto.categoria_id` es `NOT NULL`, así que este
   caso puntual no se dispara — pero el patrón `NOT IN` con una subconsulta sigue siendo una trampa
   general a evitar, porque alcanza con que la tabla cambie en el futuro (por ejemplo, si alguien
   permite `categoria_id NULL`) para que el comportamiento cambie sin que el script cambie una letra.

2. **No respeta el borrado lógico ni la integridad histórica.** Aunque el `NOT IN` funcionara, es un
   `DELETE` físico. En este esquema las bajas son siempre lógicas (`eliminado = TRUE`), y además la
   condición "sin productos asociados" tal como está escrita no filtra por `producto.eliminado`: una
   categoría que solo tiene productos dados de baja lógica (pero que igual existen como fila, por
   ejemplo por historial de pedidos) **sí** aparece como "sin productos" para el `NOT IN`, y el script
   la borraría. Como `producto.categoria_id` tiene una `FOREIGN KEY` hacia `categoria` sin
   `ON DELETE CASCADE`, si esa categoría efectivamente estuviera referenciada por algún producto
   (aunque esté con `eliminado = TRUE`), el motor rechazaría el `DELETE` con un error de violación de
   clave foránea — pero si no está referenciada, se pierde para siempre una categoría que podría
   tener valor histórico, rompiendo el criterio de "el soft delete preserva el historial" que rige el
   resto del esquema.

**Por qué no coincide con la consigna**

La consigna dice "limpiar categorías sin productos asociados" en un esquema donde el patrón de baja
establecido es siempre lógico y donde "sin productos" debería significar "sin productos vigentes",
no "sin ninguna fila de producto, ni siquiera dadas de baja". El script, tal como está, o no borra
nada (si hay NULLs) o borra físicamente y sin criterio de vigencia (si no los hay).

**Versión corregida** (adaptada a los nombres reales del esquema Food Store)

```sql
UPDATE categoria c
SET    eliminado = TRUE
WHERE  c.eliminado = FALSE
  AND  NOT EXISTS (
        SELECT 1
        FROM   producto p
        WHERE  p.categoria_id = c.id_categoria
          AND  p.eliminado = FALSE
       );
```

Cambios respecto del original:

- `DELETE` → `UPDATE ... SET eliminado = TRUE`, para respetar el patrón de baja lógica del proyecto.
- `NOT IN` → `NOT EXISTS`, que es inmune al problema de NULL (una subconsulta con NULL en `NOT
  EXISTS` simplemente no afecta el resultado de las demás filas).
- Se agrega `AND p.eliminado = FALSE` dentro de la subconsulta, para que "sin productos asociados"
  signifique "sin productos vigentes" y no "sin ninguna fila de producto".
- Se agrega `AND c.eliminado = FALSE` en el `WHERE` externo, para no volver a "dar de baja" algo que
  ya estaba dado de baja (evita ruido al revisar cuántas filas afectó el `UPDATE`).

Como siempre, esto se corre primero dentro de `BEGIN; ... ROLLBACK;` sobre la copia de trabajo,
verificando primero con un `SELECT` equivalente cuántas categorías cumplen la condición antes de
aplicar el `UPDATE`.
