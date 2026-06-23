# Normalization Analysis — Portfolio Management System

---

## Notation

| Symbol | Meaning |
|--------|---------|
| `A → B` | A functionally determines B (FD) |
| `A ↠ B` | A multi-value determines B (MVD) |
| **PK** | Primary key |
| **CK** | Candidate key (alternate key that could serve as PK) |
| **NKA** | Non-key attribute |
| Underline | Primary key attribute |

A **functional dependency** `X → Y` holds when each value of X is associated with exactly one value of Y.  
A **multi-valued dependency** `X ↠ Y` holds when the set of Y values paired with a given X is independent of all other attributes in the relation.

---

## Normal Form Definitions (Summary)

| Form | Requirement |
|------|-------------|
| **1NF** | All attributes are atomic; no repeating groups; every row is uniquely identified |
| **2NF** | 1NF + every non-key attribute fully depends on the *entire* primary key (no partial dependencies) |
| **3NF** | 2NF + no transitive dependencies — non-key attributes depend only on the PK, not on other NKAs |
| **BCNF** | For *every* non-trivial FD `X → Y`, X must be a superkey (stricter than 3NF when multiple CKs overlap) |
| **4NF** | BCNF + no non-trivial multi-valued dependencies |

---

## 1NF Analysis

### What 1NF requires
- Every column holds one atomic value per row (no sets, lists, or packed composites).
- No repeating column groups (e.g., `Phone1`, `Phone2`, `Phone3`).
- A primary key exists to uniquely identify every row.

### Violations in the original specification — corrected before implementation

#### ① `Stocks.High_Low_52w` and `Stocks.High_Low_Day` — composite attributes

The original spec used a single column to store both a high and a low price.

**Violation:** A column like `High_Low_52w = "199.62 / 124.17"` packs two values into one field. Queries such as "find all stocks whose 52-week low is below $130" become impossible without string parsing.

**Decomposition applied:**
```
Before:  Stocks(Stock_ID, ..., High_Low_52w,  High_Low_Day)
After:   Stocks(Stock_ID, ..., High_52w, Low_52w, High_Day, Low_Day)
```

#### ② `IPO.Date_Range` — composite attribute

**Violation:** A single `Date_Range` column such as `"2023-09-13 to 2023-09-14"` is non-atomic. Range comparisons and overlap checks require splitting.

**Decomposition applied:**
```
Before:  IPO(IPO_ID, ..., Date_Range)
After:   IPO(IPO_ID, ..., Start_Date, End_Date)
```

### All 15 tables after corrections — 1NF status

| Table | Atomic values? | No repeating groups? | PK exists? | **1NF** |
|-------|---------------|----------------------|------------|---------|
| Market | ✓ | ✓ | Market_ID | ✅ |
| Stocks | ✓ (after split) | ✓ | Stock_ID | ✅ |
| Mutual_Funds | ✓ | ✓ | Mutual_Funds_ID | ✅ |
| IPO | ✓ (after split) | ✓ | IPO_ID | ✅ |
| Client | ✓ † | ✓ | Client_ID | ✅ |
| Broker | ✓ | ✓ | Broker_ID | ✅ |
| Investments | ✓ | ✓ | Investment_ID | ✅ |
| Portfolio | ✓ | ✓ | Portfolio_ID | ✅ |
| Watchlist | ✓ | ✓ | Watchlist_ID | ✅ |
| Trigger_Price | ✓ | ✓ | Alert_ID | ✅ |
| Orders | ✓ | ✓ | Order_ID | ✅ |
| stock_transaction | ✓ | ✓ | Transaction_ID | ✅ |
| Tax | ✓ | ✓ | Tax_ID | ✅ |
| Documents | ✓ | ✓ | Documents_ID | ✅ |
| Insights | ✓ | ✓ | Insight_ID | ✅ |

† `Client.Address` stores a full address as one string. Strictly this is a composite (street, city, state, zip). It is treated as atomic here because no query needs to filter on individual address components; decomposing it would add tables without analytical benefit. This is a documented design decision, not an oversight.

---

## 2NF Analysis

### What 2NF requires
Every non-key attribute must depend on the **entire** primary key — not just part of it. Partial dependencies can only arise when the primary key is composite (multi-column).

### Why all tables trivially satisfy 2NF with surrogate keys
Every table uses a single-column integer surrogate PK (`AUTO_INCREMENT`). With a single-attribute PK you cannot have a partial dependency by definition — a partial dependency requires two or more PK columns where a non-key attribute depends on only a subset of them.

