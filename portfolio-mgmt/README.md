# Portfolio Management System

A relational database project for a DBMS course, modelling the core operations of a brokerage firm — client accounts, stock and mutual-fund holdings, buy/sell orders, tax records, and portfolio analytics.

The **database layer is the primary deliverable**. A lightweight Flask web app wires the SQL work to a browser interface.

---

## Table of Contents

1. [Tech Stack](#tech-stack)
2. [Project Structure](#project-structure)
3. [Prerequisites](#prerequisites)
4. [Loading the Database](#loading-the-database)
5. [Running the App](#running-the-app)
6. [SQL Features Demonstrated](#sql-features-demonstrated)
7. [Schema Overview](#schema-overview)
8. [Screenshots](#screenshots)
9. [Documentation](#documentation)

---

## Tech Stack

| Layer    | Technology                | Notes                          |
|----------|---------------------------|--------------------------------|
| Database | MySQL 8.4                 | InnoDB engine; raw SQL only    |
| Backend  | Flask 3.x (Python)        | Minimal app layer              |
| Driver   | mysql-connector-python    | No ORM — direct SQL execution  |
| Config   | python-dotenv             | Credentials read from `.env`   |

---

## Project Structure

```
portfolio-mgmt/
├── sql/
│   ├── 01_schema.sql          — CREATE TABLE, all constraints and indexes
│   ├── 02_seed.sql            — ~10 rows per table, realistic brokerage data
│   ├── 03_queries.sql         — 10 analytical queries (joins, CTEs, set ops)
│   ├── 04_views.sql           — 3 views: ClientPortfolioSummary, BrokerPerformance, WatchlistAlerts
│   ├── 05_triggers.sql        — 5 triggers: order validation, auto-execution, tax upsert
│   └── 06_cursors.sql         — Stored procedure with cursor: sp_portfolio_value_report()
├── docs/
│   ├── er_diagram/
│   │   └── er_diagram.md      — Mermaid ER diagram (all 15 tables, rendered on GitHub)
│   ├── schema-design.md       — ER description, cardinalities, FK dependency map
│   ├── normalization.md       — 1NF → 4NF analysis for all 15 tables
│   └── concurrency-recovery.md — Transactions, isolation levels, locking, WAL, PITR
├── app/
│   ├── main.py                — Flask routes and template filters
│   ├── db.py                  — DB connection module (reads .env)
│   └── templates/
│       ├── base.html          — Shared layout, CSS, nav
│       ├── clients.html       — Client list + add form
│       ├── portfolio.html     — Per-client holdings with live P&L
│       ├── order.html         — Place a new order
│       └── summary.html       — ClientPortfolioSummary view
├── requirements.txt
├── .env.example               — Credential template (copy to .env)
└── README.md
```

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| MySQL Server | 8.4 | Must be running; InnoDB is the default engine |
| Python | 3.9 + | |
| pip | any | |

---

## Loading the Database

> **Important — run the files in order.** The seed data must be loaded before triggers are created; otherwise the trigger fires during seeding and conflicts with the seed's own Tax inserts.

### Step 1 — Create the schema

```bash
mysql -u root -p < sql/01_schema.sql
```

This creates `portfolio_db` and all 15 tables. Safe to re-run (drops and recreates).

### Step 2 — Load seed data

```bash
mysql -u root -p portfolio_db < sql/02_seed.sql
```

~10 rows per table. Safe to re-run (TRUNCATEs all tables first).

### Step 3 — Create views

```bash
mysql -u root -p portfolio_db < sql/04_views.sql
```

### Step 4 — Create triggers

```bash
mysql -u root -p portfolio_db < sql/05_triggers.sql
```

### Step 5 — Create stored procedure

```bash
mysql -u root -p portfolio_db < sql/06_cursors.sql
```

### Step 6 — (Optional) Run the analytical queries

```bash
mysql -u root -p portfolio_db < sql/03_queries.sql
```

### Verify the load

```sql
-- Connect to MySQL
mysql -u root -p portfolio_db

-- Check row counts
SELECT TABLE_NAME, TABLE_ROWS
FROM   information_schema.TABLES
WHERE  TABLE_SCHEMA = 'portfolio_db'
ORDER  BY TABLE_NAME;

-- Spot-check a view
SELECT * FROM ClientPortfolioSummary ORDER BY Return_Pct DESC;

-- Run the cursor procedure
CALL sp_portfolio_value_report();
```

---

## Running the App

### 1. Create the `.env` file

```bash
# From the project root
copy .env.example .env      # Windows
# cp .env.example .env      # Mac/Linux
```

Edit `.env` and fill in your MySQL password:

```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_password_here
DB_NAME=portfolio_db
SECRET_KEY=any-random-string
```

### 2. Install dependencies

```bash
pip install -r requirements.txt
```

### 3. Start the server

```bash
python app/main.py
```

Open **http://localhost:5000** in your browser.

### Available pages

| URL | Description |
|-----|-------------|
| `/` | Redirects to Clients |
| `/clients` | List all clients; add a new client |
| `/clients/<id>/portfolio` | Holdings table with live unrealized P&L |
| `/orders/new` | Place a new PENDING order |
| `/summary` | `ClientPortfolioSummary` view — all clients ranked by return % |

---

## SQL Features Demonstrated

### DDL & Schema Design

| Feature | Where |
|---------|-------|
| `CREATE DATABASE` with charset | `01_schema.sql` ln 1 |
| `CREATE TABLE` with 6 constraint types | `01_schema.sql` throughout |
| `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `NOT NULL`, `DEFAULT`, `CHECK` | `01_schema.sql` all tables |
| `ENUM` columns | `Investments.Investment_Type`, `Orders.Status`, `Trigger_Price.Trigger_Condition` |
| `AUTO_INCREMENT` surrogate keys | All 15 tables |
| Supertype/subtype pattern with XOR `CHECK` | `Investments` table |
| Circular FK resolution (nullable FK) | `stock_transaction.Order_ID` |
| `SET FOREIGN_KEY_CHECKS = 0` for safe re-runs | `01_schema.sql`, `02_seed.sql` |
| `DROP TABLE IF EXISTS` in reverse FK order | `01_schema.sql` |

### Data Types

`INT`, `DECIMAL(15,2)`, `VARCHAR`, `DATE`, `DATETIME`, `YEAR`, `ENUM`

### DML

`INSERT` with explicit IDs, `INSERT … ON DUPLICATE KEY UPDATE` (Tax upsert in trigger), `UPDATE`, `DELETE` via `TRUNCATE`

### SELECT & Joins

| Feature | Query |
|---------|-------|
| `INNER JOIN` across 3–5 tables | Q1, Q2, Q4, Q5, Q10 |
| `LEFT JOIN` (preserve all left rows) | Q1–Q5, Q8, Q10, all views |
| `RIGHT JOIN` (all brokers inc. inactive) | Q9 |
| `CROSS JOIN` with scalar subquery | Q8 (platform average) |
| 5-table join | Q1, `ClientPortfolioSummary` view |
| `COALESCE` for nullable FK columns | Q2, Q4, Q7, all views |
| `CASE … WHEN` for conditional columns | Q1, Q2, Q5, all views |
| `NULLIF` to prevent division-by-zero | `ClientPortfolioSummary`, `BrokerPerformance` |

### Aggregates & Grouping

`COUNT`, `SUM`, `AVG`, `ROUND`, `MIN`, `MAX`; `GROUP BY`; `HAVING` (Q3, Q4)

### Subqueries

| Type | Where |
|------|-------|
| Correlated subquery | Q6 (clients with both investment types) |
| Derived-table subquery | Q8 (per-client market value), `BrokerPerformance` view (avoids fan-out) |
| Scalar subquery | Q8 (platform average via `CROSS JOIN`) |
| CTE (`WITH`) | Q5 (live price lookup reused across JOIN and WHERE) |

### Set Operations

| Operation | Where |
|-----------|-------|
| `UNION` | Q7 (NASDAQ stocks + selected US mutual funds) |
| `INTERSECT` | Q6 (clients diversified in both stocks and funds) |

### Views

| View | Purpose |
|------|---------|
| `ClientPortfolioSummary` | Cost basis, market value, unrealized P&L, return % per client |
| `BrokerPerformance` | Order pipeline, trade volume, execution rate per broker |
| `WatchlistAlerts` | Live alert status (`YES`/`NO`) per watchlist trigger |

All use `CREATE OR REPLACE VIEW`.

### Triggers

| Trigger | Event | Purpose |
|---------|-------|---------|
| `trg_orders_before_insert` | BEFORE INSERT on Orders | Reject qty ≤ 0 or price ≤ 0 via `SIGNAL SQLSTATE '45000'` |
| `trg_orders_before_update` | BEFORE UPDATE on Orders | Enforce immutability of executed/cancelled orders |
| `trg_transaction_before_insert` | BEFORE INSERT on stock_transaction | Block transaction on cancelled order; enforce 1-to-1 with Orders |
| `trg_transaction_after_insert` | AFTER INSERT on stock_transaction | Auto-execute linked order; upsert Tax with 15% capital gains; append Insights |
| `trg_portfolio_before_insert` | BEFORE INSERT on Portfolio | Reject zero-quantity or zero-price positions |

### Stored Procedure with Cursor

`sp_portfolio_value_report()` — iterates every client row-by-row using a cursor; computes cost basis, market value, unrealized P&L, and a risk-band label per client; emits two result sets (per-client snapshot + platform-wide summary).

Demonstrates: `DECLARE … CURSOR FOR`, `OPEN`, `FETCH … INTO`, `DECLARE CONTINUE HANDLER FOR NOT FOUND`, `LEAVE`, `CLOSE`, `TEMPORARY TABLE`.

### Transactions & Concurrency (documented in `docs/concurrency-recovery.md`)

`BEGIN` / `COMMIT` / `ROLLBACK` / `SAVEPOINT`; all four isolation levels (`READ UNCOMMITTED` → `SERIALIZABLE`); `SELECT … FOR UPDATE`; `SELECT … FOR SHARE`; `FOR UPDATE NOWAIT`; `FOR UPDATE SKIP LOCKED`; deadlock detection and prevention; MVCC internals.

### Recovery (documented in `docs/concurrency-recovery.md`)

InnoDB redo log (WAL), undo log, crash recovery sequence, checkpoints, `mysqldump --single-transaction`, binary log, point-in-time recovery.

### Normalization (documented in `docs/normalization.md`)

1NF through 4NF analysis for all 15 tables, including decompositions for three 3NF violations and a 4NF multi-valued dependency demonstration.

---

## Schema Overview

15 tables in FK dependency order:

```
Market
  └── Stocks
  └── Mutual_Funds
  └── IPO
       Client
       Broker
         └── Investments (Stock_ID XOR Mutual_Funds_ID)
               └── Portfolio    (Client + Investment)
               └── Watchlist    (Client + Investment)
                     └── Trigger_Price
               └── Orders       (Client + Broker + Investment)
                     └── stock_transaction (nullable Order_ID)
                           └── Tax       (Client + Broker + Year, UNIQUE)
               └── Documents    (Client + Broker)
               └── Insights     (Client + Market ± Stock ± Fund)
```

---

## Screenshots

> **To add a screenshot:** run the app, navigate to the page, take a screenshot, save it to `docs/screenshots/`, and replace the placeholder below.

| Page | Placeholder | Suggested capture |
|------|-------------|-------------------|
| Client list | `docs/screenshots/clients.png` | All 10 seed clients in the table |
| Add client form | `docs/screenshots/add-client.png` | Form filled in before submit |
| Portfolio — James Harrington | `docs/screenshots/portfolio-james.png` | AAPL + MSFT holdings with green P&L |
| Portfolio — Laura Schmidt | `docs/screenshots/portfolio-laura.png` | TSLA position showing red (loss) P&L |
| Place order form | `docs/screenshots/place-order.png` | Dropdowns populated, BUY selected |
| Summary dashboard | `docs/screenshots/summary.png` | All clients ranked by return % with colour-coded P&L |

---

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/er_diagram/er_diagram.md`](docs/er_diagram/er_diagram.md) | Mermaid ER diagram — all 15 tables with columns, PKs, FKs, and relationship lines |
| [`docs/schema-design.md`](docs/schema-design.md) | Textual ER description, cardinalities, 10 integrity issues found and fixed, FK dependency map |
| [`docs/normalization.md`](docs/normalization.md) | 1NF–4NF analysis for all 15 tables; decompositions for violations; 4NF MVD example |
| [`docs/concurrency-recovery.md`](docs/concurrency-recovery.md) | Transactions, ACID, isolation levels with anomaly scenarios, row locking, MVCC, WAL, crash recovery, backup and PITR |
