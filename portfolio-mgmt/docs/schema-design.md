# Schema Design — Portfolio Management System

---

## Part A: Textual ER Description with Cardinalities

### Entities and Relationships

**Client — Portfolio**
One client can hold many portfolio positions; each portfolio position belongs to exactly one client.
`Client (1) ──< Portfolio (M)`

**Client — Transaction**
One client can make many transactions; each transaction belongs to one client.
`Client (1) ──< Transaction (M)`

**Client — Orders**
One client can place many orders; each order belongs to one client.
`Client (1) ──< Orders (M)`

**Client — Tax**
One client can have many tax records (one per fiscal year per broker); each tax record belongs to one client.
`Client (1) ──< Tax (M)`

**Client — Watchlist**
One client can have many watchlist entries; each entry belongs to one client.
`Client (1) ──< Watchlist (M)`

**Client — Documents**
One client can have many documents; each document is associated with one client.
`Client (1) ──< Documents (M)`

**Client — Insights**
One client can have many insight records; each insight belongs to one client.
`Client (1) ──< Insights (M)`

**Broker — Transaction**
One broker facilitates many transactions; each transaction is handled by one broker.
`Broker (1) ──< Transaction (M)`

**Broker — Orders**
One broker can handle many orders; each order is assigned to one broker.
`Broker (1) ──< Orders (M)`

**Broker — Tax**
One broker is associated with many tax records; each tax record references one broker.
`Broker (1) ──< Tax (M)`

**Broker — Documents**
One broker can be linked to many documents.
`Broker (1) ──< Documents (M)`

**Market — Stocks**
One market lists many stocks; each stock is listed on one market.
`Market (1) ──< Stocks (M)`

**Market — Mutual_Funds** *(via Investments)*
Mutual funds are linked to a market through the Investments table.

**Market — Investments**
One market can host many investments; each investment belongs to one market.
`Market (1) ──< Investments (M)`

**Market — IPO**
One market hosts many IPOs; each IPO is listed on one market.
`Market (1) ──< IPO (M)`

**Market — Insights**
Insights are scoped to a market context.
`Market (1) ──< Insights (M)`

**Investments — Stocks** *(supertype–subtype)*
An investment of type STOCK references exactly one stock; a stock may be referenced by one investment record.
`Investments (1) ── Stocks (1)` *(nullable FK, exclusive with Mutual_Funds_ID)*

**Investments — Mutual_Funds** *(supertype–subtype)*
An investment of type MUTUAL_FUND references exactly one mutual fund.
`Investments (1) ── Mutual_Funds (1)` *(nullable FK, exclusive with Stock_ID)*

**Investments — Portfolio**
One investment can appear in many portfolio positions; each portfolio position tracks one investment.
`Investments (1) ──< Portfolio (M)`

**Investments — Watchlist**
One investment can be on many clients' watchlists.
`Investments (1) ──< Watchlist (M)`

**Investments — Orders**
One investment can be the target of many orders.
`Investments (1) ──< Orders (M)`

**Orders — Transaction** *(1:0..1)*
An executed order produces at most one transaction; a transaction traces back to the order that triggered it.
`Orders (1) ──○ Transaction (0..1)`

**Watchlist — Trigger_Price**
One watchlist entry can have many price alerts; each alert belongs to one watchlist entry.
`Watchlist (1) ──< Trigger_Price (M)`

**Stocks — Insights**
Insights can be scoped to a specific stock (nullable).
`Stocks (1) ──○< Insights (M)`

**Mutual_Funds — Insights**
Insights can be scoped to a specific mutual fund (nullable).
`Mutual_Funds (1) ──○< Insights (M)`

---

## Part B: Normalized Table Definitions

> All monetary values use `DECIMAL(15,2)`. All IDs use `INT AUTO_INCREMENT`.
> Composite and multi-valued attributes from the original spec have been decomposed (see Issues section).

---

### Client
| Column     | Type          | Constraints            |
|------------|---------------|------------------------|
| Client_ID  | INT           | PK, AUTO_INCREMENT     |
| Name       | VARCHAR(100)  | NOT NULL               |
| Phone      | VARCHAR(20)   |                        |
| Email      | VARCHAR(100)  | NOT NULL, UNIQUE       |
| Address    | VARCHAR(255)  |                        |

---

