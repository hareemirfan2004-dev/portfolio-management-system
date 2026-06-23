# Concurrency Control & Recovery — Portfolio Management System

---

## Engine Foundation

Every table in this database uses the **InnoDB** storage engine (MySQL 8.4 default). InnoDB is the only MySQL engine that provides:

- Full ACID transactions
- Row-level locking (not table-level)
- Multi-Version Concurrency Control (MVCC)
- Crash-safe redo and undo logs
- Foreign key enforcement

All concurrency and recovery guarantees discussed in this document are InnoDB features. MyISAM, MEMORY, and other engines do not support transactions at all.

---

## Part 1 — Transactions

### ACID Properties

| Property | What it guarantees | How InnoDB delivers it |
|----------|-------------------|----------------------|
| **Atomicity** | All operations in a transaction commit together or none do | Undo log — on ROLLBACK, every change is reversed |
| **Consistency** | A transaction can only bring the DB from one valid state to another | Constraints checked at commit; triggers fire within the same transaction |
| **Isolation** | Concurrent transactions cannot see each other's uncommitted work | MVCC + locking (detail below) |
| **Durability** | A committed transaction survives a crash | Redo log flushed to disk before the COMMIT acknowledgment is sent |

---

### Basic Transaction Syntax

```sql
-- Start a transaction explicitly.
-- Autocommit is ON by default in MySQL; BEGIN suspends it for this block.
BEGIN;

-- ... one or more DML statements ...

COMMIT;     -- make all changes permanent
-- OR
ROLLBACK;   -- undo all changes since BEGIN
```

Any DML (`INSERT`, `UPDATE`, `DELETE`) run outside a `BEGIN` block is auto-committed immediately as its own one-statement transaction.

---

### Example T1 — Placing a BUY Order (multi-table atomic write)

A broker submits a BUY order for Client 3 (50 shares of AAPL at $189.30). The operation must atomically insert the order and, once executed, insert the matching transaction. If either step fails, neither row should persist.

```sql
BEGIN;

-- Step 1: record the order
INSERT INTO Orders (Client_ID, Broker_ID, Investment_ID, Status, Price, Quantity)
VALUES (3, 2, 1, 'PENDING', 189.30, 50);

SET @new_order_id = LAST_INSERT_ID();

-- Step 2: record the execution (triggers trg_transaction_after_insert,
--         which auto-flips Order.Status → EXECUTED and upserts Tax)
INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price)
VALUES (@new_order_id, 3, 2, 'BUY', 189.30);

COMMIT;
-- Both rows are visible to other sessions only after this line.
```

If the second INSERT fails (e.g. the trigger rejects it because the order is already settled), the ROLLBACK issued by the trigger's SIGNAL propagates up and neither row is committed.

---

### Example T2 — SELL with Explicit Rollback on Error

A SELL order is processed. If the client's Portfolio row shows fewer shares than requested, the transaction is rolled back before any data changes.

```sql
BEGIN;

-- Lock the Portfolio row immediately so no concurrent SELL can read
-- the same quantity and both proceed (see SELECT FOR UPDATE below).
SELECT Quantity, Average_Price
INTO   @held_qty, @avg_cost
FROM   Portfolio
WHERE  Client_ID = 5 AND Investment_ID = 3
FOR UPDATE;

-- Validate server-side before writing anything
IF @held_qty < 20 THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient shares for this sell order.';
END IF;

INSERT INTO Orders (Client_ID, Broker_ID, Investment_ID, Status, Price, Quantity)
VALUES (5, 3, 3, 'PENDING', 172.63, 20);

SET @new_order_id = LAST_INSERT_ID();

INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price)
VALUES (@new_order_id, 5, 3, 'SELL', 172.63);

-- Reduce the holding
UPDATE Portfolio
SET    Quantity = Quantity - 20
WHERE  Client_ID = 5 AND Investment_ID = 3;

COMMIT;
```

---

### Example T3 — SAVEPOINTs for Partial Rollback

A batch operation processes a list of clients. If one client's update fails, only that client's work is rolled back; the others are kept.

