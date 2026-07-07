-- ============================================================
-- Portfolio Management System
-- 05_triggers.sql  —  Business-rule triggers
-- MySQL 8.4
-- Run: mysql -u root -p portfolio_db < sql/05_triggers.sql
-- ============================================================

USE portfolio_db;

-- Drop existing triggers so the file is safely re-runnable
DROP TRIGGER IF EXISTS trg_orders_before_insert;
DROP TRIGGER IF EXISTS trg_orders_before_update;
DROP TRIGGER IF EXISTS trg_transaction_before_insert;
DROP TRIGGER IF EXISTS trg_transaction_after_insert;
DROP TRIGGER IF EXISTS trg_portfolio_before_insert;

DELIMITER $$

-- ─────────────────────────────────────────────────────────────
-- Trigger 1: trg_orders_before_insert
-- Fires:  BEFORE INSERT on Orders
-- Purpose: Hard-validate Quantity and Price at the database
--   layer, independent of the CHECK constraints. SIGNAL raises
--   a meaningful error that the application can surface to the
--   user rather than a generic constraint message.
-- ─────────────────────────────────────────────────────────────
CREATE TRIGGER trg_orders_before_insert
BEFORE INSERT ON Orders
FOR EACH ROW
BEGIN
    IF NEW.Quantity IS NULL OR NEW.Quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order rejected: Quantity must be greater than zero.';
    END IF;

    IF NEW.Price IS NULL OR NEW.Price <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order rejected: Price must be greater than zero.';
    END IF;
END$$


-- ─────────────────────────────────────────────────────────────
-- Trigger 2: trg_orders_before_update
-- Fires:  BEFORE UPDATE on Orders
-- Purpose: Enforce order immutability once finalised.
--   * An EXECUTED or CANCELLED order must not have its
--     financial fields (Price, Quantity, Investment, Client,
--     Broker) changed — the historical record must stay intact.
--   * A CANCELLED order cannot be reopened to PENDING; it
--     must be resubmitted as a new order.
-- ─────────────────────────────────────────────────────────────
CREATE TRIGGER trg_orders_before_update
BEFORE UPDATE ON Orders
FOR EACH ROW
BEGIN
    IF NEW.Quantity IS NULL OR NEW.Quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order rejected: Quantity must be greater than zero.';
    END IF;

    IF NEW.Price IS NULL OR NEW.Price <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order rejected: Price must be greater than zero.';
    END IF;

    -- Protect core financial fields on finalised orders
    IF OLD.Status IN ('EXECUTED', 'CANCELLED')
       AND (   NOT (NEW.Price         <=> OLD.Price)
            OR NOT (NEW.Quantity      <=> OLD.Quantity)
            OR NOT (NEW.Investment_ID <=> OLD.Investment_ID)
            OR NOT (NEW.Client_ID     <=> OLD.Client_ID)
            OR NOT (NEW.Broker_ID     <=> OLD.Broker_ID))
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot modify a finalised (EXECUTED or CANCELLED) order.';
    END IF;

    -- Prevent reopening a cancelled order
    IF OLD.Status = 'CANCELLED' AND NEW.Status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot reopen a cancelled order; submit a new one instead.';
    END IF;
END$$


