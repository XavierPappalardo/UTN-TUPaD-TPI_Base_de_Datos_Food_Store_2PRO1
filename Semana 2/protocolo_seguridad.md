# Protocolo de Seguridad — Food Store (TP2, Parte 0)

Adaptación del protocolo de tres pasos de la cátedra (copia, transacción, respaldo) al entorno
concreto de este proyecto: PostgreSQL instalado localmente, administrado con **DBeaver**, con los
scripts versionados en `SQL/schema.sql`, `SQL/objects.sql`, `SQL/data.sql`.

Se aplica **siempre**, sin excepción, a cualquier script que toque la base — propio o generado por
un agente de IA (Claude, OpenCode, Kiro, etc.). No hay casos en los que se salte.

## 1. Copia — nunca se trabaja sobre datos reales

Nunca se ejecuta un script (propio o generado por IA) contra la base que contiene datos que
importan. Siempre se trabaja sobre una base de desarrollo descartable.

**En DBeaver:**

1. Conexión → clic derecho sobre el servidor Postgres local → **Create New Database**.
2. Nombre sugerido: `food_store_copia_trabajo`.
3. Abrir un **SQL Editor** contra esa base nueva y ejecutar, en orden:
   - `SQL/schema.sql`
   - `SQL/objects.sql`
   - `SQL/data.sql`

Si ya existe una base "buena" (`food_store_dev`) y se quiere probar algo riesgoso sin arriesgarla, se
repite el mismo paso creando otra base descartable (`food_store_copia_trabajo_2`, etc.) y se vuelven a
correr los tres scripts ahí.

Todo lo que un agente de IA proponga (restricciones nuevas, migraciones, scripts de limpieza) se
prueba primero en `food_store_copia_trabajo`, nunca en `food_store_dev` directamente y mucho menos en
una base con datos de producción.

## 2. Transacción — nada se confirma sin inspeccionar el efecto

Todo script de escritura (INSERT/UPDATE/DELETE/ALTER que modifique datos) corre primero envuelto en
`BEGIN; ... ROLLBACK;` para ver cuántas filas afecta y qué mensajes tira, antes de decidir si se
confirma.

**En DBeaver:**

1. En el SQL Editor, verificar que el **modo de auto-commit esté desactivado** (barra superior del
   editor: ícono de transacción → "Manual commit"). Si está en "Auto-commit", cada sentencia se
   confirma sola apenas se ejecuta, y este paso pierde el sentido.
2. Ejecutar `BEGIN;` (o directamente empezar a correr sentencias, ya que en modo manual DBeaver abre
   la transacción implícitamente al primer statement).
3. Ejecutar el script generado por la IA (o propio).
4. Revisar en la pestaña de resultados **cuántas filas se afectaron** y si hubo errores/avisos.
5. Si el efecto es el esperado: botón **Commit** (o `COMMIT;`). Si no: botón **Rollback** (o
   `ROLLBACK;`), corregir el script y repetir desde el paso 2.

Ningún `CALL sp_crear_pedido(...)`, `UPDATE`, `DELETE` ni restricción nueva se ejecuta "directo a
Commit" contra la copia de trabajo, ni siquiera cuando el cambio parece trivial (por ejemplo, dar de
baja una sola categoría).

## 3. Respaldo — antes de cualquier cambio estructural

Antes de aplicar un `ALTER TABLE`, un `CREATE TRIGGER`, o cualquier migración sobre la copia de
trabajo, se saca un respaldo independiente que no depende de poder hacer Rollback (por ejemplo, si el
cambio ya fue confirmado por error).

**En DBeaver:**

1. Clic derecho sobre la base `food_store_copia_trabajo` en el árbol de conexiones → **Tools →
   Backup...** (DBeaver usa `pg_dump` de la instalación local por detrás; hay que tener configurada
   la ruta a las herramientas cliente de Postgres la primera vez que se usa, DBeaver lo pide solo).
2. Guardar el respaldo en una carpeta del repo, por ejemplo `respaldos/`, con nombre con fecha:
   `food_store_copia_trabajo_2026-08-31.backup`.
3. Para restaurar si algo salió mal después de un Commit: clic derecho sobre el servidor → **Create
   New Database** (una nueva, o borrar y recrear la misma) → clic derecho sobre esa base → **Tools →
   Restore...** → seleccionar el archivo del paso 2.

Alternativa por línea de comandos (si se prefiere, ya que la instalación local de Postgres trae
`pg_dump` disponible aunque el día a día sea con DBeaver):

```bash
pg_dump -U postgres -d food_store_copia_trabajo -F c -f respaldos/food_store_copia_trabajo_$(date +%Y%m%d).backup
```

## Regla de fondo

Un agente de IA puede **escribir** el script (constraint, trigger, script de baja masiva,
corrección), pero la **decisión** de aplicarlo contra cualquier base —incluso la de desarrollo— es
siempre humana, y pasa obligatoriamente por: leer el diff línea por línea, probarlo dentro de una
transacción sobre una copia (modo manual commit en DBeaver), y tener un respaldo antes de cualquier
DDL. Ningún reporte del propio agente ("ya lo apliqué", "funcionó") se toma como confirmación: la
confirmación es lo que muestra DBeaver en la pestaña de resultados o lo que devuelve el motor.
