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
- App layer is secondary — SQL is the deliverable

## Conventions

- All SQL files use lowercase keywords for readability
- Table names: singular, snake_case (e.g., `client`, `stock_holding`)
- Primary keys: `id` (auto-increment) or descriptive (e.g., `account_id`)
- Seed data lives in `sql/seed/` and is safe to re-run (use INSERT IGNORE or truncate first)

## MySQL Connection (local dev)

- Host: localhost
- Port: 3306
- User: root
- Database: portfolio_db (to be created)

## File Layout Decisions

- `sql/schema/` — one file per logical group (accounts, transactions, etc.) or one combined `create_tables.sql`
- `sql/queries/` — named by feature (e.g., `portfolio_summary.sql`, `top_gainers.sql`)
- `sql/triggers/` — one file per trigger or grouped by table
- `sql/seed/` — `sample_data.sql` with realistic but fictional brokerage data