### Broker
| Column     | Type         | Constraints            |
|------------|--------------|------------------------|
| Broker_ID  | INT          | PK, AUTO_INCREMENT     |
| Name       | VARCHAR(100) | NOT NULL               |
| License    | VARCHAR(50)  | NOT NULL, UNIQUE       |

---

### Market
| Column    | Type         | Constraints        |
|-----------|--------------|--------------------|
| Market_ID | INT          | PK, AUTO_INCREMENT |
| Name      | VARCHAR(100) | NOT NULL           |
| Location  | VARCHAR(100) |                    |

---

### Stocks
> `High_Low_52w` and `High_Low_Day` split into four columns (1NF fix — see Issues #4).

| Column           | Type          | Constraints              |
|------------------|---------------|--------------------------|
| Stock_ID         | INT           | PK, AUTO_INCREMENT       |
| Market_ID        | INT           | FK → Market(Market_ID)   |
| Symbol           | VARCHAR(10)   | NOT NULL, UNIQUE         |
| Name             | VARCHAR(100)  | NOT NULL                 |
| Last_Traded_Price| DECIMAL(15,2) |                          |
| High_52w         | DECIMAL(15,2) |                          |
| Low_52w          | DECIMAL(15,2) |                          |
| High_Day         | DECIMAL(15,2) |                          |
| Low_Day          | DECIMAL(15,2) |                          |

---

### Mutual_Funds
> `Quantity` removed — it is a per-holding attribute, not a fund-level attribute (see Issues #6).

| Column          | Type          | Constraints        |
|-----------------|---------------|--------------------|
| Mutual_Funds_ID | INT           | PK, AUTO_INCREMENT |
| Name            | VARCHAR(100)  | NOT NULL           |
| Symbol          | VARCHAR(10)   | NOT NULL, UNIQUE   |
| Price           | DECIMAL(15,2) |                    |

---

### IPO
> `Date_Range` split into `Start_Date` / `End_Date` (1NF fix — see Issues #5).
> `Market_ID` added to link IPO to a market (see Issues #8).

| Column    | Type          | Constraints              |
|-----------|---------------|--------------------------|
| IPO_ID    | INT           | PK, AUTO_INCREMENT       |
| Market_ID | INT           | FK → Market(Market_ID)   |
| Name      | VARCHAR(100)  | NOT NULL                 |
| Symbol    | VARCHAR(10)   | NOT NULL                 |
| Start_Date| DATE          |                          |
| End_Date  | DATE          |                          |
| Price     | DECIMAL(15,2) |                          |
| Quantity  | INT           |                          |

---

### Investments
> Acts as a supertype for Stock and Mutual Fund holdings.
> Exactly one of `Stock_ID` or `Mutual_Funds_ID` must be non-null (enforced by `Investment_Type` + application logic or CHECK constraint).

| Column          | Type                        | Constraints                           |
|-----------------|-----------------------------|---------------------------------------|
| Investment_ID   | INT                         | PK, AUTO_INCREMENT                    |
| Market_ID       | INT                         | FK → Market(Market_ID), NOT NULL      |
| Investment_Type | ENUM('STOCK','MUTUAL_FUND') | NOT NULL                              |
| Name            | VARCHAR(100)                | NOT NULL                              |
| Stock_ID        | INT                         | FK → Stocks(Stock_ID), NULLABLE       |
| Mutual_Funds_ID | INT                         | FK → Mutual_Funds(Mutual_Funds_ID), NULLABLE |

**CHECK constraint:** `(Stock_ID IS NOT NULL) XOR (Mutual_Funds_ID IS NOT NULL)`

---

### Portfolio
| Column        | Type          | Constraints                             |
|---------------|---------------|-----------------------------------------|
| Portfolio_ID  | INT           | PK, AUTO_INCREMENT                      |
| Client_ID     | INT           | FK → Client(Client_ID), NOT NULL        |
| Investment_ID | INT           | FK → Investments(Investment_ID), NOT NULL |
| Average_Price | DECIMAL(15,2) |                                         |
| Quantity      | INT           |                                         |

---

### Orders
> `Transaction_ID` removed — Transaction now holds the FK back to Orders (see Issues #3).

| Column        | Type                                    | Constraints                               |
|---------------|-----------------------------------------|-------------------------------------------|
| Order_ID      | INT                                     | PK, AUTO_INCREMENT                        |
| Client_ID     | INT                                     | FK → Client(Client_ID), NOT NULL          |
| Broker_ID     | INT                                     | FK → Broker(Broker_ID), NOT NULL          |
| Investment_ID | INT                                     | FK → Investments(Investment_ID), NOT NULL |
| Status        | ENUM('PENDING','EXECUTED','CANCELLED')  | NOT NULL, DEFAULT 'PENDING'               |
| Price         | DECIMAL(15,2)                           |                                           |
| Quantity      | INT                                     |                                           |
| Order_Date    | DATETIME                                | DEFAULT CURRENT_TIMESTAMP                 |

---

### Transaction
> Renamed to `stock_transaction` in SQL to avoid MySQL reserved word conflict (see Issues #9).
> `Order_ID` FK added here (moved from Orders) to break circular dependency.

| Column          | Type                | Constraints                          |
|-----------------|---------------------|--------------------------------------|
| Transaction_ID  | INT                 | PK, AUTO_INCREMENT                   |
| Order_ID        | INT                 | FK → Orders(Order_ID), NULLABLE      |
| Client_ID       | INT                 | FK → Client(Client_ID), NOT NULL     |
| Broker_ID       | INT                 | FK → Broker(Broker_ID), NOT NULL     |
| Type            | ENUM('BUY','SELL')  | NOT NULL                             |
| Price           | DECIMAL(15,2)       |                                      |
| Transaction_Date| DATETIME            | DEFAULT CURRENT_TIMESTAMP            |

---

### Tax
> `Tax_ID` PK added — original had no primary key (see Issues #1).
> `Tax_Year` added — without it, only one tax record per client-broker pair is possible.

| Column    | Type          | Constraints                          |
|-----------|---------------|--------------------------------------|
| Tax_ID    | INT           | PK, AUTO_INCREMENT                   |
| Client_ID | INT           | FK → Client(Client_ID), NOT NULL     |
| Broker_ID | INT           | FK → Broker(Broker_ID), NOT NULL     |
| Tax_Year  | YEAR          | NOT NULL                             |
| Profit    | DECIMAL(15,2) |                                      |
| Loss      | DECIMAL(15,2) |                                      |
| Tax       | DECIMAL(15,2) |                                      |

**Unique constraint:** `(Client_ID, Broker_ID, Tax_Year)`

---

### Watchlist
| Column        | Type | Constraints                               |
|---------------|------|-------------------------------------------|
| Watchlist_ID  | INT  | PK, AUTO_INCREMENT                        |
| Client_ID     | INT  | FK → Client(Client_ID), NOT NULL          |
| Investment_ID | INT  | FK → Investments(Investment_ID), NOT NULL |

---

### Trigger_Price
| Column             | Type                          | Constraints                              |
|--------------------|-------------------------------|------------------------------------------|
| Alert_ID           | INT                           | PK, AUTO_INCREMENT                       |
| Watchlist_ID       | INT                           | FK → Watchlist(Watchlist_ID), NOT NULL   |
| Trigger_Condition  | ENUM('ABOVE','BELOW','EQUALS')| NOT NULL                                 |
| Trigger_Price      | DECIMAL(15,2)                 | NOT NULL                                 |
| Notification_Type  | ENUM('EMAIL','SMS','PUSH')    | NOT NULL                                 |

---

### Documents
| Column        | Type        | Constraints                          |
|---------------|-------------|--------------------------------------|
| Documents_ID  | INT         | PK, AUTO_INCREMENT                   |
| Client_ID     | INT         | FK → Client(Client_ID), NOT NULL     |
| Broker_ID     | INT         | FK → Broker(Broker_ID), NOT NULL     |
| Document_Type | VARCHAR(50) |                                      |
| Date_Uploaded | DATE        |                                      |

---

### Insights
> `Insight_ID` PK added — original had no primary key (see Issues #2).
> `Stock_ID` and `Mutual_Funds_ID` are nullable (an insight may be for stock, fund, or market-level).

| Column          | Type          | Constraints                                   |
|-----------------|---------------|-----------------------------------------------|
| Insight_ID      | INT           | PK, AUTO_INCREMENT                            |
| Client_ID       | INT           | FK → Client(Client_ID), NOT NULL              |
| Market_ID       | INT           | FK → Market(Market_ID), NOT NULL              |
| Stock_ID        | INT           | FK → Stocks(Stock_ID), NULLABLE               |
| Mutual_Funds_ID | INT           | FK → Mutual_Funds(Mutual_Funds_ID), NULLABLE  |
| Profit          | DECIMAL(15,2) |                                               |
| Loss            | DECIMAL(15,2) |                                               |
| Total_PL        | DECIMAL(15,2) |                                               |

---

## Issues Found and Fixes Applied

### Issue 1 — Tax has no primary key
**Problem:** `Tax(Client_ID FK, Broker_ID FK, ...)` has no PK. Using `(Client_ID, Broker_ID)` as composite PK would limit a client to one tax record per broker ever.
**Fix:** Added `Tax_ID INT AUTO_INCREMENT` as PK. Added `Tax_Year YEAR` + unique constraint on `(Client_ID, Broker_ID, Tax_Year)`.

---

### Issue 2 — Insights has no primary key
**Problem:** `Insights(Client_ID FK, Stock_ID FK, ...)` has no PK. The FK columns can't serve as a reliable composite PK since both `Stock_ID` and `Mutual_Funds_ID` are nullable.
**Fix:** Added `Insight_ID INT AUTO_INCREMENT` as PK.

---

### Issue 3 — Circular FK: Orders ↔ Transaction
**Problem:** `Orders.Transaction_ID FK → Transaction` creates a circular dependency because logically a Transaction is the *result* of an Order being executed. Having the FK in Orders means you can't insert an Order until the Transaction exists, and you can't insert a Transaction until the Order exists — a deadlock.
**Fix:** Removed `Transaction_ID` from Orders. Added `Order_ID INT NULLABLE FK → Orders` in Transaction. An order is inserted first (with no transaction); when executed, a Transaction row is created referencing the order.

---

### Issue 4 — Composite attributes in Stocks violate 1NF
**Problem:** `High_Low_52w` and `High_Low_Day` each pack two values into one column.
**Fix:** Split into `High_52w`, `Low_52w`, `High_Day`, `Low_Day`.

---

### Issue 5 — Composite attribute in IPO violates 1NF
**Problem:** `Date_Range` packs a start and end date into one column.
**Fix:** Split into `Start_Date DATE` and `End_Date DATE`.

---

### Issue 6 — Mutual_Funds.Quantity is misplaced
**Problem:** `Quantity` on a mutual fund describes how many units exist globally — that's not meaningful at the fund-definition level. Quantity is a per-client, per-portfolio attribute.
**Fix:** Removed `Quantity` from Mutual_Funds. It already exists in Portfolio.

---

### Issue 7 — Investments supertype: Stock_ID and Mutual_Funds_ID must be mutually exclusive
**Problem:** Both `Stock_ID` and `Mutual_Funds_ID` exist in Investments. If both are non-null, the row is ambiguous.
**Fix:** Added `Investment_Type ENUM('STOCK','MUTUAL_FUND')`. Both FKs are nullable. A CHECK constraint enforces that exactly one is set: `(Stock_ID IS NOT NULL) XOR (Mutual_Funds_ID IS NOT NULL)`.

---

### Issue 8 — IPO is an isolated island (no FK to Market)
**Problem:** `IPO` has no foreign key — it can't be queried in relation to any other entity.
**Fix:** Added `Market_ID FK → Market` so IPOs are associated with the exchange they list on.

---

### Issue 9 — TRANSACTION is a MySQL reserved word
**Problem:** Naming a table `Transaction` will require backtick escaping in every SQL statement and risks parse errors.
**Fix:** Use `stock_transaction` as the physical table name in SQL files. The logical entity name remains Transaction in ER diagrams.

---

### Issue 10 — Redundant Market_ID in Investments (minor)
**Observation:** `Investments.Market_ID` and `Stocks.Market_ID` both point to Market. For stock-type investments, the market is derivable via `Investments.Stock_ID → Stocks.Market_ID`. This is a minor redundancy (not a normalization violation since Investments is not fully dependent on Stock_ID alone).
**Decision:** Retain `Investments.Market_ID` — it is required for mutual fund investments (which have no direct Market link) and simplifies queries that need market context without joining through Stocks.

---

## FK Dependency Map (safe insertion order)

```
Market
Stocks        → Market
Mutual_Funds
IPO           → Market
Client
Broker
Investments   → Market, Stocks, Mutual_Funds
Portfolio     → Client, Investments
Watchlist     → Client, Investments
Trigger_Price → Watchlist
Orders        → Client, Broker, Investments
stock_transaction → Client, Broker, Orders
Tax           → Client, Broker
Documents     → Client, Broker
Insights      → Client, Market, Stocks, Mutual_Funds
```

Tables must be created in the order above to satisfy FK constraints.