### Natural composite key analysis
Even if surrogate PKs were replaced by natural composite keys, 2NF holds for every table.

| Table | Natural candidate key | NKA | Fully depends on entire CK? |
|-------|-----------------------|-----|-----------------------------|
| Tax | (Client_ID, Broker_ID, Tax_Year) | Profit, Loss, Tax | Yes — tax figures belong to the specific client-broker-year triple | ✅ |
| Portfolio | (Client_ID, Investment_ID) | Average_Price, Quantity | Yes — average cost and quantity are specific to one client's holding in one investment | ✅ |
| Watchlist | (Client_ID, Investment_ID) | — (no NKAs) | Trivially | ✅ |
| Trigger_Price | (Watchlist_ID, Trigger_Condition, Trigger_Price) | Notification_Type | Yes — notification method belongs to the full alert specification | ✅ |
| Documents | (Client_ID, Broker_ID, Document_Type, Date_Uploaded) | — (no NKAs) | Trivially | ✅ |

**Conclusion: all 15 tables satisfy 2NF.**

---

## 3NF Analysis

### What 3NF requires
No non-key attribute may be transitively dependent on the PK — i.e., no `PK → X → Y` where X is a non-key attribute.

Equivalently: every non-key attribute must depend *directly* on the PK and nothing else.

### Tables with no transitive dependencies (3NF satisfied)

These tables have no non-key attribute that determines another non-key attribute:

| Table | Reason |
|-------|--------|
| Market | Location does not determine Name or vice versa |
| Mutual_Funds | Symbol is a CK (superkey), not a NKA — covered under BCNF below |
| IPO | All attributes depend directly on IPO_ID; Symbol is not declared unique so cannot be a hidden CK |
| Client | Email is a CK — covered under BCNF below |
| Broker | License is a CK — covered under BCNF below |
| Portfolio | Average_Price and Quantity depend directly on Portfolio_ID |
| Watchlist | No NKAs beyond FK references |
| Trigger_Price | All attributes depend directly on Alert_ID |
| Orders | All attributes depend directly on Order_ID |
| Documents | All attributes depend directly on Documents_ID |

---

### Violation V1 — `Investments.Name` (transitive via `Stock_ID` / `Mutual_Funds_ID`)

**Table:** `Investments(Investment_ID, Market_ID, Investment_Type, Name, Stock_ID, Mutual_Funds_ID)`

**Functional dependencies present:**
```
Investment_ID → Stock_ID
Stock_ID      → Stocks.Name          ← Stock_ID is NOT a superkey of Investments
Investment_ID → Mutual_Funds_ID
Mutual_Funds_ID → Mutual_Funds.Name  ← Mutual_Funds_ID is NOT a superkey of Investments
```

`Investments.Name` mirrors `Stocks.Name` or `Mutual_Funds.Name` exactly. This is a transitive chain:

```
Investment_ID → Stock_ID → (Stocks) Name
```

`Stock_ID` is a non-key attribute of Investments yet it determines `Name`. This violates 3NF.

**Decomposition to 3NF:**
Remove `Name` from Investments. Derive it at query time:

```sql
-- 3NF-compliant Investments table
Investments(Investment_ID, Market_ID, Investment_Type, Stock_ID, Mutual_Funds_ID)

-- Name recovered via:
SELECT COALESCE(s.Name, mf.Name) AS Investment_Name
FROM Investments i
LEFT JOIN Stocks s ON i.Stock_ID = s.Stock_ID
LEFT JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID;
```

**Why it was retained:** The `Name` column is kept in the implemented schema as a denormalization for query convenience — it avoids an extra JOIN in the most common read path. This is an explicit trade-off: **write-time redundancy for read-time simplicity**. In a production system a trigger would keep `Investments.Name` in sync with its source table.

---

### Violation V2 — `Investments.Market_ID` for STOCK-type rows (transitive via `Stock_ID`)

**Functional dependency for STOCK-type rows:**
```
Stock_ID → Stocks.Market_ID   (a stock belongs to exactly one market)
```

For any row where `Investment_Type = 'STOCK'`:
```
Investment_ID → Stock_ID → Market_ID   ← transitive dependency
```

`Market_ID` is derivable from `Stock_ID → Stocks.Market_ID`, so it is transitively dependent for stock investments.