```sql
BEGIN;

-- Client 1's tax update
SAVEPOINT sp_client1;
UPDATE Tax SET Profit = Profit + 500.00, Tax = Tax + 75.00
WHERE Client_ID = 1 AND Tax_Year = 2023;
-- (assume success — no rollback to sp_client1)

-- Client 2's tax update
SAVEPOINT sp_client2;
UPDATE Tax SET Profit = Profit + 800.00, Tax = Tax + 120.00
WHERE Client_ID = 2 AND Tax_Year = 2023;
-- Suppose validation catches an error for Client 2:
ROLLBACK TO SAVEPOINT sp_client2;
-- Client 2's UPDATE is undone; Client 1's UPDATE is still live in this transaction.

-- Release the savepoint (frees its undo memory; optional but tidy)
RELEASE SAVEPOINT sp_client2;

-- Commit what succeeded
COMMIT;
-- Only Client 1's change is persisted.
```

`ROLLBACK TO SAVEPOINT` does **not** end the transaction — it only reverses work back to that marker. The transaction continues until an explicit `COMMIT` or `ROLLBACK`.

---

## Part 2 — Isolation Levels

Isolation controls what a transaction can see about other concurrent transactions. MySQL InnoDB supports four standard SQL isolation levels.

### The Four Anomalies

| Anomaly | Description |
|---------|-------------|
| **Dirty read** | Reading uncommitted data from another transaction |
| **Non-repeatable read** | Reading the same row twice and getting different values because another transaction committed an UPDATE between reads |
| **Phantom read** | A query returns different sets of rows because another transaction committed INSERTs or DELETEs between two identical queries |
| **Lost update** | Two transactions read the same value, compute an update independently, and one overwrites the other's result |

### Isolation Level Matrix

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read | Lost Update |
|----------------|-----------|---------------------|-------------|------------|
| `READ UNCOMMITTED` | ✗ Possible | ✗ Possible | ✗ Possible | ✗ Possible |
| `READ COMMITTED` | ✓ Prevented | ✗ Possible | ✗ Possible | ✗ Possible |
| `REPEATABLE READ` ← **MySQL default** | ✓ Prevented | ✓ Prevented | ✓ Prevented* | ✗ Possible without locking |
| `SERIALIZABLE` | ✓ Prevented | ✓ Prevented | ✓ Prevented | ✓ Prevented |

*InnoDB's MVCC snapshot prevents phantom reads in **plain SELECT** at REPEATABLE READ. However, writes (UPDATE/DELETE) use current-read semantics and can still interact with new rows — use `FOR UPDATE` or `SERIALIZABLE` when phantom-proofing writes.

---

### Setting the Isolation Level

```sql
-- For the current session only (most common in application code)
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- For the next single transaction only
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Globally (takes effect for new connections — requires SUPER privilege)
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Verify
SELECT @@transaction_isolation;
```

---

### Anomaly Scenarios in the Portfolio Context

#### Dirty Read (prevented at READ COMMITTED and above)

```
Session A                               Session B
─────────────────────────────────────   ───────────────────────────────────────
BEGIN;
UPDATE Stocks
  SET Last_Traded_Price = 210.00
  WHERE Stock_ID = 1;                   -- AAPL price updated but NOT committed

                                        -- At READ UNCOMMITTED, Session B would see 210.00
                                        -- and might place an order at a price that never
                                        -- actually committed (Session A may ROLLBACK to 189.30).
                                        SELECT Last_Traded_Price FROM Stocks
                                        WHERE Stock_ID = 1;
                                        -- READ COMMITTED: still sees 189.30 (committed value)

ROLLBACK;
-- Price reverts to 189.30
```

**Risk in this schema:** A client placing an order based on a dirty stock price could trade at a phantom price. `READ COMMITTED` is the minimum safe level for order placement.

---

#### Non-Repeatable Read (prevented at REPEATABLE READ and above)

```
Session A                               Session B
─────────────────────────────────────   ───────────────────────────────────────
BEGIN;
SELECT SUM(Quantity * Average_Price)
FROM Portfolio WHERE Client_ID = 1;
-- Returns: 9,465.00

                                        BEGIN;
                                        UPDATE Portfolio
                                          SET Quantity = Quantity + 100
                                          WHERE Client_ID = 1 AND Investment_ID = 1;
                                        COMMIT;

-- At READ COMMITTED, this second read would return a different number.
-- At REPEATABLE READ, the snapshot is frozen at Session A's BEGIN — still 9,465.00.
SELECT SUM(Quantity * Average_Price)
FROM Portfolio WHERE Client_ID = 1;

COMMIT;
```

