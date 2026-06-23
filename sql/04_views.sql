-- ============================================================
-- Portfolio Management System
-- 04_views.sql  —  Reusable views
-- MySQL 8.4
-- Run: mysql -u root -p portfolio_db < sql/04_views.sql
-- ============================================================

USE portfolio_db;

-- ─────────────────────────────────────────────────────────────
-- View 1: ClientPortfolioSummary
-- Purpose: One row per client showing their full portfolio
-- snapshot — cost basis, live market value, unrealized P&L,
-- and return percentage. Query this view anywhere you need a
-- client-level financial overview without rewriting the JOINs.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW ClientPortfolioSummary AS
SELECT
    c.Client_ID,
    c.Name                                                        AS Client_Name,
    c.Email,
    COUNT(p.Portfolio_ID)                                         AS Holdings,

    -- how many of each type they own
    SUM(i.Investment_Type = 'STOCK')                              AS Stock_Holdings,
    SUM(i.Investment_Type = 'MUTUAL_FUND')                        AS Fund_Holdings,

    -- what they paid in total
    ROUND(SUM(p.Quantity * p.Average_Price),                   2) AS Cost_Basis,

    -- what it is worth today
    ROUND(SUM(p.Quantity *
        CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END),                                                   2) AS Market_Value,

    -- dollar gain or loss vs cost basis
    ROUND(SUM(p.Quantity *
       (CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END - p.Average_Price)),                                2) AS Unrealized_PL,

    -- percentage return
    ROUND(
        SUM(p.Quantity *
           (CASE i.Investment_Type
                WHEN 'STOCK'       THEN s.Last_Traded_Price
                WHEN 'MUTUAL_FUND' THEN mf.Price
            END - p.Average_Price))
        / NULLIF(SUM(p.Quantity * p.Average_Price), 0) * 100,  2) AS Return_Pct

FROM            Client       c
INNER JOIN      Portfolio    p  ON c.Client_ID       = p.Client_ID
INNER JOIN      Investments  i  ON p.Investment_ID   = i.Investment_ID
LEFT  JOIN      Stocks       s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN      Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
GROUP BY c.Client_ID, c.Name, c.Email;

-- Sample usage:
--   SELECT * FROM ClientPortfolioSummary ORDER BY Return_Pct DESC;
--   SELECT * FROM ClientPortfolioSummary WHERE Unrealized_PL < 0;


-- ─────────────────────────────────────────────────────────────
-- View 2: BrokerPerformance
-- Purpose: One row per broker with aggregated activity metrics —
-- clients served, order pipeline, transaction volume, and tax
-- records filed. Useful for ranking brokers and compliance
-- reporting. Uses derived-table subqueries to avoid fan-out
-- from joining Orders and stock_transaction to the same broker.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW BrokerPerformance AS
SELECT
    b.Broker_ID,
    b.Name                                       AS Broker_Name,
    b.License,

    COALESCE(ord.Clients_Served,      0)         AS Clients_Served,
    COALESCE(ord.Total_Orders,        0)         AS Total_Orders,
    COALESCE(ord.Executed_Orders,     0)         AS Executed_Orders,
    COALESCE(ord.Pending_Orders,      0)         AS Pending_Orders,
    COALESCE(ord.Cancelled_Orders,    0)         AS Cancelled_Orders,

    -- execution rate as a percentage
    ROUND(
        COALESCE(ord.Executed_Orders, 0)
        / NULLIF(COALESCE(ord.Total_Orders, 0), 0) * 100,
    2)                                           AS Execution_Rate_Pct,

    COALESCE(txn.Total_Transactions,  0)         AS Total_Transactions,
    COALESCE(txn.Buy_Transactions,    0)         AS Buy_Transactions,
    COALESCE(txn.Sell_Transactions,   0)         AS Sell_Transactions,

    -- total dollar volume: price × quantity (quantity from linked order, 1 for manual trades)
    COALESCE(txn.Total_Trade_Volume,  0.00)      AS Total_Trade_Volume,

    COALESCE(tax_rec.Tax_Records,     0)         AS Tax_Records_Filed

FROM Broker b

-- order-level metrics (one aggregation per broker)
LEFT JOIN (
    SELECT
        Broker_ID,
        COUNT(DISTINCT Client_ID)          AS Clients_Served,
        COUNT(*)                           AS Total_Orders,
        SUM(Status = 'EXECUTED')           AS Executed_Orders,
        SUM(Status = 'PENDING')            AS Pending_Orders,
        SUM(Status = 'CANCELLED')          AS Cancelled_Orders
    FROM Orders
    GROUP BY Broker_ID
) ord ON b.Broker_ID = ord.Broker_ID