For `MUTUAL_FUND`-type rows there is no such path — `Mutual_Funds` has no `Market_ID` column — so `Market_ID` is a direct dependency for fund investments only.

**Decomposition to 3NF (type-split approach):**
```sql
-- Investments supertype (no Market_ID)
Investments(Investment_ID, Investment_Type, Stock_ID, Mutual_Funds_ID)

-- Subtype for stock investments — Market derived from Stocks
StockInvestment(Investment_ID FK, Stock_ID FK)
  -- Market_ID obtained via: StockInvestment → Stock_ID → Stocks.Market_ID

-- Subtype for fund investments — Market stored directly
FundInvestment(Investment_ID FK, Mutual_Funds_ID FK, Market_ID FK)
```

**Why it was retained:** Splitting into subtypes adds two joins to every portfolio/watchlist query and complicates the application layer significantly. `Market_ID` is kept directly on `Investments` as a **documented redundancy** with a note that for STOCK-type rows it must equal `Stocks.Market_ID`. This is enforced at insert time by the application and trigger layer.

---

### Violation V3 — `Insights.Total_PL` (derived from `Profit` and `Loss`)

**Table:** `Insights(Insight_ID, Client_ID, Market_ID, Stock_ID, Mutual_Funds_ID, Profit, Loss, Total_PL)`

**Functional dependency:**
```
(Profit, Loss) → Total_PL    where Total_PL = Profit − Loss
```

`Profit` and `Loss` are non-key attributes. `Total_PL` is determined entirely by them, not independently by `Insight_ID`. The chain is:

```
Insight_ID → (Profit, Loss) → Total_PL
```

This is a classic transitive dependency on a derived/computed attribute.

**Decomposition to 3NF:**
```sql
-- Remove Total_PL from the table
Insights(Insight_ID, Client_ID, Market_ID, Stock_ID, Mutual_Funds_ID, Profit, Loss)

-- Compute at query time — no information is lost:
SELECT Insight_ID, Client_ID, Profit, Loss,
       ROUND(Profit - Loss, 2) AS Total_PL
FROM Insights;
```

**Status:** This is a genuine 3NF violation. The column is retained in the implemented schema to satisfy the original specification, but it **should be removed** in a strict normalization. Any code updating `Profit` or `Loss` must also update `Total_PL` to prevent inconsistency.

---

### Violation V4 — `stock_transaction.Client_ID` and `Broker_ID` (transitive via `Order_ID`)

**Table:** `stock_transaction(Transaction_ID, Order_ID, Client_ID, Broker_ID, Type, Price, Transaction_Date)`

When `Order_ID IS NOT NULL`:
```
Order_ID → Client_ID    (Orders stores the client who placed the order)
Order_ID → Broker_ID    (Orders stores the broker who handled the order)
```

The transitive chains:
```
Transaction_ID → Order_ID → Client_ID
Transaction_ID → Order_ID → Broker_ID
```

`Client_ID` and `Broker_ID` are redundantly stored when `Order_ID` is present.

**Strict 3NF decomposition:**
```sql
-- Remove Client_ID and Broker_ID; recover via Order_ID join
stock_transaction(Transaction_ID, Order_ID, Type, Price, Transaction_Date)

-- Client and Broker recovered via:
SELECT st.*, o.Client_ID, o.Broker_ID
FROM stock_transaction st
LEFT JOIN Orders o ON st.Order_ID = o.Order_ID;
```

**Why it was retained:** When `Order_ID IS NULL` (manual / off-platform trades, rows 9–10 in seed data), there is no order to join through. Removing `Client_ID` and `Broker_ID` from the table would make these rows untraceable. The denormalization is **necessary for nullable-FK correctness**, not merely convenient. This is an accepted 3NF violation with a clear justification.

---

### 3NF Summary

| Table | Violation | Decomposition status |
|-------|-----------|---------------------|
| Investments | V1: `Name` transitive via `Stock_ID`/`Mutual_Funds_ID` | Retained (documented denorm) |
| Investments | V2: `Market_ID` transitive via `Stock_ID` for STOCK rows | Retained (documented denorm) |
| Insights | V3: `Total_PL` derived from `(Profit, Loss)` | Retained (spec requirement — should be removed) |
| stock_transaction | V4: `Client_ID`, `Broker_ID` transitive via `Order_ID` | Retained (required for NULL `Order_ID` rows) |
| All others | No violations | — |

---

## BCNF Analysis