**Risk in this schema:** A broker's risk-assessment report that reads portfolio values twice in the same report would show inconsistent figures without REPEATABLE READ.

---

#### Lost Update (requires locking — not solved by MVCC alone)

```
Session A                               Session B
─────────────────────────────────────   ───────────────────────────────────────
BEGIN;                                  BEGIN;
SELECT Quantity FROM Portfolio
WHERE Client_ID = 2                     SELECT Quantity FROM Portfolio
  AND Investment_ID = 2;                WHERE Client_ID = 2
-- Returns: 30                            AND Investment_ID = 2;
                                        -- Returns: 30

-- Both sessions compute: 30 - 10 = 20
UPDATE Portfolio SET Quantity = 20 ...  UPDATE Portfolio SET Quantity = 20 ...
COMMIT;                                 COMMIT;
-- Both commits succeed. The correct
-- result should have been 10 (two
-- separate sells of 10 shares each).
```

MVCC does not prevent this. The fix is `SELECT ... FOR UPDATE` (shown in Part 3).

---

## Part 3 — Locking

### Lock Types

| Lock Type | Symbol | Who can hold it simultaneously | Use case |
|-----------|--------|-------------------------------|----------|
| **Shared (S)** | `FOR SHARE` | Multiple readers | Read a row, prevent its deletion until commit |
| **Exclusive (X)** | `FOR UPDATE` | One writer only | Modify a row; block all other readers and writers |
| **Intention Shared (IS)** | table-level | Multiple | Signal that rows in the table will be S-locked |
| **Intention Exclusive (IX)** | table-level | Multiple | Signal that rows in the table will be X-locked |
| **Gap lock** | — | — | Lock the gap before a row (prevents phantom inserts at REPEATABLE READ) |
| **Next-key lock** | — | — | Row lock + gap lock combined; InnoDB's default for range queries |

InnoDB acquires **intention locks** at the table level automatically before row-level locks. They prevent DDL (`ALTER TABLE`, `DROP TABLE`) from conflicting with running DML transactions without scanning every locked row.

---

### SELECT ... FOR UPDATE (Exclusive Row Lock)

Acquires an **exclusive lock** on every row returned. Other sessions must wait to read (at `SERIALIZABLE`) or write those rows until the lock is released at `COMMIT` or `ROLLBACK`.

```sql
-- Scenario: Two brokers simultaneously try to sell shares of the same
-- investment for the same client. Without FOR UPDATE both read the same
-- Quantity and both proceed, resulting in a lost update.

BEGIN;

-- Lock the portfolio row. Any concurrent session trying to lock the same
-- row (with FOR UPDATE or FOR SHARE) will block here until we commit.
SELECT Portfolio_ID, Quantity, Average_Price
FROM   Portfolio
WHERE  Client_ID = 2 AND Investment_ID = 2
FOR UPDATE;

-- Now we own the lock. Re-check quantity safely.
-- (Application reads @held_qty from the result above)
-- If sufficient: proceed. If not: ROLLBACK.

UPDATE Portfolio
SET    Quantity = Quantity - 10
WHERE  Client_ID = 2 AND Investment_ID = 2;

INSERT INTO Orders (Client_ID, Broker_ID, Investment_ID, Status, Price, Quantity)
VALUES (2, 1, 2, 'PENDING', 415.22, 10);

INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price)
VALUES (LAST_INSERT_ID(), 2, 1, 'SELL', 415.22);

COMMIT;
-- Lock is released. The concurrent session can now proceed with the updated Quantity.
```

---

### SELECT ... FOR SHARE (Shared Row Lock)

Acquires a **shared lock** — multiple sessions can hold it simultaneously, but no session can acquire an exclusive lock on those rows while any shared lock exists.

```sql
-- Scenario: A reporting job reads all portfolio positions to compute
-- daily NAV. It doesn't need to modify rows, but it needs a guarantee
-- that prices won't change mid-report.

BEGIN;

-- Allow other readers but block any price UPDATE until we're done.
SELECT s.Symbol, s.Last_Traded_Price, p.Quantity
FROM   Portfolio    p
INNER JOIN Investments  i  ON p.Investment_ID = i.Investment_ID
INNER JOIN Stocks       s  ON i.Stock_ID      = s.Stock_ID
WHERE  p.Client_ID = 3
FOR SHARE;

-- ... compute NAV report ...

COMMIT;
-- Shared locks released. Writers can now update prices.
```