-- transaction-level metrics (one aggregation per broker)
LEFT JOIN (
    SELECT
        st.Broker_ID,
        COUNT(*)                                             AS Total_Transactions,
        SUM(st.Type = 'BUY')                                AS Buy_Transactions,
        SUM(st.Type = 'SELL')                               AS Sell_Transactions,
        ROUND(SUM(st.Price * COALESCE(o.Quantity, 1)), 2)   AS Total_Trade_Volume
    FROM  stock_transaction st
    LEFT JOIN Orders o ON st.Order_ID = o.Order_ID
    GROUP BY st.Broker_ID
) txn ON b.Broker_ID = txn.Broker_ID

-- tax filing count (one aggregation per broker)
LEFT JOIN (
    SELECT Broker_ID, COUNT(*) AS Tax_Records
    FROM   Tax
    GROUP BY Broker_ID
) tax_rec ON b.Broker_ID = tax_rec.Broker_ID

ORDER BY Total_Trade_Volume DESC;

-- Sample usage:
--   SELECT * FROM BrokerPerformance;
--   SELECT Broker_Name, Execution_Rate_Pct FROM BrokerPerformance ORDER BY Execution_Rate_Pct DESC;


-- ─────────────────────────────────────────────────────────────
-- View 3: WatchlistAlerts
-- Purpose: One row per alert showing the client, the watched
-- investment, the live price, and whether the trigger condition
-- is currently met. The Alert_Triggered flag lets the
-- application filter to only actionable alerts in one query.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW WatchlistAlerts AS
SELECT
    c.Client_ID,
    c.Name                          AS Client_Name,
    c.Email,
    w.Watchlist_ID,
    tp.Alert_ID,
    COALESCE(s.Symbol, mf.Symbol)   AS Symbol,
    i.Name                          AS Investment_Name,
    i.Investment_Type,
    tp.Trigger_Condition,
    tp.Trigger_Price,

    -- live price from Stocks or Mutual_Funds depending on type
    ROUND(CASE i.Investment_Type
        WHEN 'STOCK'       THEN s.Last_Traded_Price
        WHEN 'MUTUAL_FUND' THEN mf.Price
    END, 2)                         AS Current_Price,

    -- gap: positive means price is above trigger, negative means below
    ROUND(CASE i.Investment_Type
        WHEN 'STOCK'       THEN s.Last_Traded_Price
        WHEN 'MUTUAL_FUND' THEN mf.Price
    END - tp.Trigger_Price, 2)      AS Price_Gap,

    -- flag: YES when the condition is currently met
    CASE
        WHEN tp.Trigger_Condition = 'ABOVE'
         AND CASE i.Investment_Type
                 WHEN 'STOCK'       THEN s.Last_Traded_Price
                 WHEN 'MUTUAL_FUND' THEN mf.Price
             END >  tp.Trigger_Price THEN 'YES'
        WHEN tp.Trigger_Condition = 'BELOW'
         AND CASE i.Investment_Type
                 WHEN 'STOCK'       THEN s.Last_Traded_Price
                 WHEN 'MUTUAL_FUND' THEN mf.Price
             END <  tp.Trigger_Price THEN 'YES'
        WHEN tp.Trigger_Condition = 'EQUALS'
         AND CASE i.Investment_Type
                 WHEN 'STOCK'       THEN s.Last_Traded_Price
                 WHEN 'MUTUAL_FUND' THEN mf.Price
             END =  tp.Trigger_Price THEN 'YES'
        ELSE 'NO'
    END                             AS Alert_Triggered,

    tp.Notification_Type

FROM            Client          c
INNER JOIN      Watchlist       w  ON c.Client_ID       = w.Client_ID
INNER JOIN      Trigger_Price   tp ON w.Watchlist_ID    = tp.Watchlist_ID
INNER JOIN      Investments     i  ON w.Investment_ID   = i.Investment_ID
LEFT  JOIN      Stocks          s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN      Mutual_Funds    mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
ORDER BY Alert_Triggered DESC, c.Name;

-- Sample usage:
--   SELECT * FROM WatchlistAlerts WHERE Alert_Triggered = 'YES';
--   SELECT * FROM WatchlistAlerts WHERE Client_Name = 'James Harrington';
--   SELECT Client_Name, Symbol, Trigger_Condition, Trigger_Price, Current_Price
--   FROM WatchlistAlerts ORDER BY ABS(Price_Gap) ASC;  -- closest to firing