### What BCNF adds over 3NF
BCNF is stricter: for **every** non-trivial FD `X → Y` in the relation, `X` must be a **superkey**. The gap between 3NF and BCNF only appears when a table has **multiple overlapping candidate keys**, where one CK partially covers attributes also covered by another CK.

### Tables with multiple candidate keys

These tables have both a surrogate PK and a natural unique key (second CK):

#### `Stocks` — CK1: `{Stock_ID}`, CK2: `{Symbol}`

FDs:
```
Stock_ID → {Market_ID, Symbol, Name, Last_Traded_Price, High_52w, Low_52w, High_Day, Low_Day}
Symbol   → {Stock_ID, Market_ID, Name, Last_Traded_Price, High_52w, Low_52w, High_Day, Low_Day}
```
Both determinants are superkeys. **BCNF satisfied. ✅**

#### `Mutual_Funds` — CK1: `{Mutual_Funds_ID}`, CK2: `{Symbol}`

FDs:
```
Mutual_Funds_ID → {Symbol, Name, Price}
Symbol          → {Mutual_Funds_ID, Name, Price}
```
Both are superkeys. **BCNF satisfied. ✅**

#### `Client` — CK1: `{Client_ID}`, CK2: `{Email}`

FDs:
```
Client_ID → {Name, Phone, Email, Address}
Email     → {Client_ID, Name, Phone, Address}
```
Both are superkeys. **BCNF satisfied. ✅**

#### `Broker` — CK1: `{Broker_ID}`, CK2: `{License}`

FDs:
```
Broker_ID → {Name, License}
License   → {Broker_ID, Name}
```
Both are superkeys. **BCNF satisfied. ✅**

#### `Tax` — CK1: `{Tax_ID}`, CK2: `{(Client_ID, Broker_ID, Tax_Year)}`

FDs:
```
Tax_ID                          → {Client_ID, Broker_ID, Tax_Year, Profit, Loss, Tax}
(Client_ID, Broker_ID, Tax_Year) → {Tax_ID, Profit, Loss, Tax}
```
Both are superkeys. **BCNF satisfied. ✅**

### Single-CK tables and BCNF

For all remaining tables the only candidate key is the surrogate PK. Since every non-trivial FD has the PK as its determinant (after correcting 3NF violations V1–V4), BCNF is automatically satisfied.

### BCNF and the 3NF violations

Violations V1 and V2 in `Investments` are simultaneously 3NF *and* BCNF violations:

```
Stock_ID → Name        (in Investments — Stock_ID is not a superkey of Investments)
Stock_ID → Market_ID   (in Investments — same)
```

Applying the 3NF decomposition above (removing `Name`, splitting Market) resolves both violations. After decomposition, all FDs in the resulting tables have a superkey as their determinant → **BCNF**.

---

## 4NF Analysis

### What 4NF requires
BCNF + no non-trivial multi-valued dependency `X ↠ Y` where X is not a superkey.

An MVD `X ↠ Y` in relation R(X, Y, Z) holds when: for every X value, the set of associated Y values is completely independent of the Z values. This forces redundant combinations of Y and Z rows to represent all possibilities.

### Checking for MVDs in the implemented schema

Most tables contain no MVDs because their attributes are specific instances (one order, one transaction, one document upload) rather than independent multi-valued sets.

| Table | Potential MVD? | Conclusion |
|-------|---------------|------------|
| Market, Client, Broker, Stocks, Mutual_Funds | None — all attributes are single-valued facts | ✅ 4NF |
| Portfolio | Client holds multiple investments, but Average_Price and Quantity are *specific* to each (Client, Investment) pair — not independent sets | ✅ 4NF |
| Watchlist | (Client_ID, Investment_ID) pairs — no third attribute to form an MVD | ✅ 4NF |
| Orders | Broker and Investment are chosen *together* for a specific trade — not independent | ✅ 4NF |
| Tax | Profit/Loss/Tax are specific to (Client, Broker, Year) — not independent sets | ✅ 4NF |

### 4NF violation — demonstrated on a hypothetical flat `Documents` design

#### The problematic design

Suppose a brokerage policy requires: *"every client who works with a broker must submit all required document types to that broker."* A naïve designer might create:

```
ClientDocBroker(Client_ID, Broker_ID, Document_Type)
```

Sample data for Client 1 (works with Brokers 1 and 2; must submit KYC and Tax Form):