-- ─────────────────────────────────────────────────────────────
-- Trigger 3: trg_transaction_before_insert
-- Fires:  BEFORE INSERT on stock_transaction
-- Purpose: Guard three rules before a transaction row lands:
--   1. Price must be positive.
--   2. A transaction cannot be linked to a CANCELLED order —
--      there is nothing to settle.
--   3. Each order may produce at most one transaction (a
--      1-to-0..1 relationship enforced here since we cannot
--      add a unique index on a nullable FK column reliably).
-- ─────────────────────────────────────────────────────────────
CREATE TRIGGER trg_transaction_before_insert
BEFORE INSERT ON stock_transaction
FOR EACH ROW
BEGIN
    DECLARE v_order_status VARCHAR(20);
    DECLARE v_existing_txn INT DEFAULT 0;

    -- Rule 1: price must be positive
    IF NEW.Price IS NULL OR NEW.Price <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Transaction rejected: Price must be greater than zero.';
    END IF;

    IF NEW.Order_ID IS NOT NULL THEN

        -- Rule 2: linked order must not be cancelled
        SELECT Status
        INTO   v_order_status
        FROM   Orders
        WHERE  Order_ID = NEW.Order_ID;

        IF v_order_status = 'CANCELLED' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Transaction rejected: cannot settle a cancelled order.';
        END IF;

        -- Rule 3: order must not already have a transaction
        SELECT COUNT(*)
        INTO   v_existing_txn
        FROM   stock_transaction
        WHERE  Order_ID = NEW.Order_ID;

        IF v_existing_txn > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Transaction rejected: this order already has a transaction record.';
        END IF;

    END IF;
END$$


-- ─────────────────────────────────────────────────────────────
-- Trigger 4: trg_transaction_after_insert
-- Fires:  AFTER INSERT on stock_transaction
-- Purpose: Three cascading actions when a trade is recorded:
--
--   Part A — Auto-execute the parent order.
--     Flips the linked Order.Status from PENDING → EXECUTED so
--     the application never has to do a separate UPDATE.
--
--   Part B — Upsert the Tax record (SELL trades only).
--     Computes realized P&L = (sell_price − avg_cost) × qty,
--     then adds to the client's Tax row for the current fiscal
--     year (unique on Client_ID + Broker_ID + Tax_Year).
--     Capital gains tax is estimated at 15%.
--
--   Part C — Append an Insights row (SELL trades only).
--     Records the individual realized gain or loss as a new
--     Insights entry so the history of each trade is preserved.
-- ─────────────────────────────────────────────────────────────
CREATE TRIGGER trg_transaction_after_insert
AFTER INSERT ON stock_transaction
FOR EACH ROW
BEGIN
    -- working variables
    DECLARE v_qty            INT           DEFAULT 1;
    DECLARE v_investment_id  INT           DEFAULT 0;
    DECLARE v_avg_cost       DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_market_id      INT;
    DECLARE v_stock_id       INT;
    DECLARE v_mf_id          INT;
    DECLARE v_realized_pl    DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_profit         DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_loss           DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_tax_amt        DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_tax_year       YEAR;

    -- ── Part A: mark parent order as EXECUTED ────────────────
    IF NEW.Order_ID IS NOT NULL THEN
        UPDATE Orders
        SET    Status = 'EXECUTED'
        WHERE  Order_ID = NEW.Order_ID
          AND  Status   = 'PENDING';
    END IF;

    -- ── Parts B & C: only relevant for SELL transactions
    --    with a linked order (so we can read qty + investment)
    IF NEW.Type = 'SELL' AND NEW.Order_ID IS NOT NULL THEN

        -- quantity and investment from the linked order
        SELECT o.Quantity, o.Investment_ID
        INTO   v_qty, v_investment_id
        FROM   Orders o
        WHERE  o.Order_ID = NEW.Order_ID;

        SET v_qty            = COALESCE(v_qty, 1);
        SET v_investment_id  = COALESCE(v_investment_id, 0);

        -- client's average cost for this investment (from Portfolio)
        SET v_avg_cost = COALESCE((
            SELECT Average_Price
            FROM   Portfolio
            WHERE  Client_ID     = NEW.Client_ID
              AND  Investment_ID = v_investment_id
            LIMIT  1
        ), 0.00);

        -- market / instrument context needed for Insights
        SELECT i.Market_ID, i.Stock_ID, i.Mutual_Funds_ID
        INTO   v_market_id, v_stock_id, v_mf_id
        FROM   Investments i
        WHERE  i.Investment_ID = v_investment_id;

        -- realized P&L for this trade
        SET v_realized_pl = (NEW.Price - v_avg_cost) * v_qty;
        SET v_tax_year    = YEAR(NEW.Transaction_Date);

        IF v_realized_pl >= 0 THEN
            SET v_profit  = v_realized_pl;
            SET v_tax_amt = ROUND(v_realized_pl * 0.15, 2);   -- 15 % capital gains rate
        ELSE
            SET v_loss    = ABS(v_realized_pl);
        END IF;

        -- ── Part B: upsert Tax row for this client/broker/year ─
        -- uq_tax_year UNIQUE(Client_ID, Broker_ID, Tax_Year)
        -- guarantees ON DUPLICATE KEY hits the right row.
        INSERT INTO Tax
            (Client_ID, Broker_ID, Tax_Year, Profit,    Loss,   Tax)
        VALUES
            (NEW.Client_ID, NEW.Broker_ID, v_tax_year,
             v_profit, v_loss, v_tax_amt)
        ON DUPLICATE KEY UPDATE
            Profit = COALESCE(Profit, 0) + v_profit,
            Loss   = COALESCE(Loss, 0)   + v_loss,
            Tax    = COALESCE(Tax, 0)    + v_tax_amt;

        -- ── Part C: append Insights row for this realized trade ─
        -- Each sell trade produces its own Insights record so the
        -- per-trade history is preserved (no upsert — append only).
        INSERT INTO Insights
            (Client_ID, Market_ID, Stock_ID, Mutual_Funds_ID,
             Profit,   Loss,   Total_PL)
        VALUES
            (NEW.Client_ID, v_market_id, v_stock_id, v_mf_id,
             v_profit, v_loss, v_realized_pl);

    END IF;