---

### NOWAIT and SKIP LOCKED

MySQL 8.0+ supports these modifiers on `FOR UPDATE` / `FOR SHARE`:

```sql
-- NOWAIT: fail immediately if the row is already locked (don't wait)
SELECT Quantity FROM Portfolio
WHERE Client_ID = 4 AND Investment_ID = 1
FOR UPDATE NOWAIT;
-- Returns ER_LOCK_NOWAIT if blocked. Useful in real-time order APIs.

-- SKIP LOCKED: skip rows that are currently locked, return only free rows
-- Useful for a job queue pattern (e.g. processing PENDING orders):
SELECT Order_ID, Client_ID, Investment_ID, Price, Quantity
FROM   Orders
WHERE  Status = 'PENDING'
FOR UPDATE SKIP LOCKED
LIMIT 5;
-- Each worker process grabs a different set of 5 orders without contention.
```

---

### Deadlocks

A deadlock occurs when two sessions each hold a lock the other needs:

```
Session A                               Session B
─────────────────────────────────────   ───────────────────────────────────────
BEGIN;                                  BEGIN;
-- Lock Tax row for Client 1
UPDATE Tax SET Tax = Tax + 75           -- Lock Tax row for Client 2
WHERE Client_ID = 1 AND Tax_Year=2023;  UPDATE Tax SET Tax = Tax + 120
                                        WHERE Client_ID = 2 AND Tax_Year=2023;

-- Now try to lock Client 2's Tax row   -- Now try to lock Client 1's Tax row
UPDATE Tax SET Loss = Loss + 200        UPDATE Tax SET Loss = Loss + 300
WHERE Client_ID = 2 AND Tax_Year=2023;  WHERE Client_ID = 1 AND Tax_Year=2023;
-- ← BLOCKS (Session B holds it)        -- ← BLOCKS (Session A holds it)
--
-- InnoDB detects the cycle.
-- It picks the cheaper transaction to roll back (usually the one with
-- fewer undo log records) and raises:
-- ERROR 1213 (40001): Deadlock found when trying to get lock;
--                     try restarting transaction
```

**InnoDB's response:** automatically rolls back one victim transaction. The surviving session proceeds normally. The application must catch `ER_LOCK_DEADLOCK (1213)` and retry.

**Prevention strategies for this schema:**

```sql
-- Strategy 1: Always acquire locks in the same order.
-- All code that touches both Orders and Portfolio should lock Orders first.
-- This eliminates the cycle.

-- Strategy 2: For batch Tax updates, sort by Client_ID ascending
-- so every session processes clients in the same sequence.
UPDATE Tax SET Tax = Tax + 75
WHERE Client_ID = 1 AND Tax_Year = 2023;  -- always Client 1 before Client 2

-- Strategy 3: Keep transactions short — the longer a transaction holds
-- locks, the higher the chance of a deadlock.

-- Inspect the last deadlock (requires PROCESS privilege):
SHOW ENGINE INNODB STATUS\G
-- Look for the LATEST DETECTED DEADLOCK section.
```

---

### Checking Lock Wait Status

```sql
-- See which transactions are currently waiting for locks
SELECT
    r.trx_id                  AS waiting_trx_id,
    r.trx_mysql_thread_id     AS waiting_thread,
    r.trx_query               AS waiting_query,
    b.trx_id                  AS blocking_trx_id,
    b.trx_mysql_thread_id     AS blocking_thread,
    b.trx_query               AS blocking_query
FROM       information_schema.innodb_lock_waits  w
INNER JOIN information_schema.innodb_trx         b ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx         r ON r.trx_id = w.requesting_trx_id;

-- Lock wait timeout (default 50 seconds)
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

-- Reduce to fail faster in an OLTP application
SET SESSION innodb_lock_wait_timeout = 5;
```

---

## Part 4 — Multi-Version Concurrency Control (MVCC)

InnoDB stores multiple **versions** of each row using two hidden columns appended to every table:

| Hidden column | Purpose |
|---------------|---------|
| `DB_TRX_ID` | ID of the transaction that last modified this row |
| `DB_ROLL_PTR` | Pointer into the undo log to the previous version of this row |

When a transaction reads a row at **REPEATABLE READ**, InnoDB computes a *read view* — a snapshot of which transaction IDs were committed at the time `BEGIN` was issued. Any row version whose `DB_TRX_ID` is newer than the snapshot is invisible; InnoDB follows `DB_ROLL_PTR` back through the undo log to find the last visible version.

**Consequence for this schema:**

```sql
-- Session A starts a long-running portfolio report
BEGIN;  -- snapshot frozen here
SELECT * FROM ClientPortfolioSummary;   -- reads current committed data

-- Meanwhile Session B commits a new Portfolio row
-- Session A's subsequent reads still see the pre-B snapshot — consistent NAV report.
SELECT * FROM ClientPortfolioSummary;   -- same result set as first read

COMMIT;
```

MVCC means readers never block writers and writers never block readers. Contention only occurs when two sessions try to **write the same row**.

---

## Part 5 — Recovery

### Components of InnoDB Recovery

InnoDB uses a **Write-Ahead Logging (WAL)** architecture with two separate log streams:

```
  Application
      │
      ▼
  Buffer Pool  ←─── modified pages live here (dirty pages)
      │
      ├──► Redo Log (iblogfile0, ib_logfile1) ← written before data page
      │         flushed to disk on every COMMIT (innodb_flush_log_at_trx_commit=1)
      │
      └──► Undo Log (undo tablespace files)   ← old row versions for ROLLBACK + MVCC
```

**Redo log** — records *what changed* (physical page changes). Used to replay committed work after a crash.  
**Undo log** — records *what the row looked like before the change*. Used to reverse uncommitted work and serve MVCC snapshots.

---

### Crash Recovery Sequence

When MySQL restarts after a crash, InnoDB performs these steps automatically before accepting connections:

```
1. REDO PHASE
   Scan the redo log from the last checkpoint LSN to the end.
   Re-apply all logged changes to data pages — this brings the buffer pool
   (and eventually the data files) up to the state at the moment of crash,
   including any changes that were in-flight but whose dirty pages hadn't
   been flushed yet.

2. UNDO PHASE
   Walk the undo log for every transaction that was active (not committed)
   at crash time. Roll back each uncommitted transaction, restoring rows
   to their pre-transaction state.

3. Ready.
   All committed transactions are present; all uncommitted ones are gone.
   No manual intervention is required.
```

**Key configuration (`my.ini` on Windows):**

```ini
[mysqld]
# 1 = flush log to disk on every COMMIT (full durability, default)
# 2 = flush log to OS cache on COMMIT (faster, ~1 second data loss on OS crash)
# 0 = flush log every ~1 second (fastest, up to 1 second data loss on MySQL crash)
innodb_flush_log_at_trx_commit = 1

# Size of the redo log on disk; larger = fewer checkpoints = better write throughput
innodb_redo_log_capacity = 104857600    # 100 MB

# How much RAM the buffer pool uses (set to ~70% of available RAM for a dedicated DB)
innodb_buffer_pool_size = 512M
```

---

### Checkpoints

A **checkpoint** records the *Log Sequence Number (LSN)* up to which all dirty buffer pool pages have been written to the data files on disk. After a checkpoint:

- Redo log entries before the checkpoint LSN can be reused (circular log).
- Crash recovery only needs to replay from the checkpoint LSN forward.

InnoDB triggers checkpoints automatically (fuzzy checkpointing) as the buffer pool fills with dirty pages. No manual action is needed.

```sql
-- Force a full checkpoint and flush all dirty pages to disk
-- (useful before a cold backup):
SET GLOBAL innodb_fast_shutdown = 0;
-- Then: net stop MySQL   — this forces a clean checkpoint before shutdown.
```

---

### Binary Log (Binlog)

The **binary log** is separate from the redo log. It records every committed SQL statement (or row change) in sequence and is the foundation for:

- **Point-in-time recovery (PITR)** — replay events from a backup up to a specific timestamp
- **Replication** — send changes to a replica server in real time