| Client_ID | Broker_ID | Document_Type |
|-----------|-----------|---------------|
| 1 | 1 | KYC Verification |
| 1 | 1 | Tax Form W-9 |
| 1 | 2 | KYC Verification |
| 1 | 2 | Tax Form W-9 |
| 2 | 1 | KYC Verification |
| 2 | 1 | Account Agreement |

#### The MVD

The set of brokers a client works with is **independent** of the set of document types they must file, and vice versa:

```
Client_ID ↠ Broker_ID        (a client works with brokers independently of document type)
Client_ID ↠ Document_Type    (a client needs document types independently of which broker)
```

Both MVDs hold with `Client_ID` as the determinant, and `Client_ID` is not a superkey (it appears in multiple rows). This violates 4NF.

**The redundancy problem:** If Client 1 adds a third document type "Account Agreement", we must insert *two* new rows — one per broker — even though no new (Client, Broker) relationship was established. Conversely, adding a new broker requires inserting one row per document type. Update anomalies arise immediately.

#### Decomposition to 4NF

Separate the two independent multi-valued facts into two tables:

```sql
-- Which brokers a client works with
ClientBroker(Client_ID, Broker_ID)
  PK: (Client_ID, Broker_ID)

-- Which document types a client must submit (platform-wide requirement)
RequiredDocType(Client_ID, Document_Type)
  PK: (Client_ID, Document_Type)
```

Each table now has only one non-trivial MVD whose determinant is the full key → **4NF satisfied**.

#### How our implemented `Documents` table avoids this

Our actual schema does not model "required document types per client-broker pair" as a cross-product. Instead, each row is a **specific upload event**:

```sql
Documents(Documents_ID PK, Client_ID, Broker_ID, Document_Type, Date_Uploaded)
```

The addition of `Documents_ID` and `Date_Uploaded` collapses the multi-valued relationship into a set of individual facts. There is no policy-driven cross-product requirement — a KYC uploaded on 2023-01-10 for Broker 1 is a distinct, timestamped document that does not imply any requirement for Broker 2. The MVD cannot form because the Y-values (broker, document type) are not independent; they belong to the same specific event.

**Result: the implemented `Documents` table satisfies 4NF. ✅**

---

## Complete Normal Form Summary

| Table | 1NF | 2NF | 3NF | BCNF | 4NF | Notes |
|-------|-----|-----|-----|------|-----|-------|
| Market | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Stocks | ✅* | ✅ | ✅ | ✅ | ✅ | *After splitting High_Low columns |
| Mutual_Funds | ✅ | ✅ | ✅ | ✅ | ✅ | |
| IPO | ✅* | ✅ | ✅ | ✅ | ✅ | *After splitting Date_Range |
| Client | ✅ | ✅ | ✅ | ✅ | ✅ | Address treated as atomic |
| Broker | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Investments | ✅ | ✅ | ⚠️ | ⚠️ | ✅ | V1, V2 — retained denorms documented |
| Portfolio | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Watchlist | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Trigger_Price | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Orders | ✅ | ✅ | ✅ | ✅ | ✅ | |
| stock_transaction | ✅ | ✅ | ⚠️ | ✅ | ✅ | V4 — required for nullable FK |
| Tax | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Documents | ✅ | ✅ | ✅ | ✅ | ✅ | Avoids 4NF violation by design |
| Insights | ✅ | ✅ | ⚠️ | ✅ | ✅ | V3 — Total_PL should be removed |

**Legend:** ✅ Satisfied &nbsp;|&nbsp; ⚠️ Violation present (retained with documented justification)

---

## Decomposition Reference (strict normalization)

If the schema were to be fully normalized to 3NF/BCNF with no retained denormalizations, the following changes would be applied:

```sql
-- V1: Remove Investments.Name
ALTER TABLE Investments DROP COLUMN Name;
-- Recover at query time: COALESCE(s.Name, mf.Name)

-- V2: Enforce Market_ID matches for STOCK rows (or split into subtypes)
-- For STOCK rows: Market_ID must equal Stocks.Market_ID
-- Add a trigger to enforce this invariant instead of splitting the table.

-- V3: Remove Insights.Total_PL
ALTER TABLE Insights DROP COLUMN Total_PL;
-- Recover at query time: Profit - Loss AS Total_PL

-- V4: For stock_transaction rows where Order_ID IS NOT NULL,
-- Client_ID and Broker_ID are redundant.
-- Accepted as necessary — no change applied.
```
