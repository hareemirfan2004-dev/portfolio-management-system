# CLAUDE.md — Portfolio Management System

Dev notes and tech decisions for Claude Code sessions.

## Tech Decisions

| Decision        | Choice                   | Reason                                              |
|-----------------|--------------------------|-----------------------------------------------------|
| Database        | MySQL 8.4                | Course requirement; running locally on Windows 11   |
| App layer       | Flask (Python)           | Lightweight, minimal boilerplate, easy MySQL wiring |
| DB driver       | mysql-connector-python   | Official MySQL driver, no ORM — raw SQL for DBMS course |
| No ORM          | Plain SQL only           | Course focus is on writing and understanding SQL    |

## Project Context

- Course: DBMS (Database Management Systems)
- Domain: Brokerage firm financial management
- Focus: Schema design, normalization, triggers, complex queries
- App layer is secondary — SQL files are the deliverable

## Actual Conventions (as implemented)

- **SQL keywords**: UPPERCASE (`SELECT`, `FROM`, `WHERE`, `INSERT`, `JOIN`, etc.)
- **Table names**: singular, mixed-case with underscores — PascalCase for most (`Market`, `Client`, `Stocks`, `Mutual_Funds`, `Trigger_Price`), all-lowercase for `stock_transaction` (reserved-word avoidance)
- **Column names**: `TableName_ID` for PKs (e.g., `Client_ID`, `Market_ID`, `Stock_ID`); descriptive names for other columns
- **Constraints**: always named (`pk_`, `fk_`, `uq_`, `chk_` prefixes)
- **NULL policy**: `NOT NULL` where a value is always required; nullable FKs for optional relationships (e.g., `Investments.Stock_ID`, `stock_transaction.Order_ID`)

## MySQL Connection (local dev)

- Host: localhost
- Port: 3306
- User: root
- Database: `portfolio_db`

## File Layout (as implemented)

```
sql/
  01_schema.sql     — all CREATE TABLE statements, in FK dependency order
  02_seed.sql       — ~10 rows per table, truncates first (re-runnable)
  03_queries.sql    — 10 analytical queries
  04_views.sql      — 3 views
  05_triggers.sql   — 5 triggers
  06_cursors.sql    — sp_portfolio_value_report() stored procedure

docs/
  schema-design.md
  normalization.md
  concurrency-recovery.md

app/
  main.py           — Flask routes + template filters
  db.py             — get_db() context manager, reads .env
  templates/        — base, clients, portfolio, order, summary
```

## Load Order (critical)

Run in this sequence to avoid the seed ↔ trigger conflict:

1. `01_schema.sql` — create tables
2. `02_seed.sql`   — insert seed data (**before** triggers)
3. `04_views.sql`  — create views
4. `05_triggers.sql` — create triggers
5. `06_cursors.sql` — create stored procedure

Re-running `02_seed.sql` after `05_triggers.sql` is loaded will fail because
`trg_transaction_after_insert` inserts a Tax row for the SELL transaction in the
seed data, then the seed's own Tax INSERT hits the UNIQUE constraint. Fix: load
seed before triggers, or drop and recreate triggers around each seed re-run.

## Known Design Trade-offs

| Decision | Reason |
|----------|--------|
| `Investments.Name` kept (3NF violation) | Avoids JOIN on every watchlist/portfolio read |
| `Investments.Market_ID` for STOCK rows (3NF violation) | Avoids subtype split that would complicate all queries |
| `stock_transaction.Client_ID / Broker_ID` (3NF violation) | Required for manual trades where `Order_ID IS NULL` |
| `Insights.Total_PL` kept (derived column) | Matches original spec; should be removed in strict normalization |
| `stock_transaction` (not `transaction`) | `TRANSACTION` is a MySQL reserved word |