END$$


-- ─────────────────────────────────────────────────────────────
-- Trigger 5: trg_portfolio_before_insert
-- Fires:  BEFORE INSERT on Portfolio
-- Purpose: Enforce that a position is only ever added with a
--   positive quantity and a positive average cost. A zero-
--   quantity holding or a zero-cost entry would silently corrupt
--   P&L calculations in views and queries.
-- ─────────────────────────────────────────────────────────────
CREATE TRIGGER trg_portfolio_before_insert
BEFORE INSERT ON Portfolio
FOR EACH ROW
BEGIN
    IF NEW.Quantity IS NULL OR NEW.Quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Portfolio entry rejected: Quantity must be greater than zero.';
    END IF;

    IF NEW.Average_Price IS NULL OR NEW.Average_Price <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Portfolio entry rejected: Average_Price must be greater than zero.';
    END IF;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────
-- Quick smoke-tests (run manually to verify trigger behaviour)
-- ─────────────────────────────────────────────────────────────

-- Test T1 — should fail: quantity = 0
-- INSERT INTO Orders (Client_ID, Broker_ID, Investment_ID, Price, Quantity)
-- VALUES (1, 1, 1, 150.00, 0);

-- Test T2 — should fail: modify an EXECUTED order's price
-- UPDATE Orders SET Price = 99.99 WHERE Order_ID = 1;

-- Test T3 — should fail: transaction on a cancelled order
-- INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price)
-- VALUES (10, 8, 8, 'BUY', 155.00);

-- Test T4 — should succeed and auto-execute order 9, then
--           upsert Tax and append Insights for the SELL
-- INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price, Transaction_Date)
-- VALUES (9, 7, 7, 'SELL', 200.00, NOW());
-- SELECT Status FROM Orders WHERE Order_ID = 9;
-- SELECT * FROM Tax WHERE Client_ID = 7;
-- SELECT * FROM Insights WHERE Client_ID = 7 ORDER BY Insight_ID DESC LIMIT 1;

-- Test T5 — should fail: zero average price
-- INSERT INTO Portfolio (Client_ID, Investment_ID, Average_Price, Quantity)
-- VALUES (1, 3, 0.00, 10);
