# AGENTS.md

## Project

UTN TUPaD TPI academic project: **Food Store** — a pure **PostgreSQL 16+** database schema for a fictional food store (categories, products, users, orders, order details). There is **no application code and no build/test/lint/CI system**. Everything (SQL code, identifiers, comments) is in **Spanish**.

## Authoritative spec

Read `.kiro/steering/*.md` first — it is the canonical design doc and matches the committed SQL:
- `01-schema.md` / `03-objetos.md` — tables, ENUMs, views, functions, triggers, procedure
- `02-convenciones.md` — naming & style conventions
- `04-soft-delete-transacciones-stock.md` — soft-delete, transactions, stock/concurrency
- `05-orden-ejecucion.md` — script execution order & dependencies

## Execution order (mandatory)

Scripts depend on each other; run in `SQL/` in this order:

```
1. schema.sql        -> ENUMs, tables, indexes
2. objects.sql       -> views, functions, triggers, procedure
3. data.sql          -> seed data (single transaction; activates triggers)
4. queries.sql       -> example DML (may INSERT/UPDATE data)
5. transacciones.sql -> ACID/concurrency tests
```

- `queries.sql` and `transacciones.sql` require the first three already run.
- Concurrency scenarios in `transacciones.sql` need **two simultaneous DB sessions** (SECTION A / SECTION B) — cannot run in one sequential session.
- `data.sql` hardcodes IDs (e.g. `WHERE id_pedido = 5`) that only match a freshly-seeded clean DB.

## Conventions (differ from SQL defaults; follow the spec)

- Naming prefixes: `v_` views, `fn_` functions, `sp_` procedures, `trg_` triggers, `idx_` indexes; `p_` params, `v_` locals.
  - **Exception:** `calcular_total_pedido()` has no `fn_` prefix (intentional — public/calculable).
  - **Gotcha:** `detalle_pedido` PK is `id_detallepedido` (no underscore before "pedido").
- ENUM type names lowercase; ENUM **values UPPERCASE** (`PENDIENTE`, `CONFIRMADO`...).
- Filter active rows with `where eliminado = FALSE` only — never `<> TRUE`, `NOT eliminado`, or `IS FALSE`. Every table has `eliminado BOOLEAN` (soft delete).
- `total_pedido` is **trigger-computed — never set manually**. Two separate AFTER STATEMENT triggers (`trg_total_ins`, `trg_total_upd`) exist because PG transition tables can't span multiple events in one trigger.
- Order deactivation = **two-step transaction**: `UPDATE detalle_pedido ... ; UPDATE pedido ...` together in one `BEGIN;...COMMIT;`.
- Use `COALESCE(nuevo_valor, columna_actual)` in UPDATEs for partial updates, and `RETURNING <pk>` in INSERTs to recover generated IDs.
- Deactivation/delete of a parent row on `detalle_pedido` is blocked by `ON DELETE RESTRICT` on `pedido_id` FK; the soft-delete path is via triggers.

## Known quirks (verified)

- `objects.sql` contains stray editor-comment artifacts (`-- corregido: id -> id_pedido`); code itself is correct.
- No `trg_total_del` trigger (soft delete converts DELETEs to UPDATEs, so `trg_total_upd` still fires).
- `v_pedidos_resumen` does not filter `usuario.eliminado`; `v_pedido_detalle` does not filter `producto.eliminado` — likely intentional to preserve history.
- Stock decrement is done in `sp_crear_pedido` using `SELECT ... FOR UPDATE` for concurrency control.

## Git

- `.kiro/`, `Link al Repo.txt`, and the TP1 zip are untracked; no `.gitignore`.