```ini
[mysqld]
# Enable binary logging
log_bin          = C:/ProgramData/MySQL/MySQL Server 8.4/Data/mysql-bin
binlog_format    = ROW          # ROW is safer than STATEMENT for triggers
expire_logs_days = 7            # auto-purge logs older than 7 days
```

```sql
-- List binary log files on disk
SHOW BINARY LOGS;

-- Show events in the most recent log file
SHOW BINLOG EVENTS IN 'mysql-bin.000003' LIMIT 20;
```

---

## Part 6 — Backup & Point-in-Time Recovery

### Logical Backup with mysqldump

A logical backup dumps the database as SQL statements. Suitable for small-to-medium databases and for portability between MySQL versions.

```bash
# Full database backup — produces a single .sql file
mysqldump -u root -p \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  portfolio_db > backup_portfolio_db_2026-06-23.sql

# --single-transaction: starts a REPEATABLE READ transaction so the dump
#   is consistent (snapshot at dump start) without locking tables.
#   Requires InnoDB — does NOT work correctly with MyISAM.
# --routines: includes stored procedures (sp_portfolio_value_report)
# --triggers: includes all five triggers
```

```bash
# Restore from a logical backup
mysql -u root -p portfolio_db < backup_portfolio_db_2026-06-23.sql
```

---

### Point-in-Time Recovery (PITR)

Scenario: it is 14:30 and someone accidentally ran `DELETE FROM Portfolio WHERE 1=1`. The last full backup was taken at 00:00. Binary logging is enabled.

**Step 1 — Restore the last full backup**
```bash
mysql -u root -p portfolio_db < backup_portfolio_db_2026-06-23.sql
```

**Step 2 — Identify the binary log position just before the accident**
```bash
mysqlbinlog --start-datetime="2026-06-23 00:00:00" \
            --stop-datetime="2026-06-23 14:29:59" \
            C:/ProgramData/MySQL/MySQL Server 8.4/Data/mysql-bin.000003 \
  | mysql -u root -p portfolio_db
```

This replays all committed transactions from midnight up to 14:29:59, recovering 14.5 hours of trades, orders, and portfolio changes.

**Step 3 — Skip the destructive event and replay the rest (if needed)**
```bash
# Find the exact log position of the bad DELETE using mysqlbinlog output,
# then replay in two parts — before and after the bad event:
mysqlbinlog --start-position=4 --stop-position=88432 mysql-bin.000003 | mysql ...
mysqlbinlog --start-position=88550 mysql-bin.000003 | mysql ...
```

---

### Concurrency-Safe Backup with FTWRL (Reference)

For tables that mix InnoDB and non-transactional engines, `--single-transaction` is insufficient. The alternative is:

```sql
-- Blocks all writes globally, flushes all pending changes to disk,
-- then allows a consistent read snapshot.
FLUSH TABLES WITH READ LOCK;

-- Take the backup here (external tool, file copy, etc.)

-- Release the global read lock
UNLOCK TABLES;
```

Since this schema is 100% InnoDB, `--single-transaction` is the preferred approach — `FTWRL` is not needed and would block all writes for the duration of the backup.

---

## Summary Table

| Feature | Mechanism | How this schema uses it |
|---------|-----------|------------------------|
| Atomicity | Undo log + ROLLBACK | BUY/SELL spans Orders + stock_transaction + Tax — all or nothing |
| Isolation | MVCC snapshots + row locks | Portfolio reports use snapshot reads; SELL orders use `FOR UPDATE` |
| Durability | Redo log flushed at COMMIT | `innodb_flush_log_at_trx_commit = 1` (default) |
| Consistent reads | MVCC (hidden TRX_ID + ROLL_PTR) | Long-running reports see a stable snapshot without blocking trades |
| Lost-update prevention | `SELECT ... FOR UPDATE` | SELL orders lock the Portfolio row before decrementing Quantity |
| Queue processing | `FOR UPDATE SKIP LOCKED` | PENDING order workers grab disjoint sets of orders |
| Deadlock avoidance | Consistent lock-acquisition order | Tax updates ordered by Client_ID; short transactions |
| Crash recovery | Redo log replay + undo rollback | Automatic on restart; no manual steps |
| Backup | `mysqldump --single-transaction` | Consistent snapshot without write blocking |
| PITR | Binary log replay | Recover from accidental mass DELETE/UPDATE |
