---
name: docs-to-dbml
description: >
  Produce a DBML database schema from documentation, requirements, or an existing
  data model. Use when the user wants a DBML (dbdiagram.io) file describing
  tables, columns, and relationships, or mentions DBML / ER diagram / data model.
risk_level: low
writes_files: true
requires_tools: []
license: MIT
metadata:
  version: "1"
---

# Docs → DBML

Read the project's documentation (requirements, specs, existing notes) and express
the data model as a [DBML](https://dbml.dbdiagram.io/docs/) file.

## Inputs

Documentation the user points to (specs, ADRs, an entity list, or a prose
description). If none is given, ask which document to model.

## Output

`docs/data-models/<name>.dbml` — one DBML file. Never modify unrelated files.

## DBML syntax (the subset to emit)

```dbml
Table users {
  id integer [primary key]
  username varchar [not null, unique]
  role varchar [note: 'admin | member']
  created_at timestamp [default: `now()`]

  Note: 'Application users'
}

Table posts {
  id integer [primary key]
  user_id integer [not null]
  status varchar
  Indexes {
    (user_id, status)
  }
}

// Relationships: > many-to-one, < one-to-many, - one-to-one
Ref: posts.user_id > users.id

Enum order_status {
  pending
  shipped
  delivered
}
```

Rules:
- Every table has a **primary key** (`[primary key]` on a column, or
  `indexes { (a,b) [pk] }` for composite).
- Column settings go in `[ ]`: `not null`, `unique`, `primary key`,
  `default: ...`, `note: '...'`. Wrap SQL/function defaults in backticks:
  `` default: `now()` ``.
- Foreign keys: declare a `Ref:` line (or inline `[ref: > users.id]`). Use `>`
  (many-to-one), `<` (one-to-many), `-` (one-to-one).
- Use `Enum` blocks for closed value sets and reference them as the column type.
- Quote table/column names containing spaces or reserved words with double quotes.

## Procedure

1. Extract entities → tables, attributes → columns (pick sensible types:
   `integer`, `varchar`, `text`, `boolean`, `timestamp`, `decimal`, `uuid`).
2. Identify relationships from the docs and emit `Ref:` lines.
3. Add a `Note:` on each table summarizing its purpose; add `note:` on
   non-obvious columns.
4. Write `docs/data-models/<name>.dbml`.

## Validation

- Every `Ref:` references a `table.column` that exists in the file.
- Every table has a primary key.
- If the `@dbml/cli` tool is available, run `dbml2sql <file> --postgres` and fix
  any parse error it reports.

The DBML file describes the model; it does not replace the migrations. When the
project already has an ORM schema, derive the DBML from that schema and say which
one is the source of truth.
