-- ============================================================
-- Portfolio Management System
-- 03_queries.sql  —  10 analytical queries
-- MySQL 8.4
-- Run: mysql -u root -p portfolio_db < sql/03_queries.sql
-- ============================================================

USE portfolio_db;

-- ─────────────────────────────────────────────────────────────
-- Q1: Current portfolio market value vs cost basis per client
-- Business question: "What is each client's portfolio worth at
-- today's prices, what did they pay, and what is their total
-- unrealized gain or loss?"
-- Technique: INNER + LEFT JOIN (5 tables), CASE, GROUP BY, SUM
-- ─────────────────────────────────────────────────────────────
SELECT
    c.Client_ID,
    c.Name                                                     AS Client_Name,
    COUNT(p.Portfolio_ID)                                      AS Holdings,
    ROUND(SUM(p.Quantity * p.Average_Price),              2)  AS Total_Cost_Basis,
    ROUND(SUM(p.Quantity *
        CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END),                                                2) AS Current_Market_Value,
    ROUND(SUM(p.Quantity *
       (CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END - p.Average_Price)),                             2) AS Unrealized_PL
FROM       Client       c
INNER JOIN Portfolio    p  ON c.Client_ID       = p.Client_ID
INNER JOIN Investments  i  ON p.Investment_ID   = i.Investment_ID
LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
GROUP BY c.Client_ID, c.Name
ORDER BY Current_Market_Value DESC;


-- ─────────────────────────────────────────────────────────────
-- Q2: Unrealized P&L broken down per individual holding
-- Business question: "Which specific positions are in profit and
-- which are at a loss, and by how many dollars?"
-- Technique: INNER + LEFT JOIN (5 tables), CASE, COALESCE
-- ─────────────────────────────────────────────────────────────
SELECT
    c.Name                            AS Client_Name,
    COALESCE(s.Symbol, mf.Symbol)     AS Symbol,
    i.Name                            AS Investment_Name,
    i.Investment_Type,
    p.Quantity,
    p.Average_Price                   AS Cost_Per_Unit,
    ROUND(CASE i.Investment_Type
        WHEN 'STOCK'       THEN s.Last_Traded_Price
        WHEN 'MUTUAL_FUND' THEN mf.Price
    END, 2)                           AS Current_Price,
    ROUND((CASE i.Investment_Type
        WHEN 'STOCK'       THEN s.Last_Traded_Price
        WHEN 'MUTUAL_FUND' THEN mf.Price
    END - p.Average_Price) * p.Quantity, 2) AS Unrealized_PL
FROM       Client       c
INNER JOIN Portfolio    p  ON c.Client_ID       = p.Client_ID
INNER JOIN Investments  i  ON p.Investment_ID   = i.Investment_ID
LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
ORDER BY Unrealized_PL DESC;


-- ─────────────────────────────────────────────────────────────
-- Q3: High-value clients with total invested capital > $5,000
-- Business question: "Which clients have committed more than
-- $5,000 in total across all their holdings (by cost basis)?"
-- Technique: INNER JOIN (3 tables), GROUP BY + HAVING, SUM/AVG
-- ─────────────────────────────────────────────────────────────
SELECT
    c.Client_ID,
    c.Name                                           AS Client_Name,
    c.Email,
    COUNT(p.Portfolio_ID)                            AS Num_Holdings,
    ROUND(SUM(p.Quantity * p.Average_Price),   2)   AS Total_Invested,
    ROUND(AVG(p.Quantity * p.Average_Price),   2)   AS Avg_Position_Size
FROM       Client       c
INNER JOIN Portfolio    p ON c.Client_ID     = p.Client_ID
INNER JOIN Investments  i ON p.Investment_ID = i.Investment_ID
GROUP BY c.Client_ID, c.Name, c.Email
HAVING SUM(p.Quantity * p.Average_Price) > 5000
ORDER BY Total_Invested DESC;


-- ─────────────────────────────────────────────────────────────
-- Q4: Most-watched investments with live price and market info
-- Business question: "Which investments are clients tracking
-- most on their watchlists, and what are they trading at?"
-- Technique: INNER + LEFT JOIN (5 tables), GROUP BY + HAVING, COUNT
-- ─────────────────────────────────────────────────────────────
SELECT
    COALESCE(s.Symbol, mf.Symbol)   AS Symbol,
    i.Name                          AS Investment_Name,
    i.Investment_Type,
    m.Name                          AS Exchange,
    ROUND(CASE i.Investment_Type
        WHEN 'STOCK'       THEN s.Last_Traded_Price
        WHEN 'MUTUAL_FUND' THEN mf.Price
    END, 2)                         AS Current_Price,
    COUNT(w.Watchlist_ID)           AS Times_Watched
FROM       Investments  i
INNER JOIN Watchlist    w  ON i.Investment_ID   = w.Investment_ID
INNER JOIN Market       m  ON i.Market_ID       = m.Market_ID
LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
GROUP BY
    i.Investment_ID, i.Name, i.Investment_Type,
    m.Name, s.Symbol, mf.Symbol, s.Last_Traded_Price, mf.Price
HAVING COUNT(w.Watchlist_ID) >= 1
ORDER BY Times_Watched DESC, Current_Price DESC;


-- ─────────────────────────────────────────────────────────────
-- Q5: Price alerts currently triggered by market conditions
-- Business question: "Which client watchlist alerts are firing
-- right now based on the latest market prices?"
-- Technique: CTE, INNER + LEFT JOIN (5 tables), conditional WHERE
-- ─────────────────────────────────────────────────────────────
WITH live_prices AS (
    SELECT
        i.Investment_ID,
        CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END AS Current_Price
    FROM       Investments  i
    LEFT JOIN  Stocks       s  ON i.Stock_ID        = s.Stock_ID
    LEFT JOIN  Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
)
SELECT
    c.Name                          AS Client_Name,
    COALESCE(s.Symbol, mf.Symbol)   AS Symbol,
    i.Name                          AS Investment_Name,
    tp.Trigger_Condition,
    tp.Trigger_Price,
    ROUND(lp.Current_Price, 2)      AS Current_Price,
    tp.Notification_Type
FROM       Client       c
INNER JOIN Watchlist      w  ON c.Client_ID       = w.Client_ID
INNER JOIN Trigger_Price  tp ON w.Watchlist_ID    = tp.Watchlist_ID
INNER JOIN Investments    i  ON w.Investment_ID   = i.Investment_ID
INNER JOIN live_prices    lp ON i.Investment_ID   = lp.Investment_ID
LEFT  JOIN Stocks         s  ON i.Stock_ID        = s.Stock_ID
LEFT  JOIN Mutual_Funds   mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
WHERE (tp.Trigger_Condition = 'ABOVE'  AND lp.Current_Price >  tp.Trigger_Price)
   OR (tp.Trigger_Condition = 'BELOW'  AND lp.Current_Price <  tp.Trigger_Price)
   OR (tp.Trigger_Condition = 'EQUALS' AND lp.Current_Price =  tp.Trigger_Price)
ORDER BY c.Name, i.Name;


-- ─────────────────────────────────────────────────────────────
-- Q6: Clients diversified in BOTH stocks AND mutual funds
-- Business question: "Which clients hold at least one stock and
-- at least one mutual fund — i.e., are truly diversified?"
-- Technique: INTERSECT set operation with correlated subqueries
-- ─────────────────────────────────────────────────────────────
SELECT c.Client_ID, c.Name AS Client_Name, c.Email
FROM Client c
WHERE c.Client_ID IN (
    SELECT p.Client_ID
    FROM       Portfolio   p
    INNER JOIN Investments i ON p.Investment_ID = i.Investment_ID
    WHERE i.Investment_Type = 'STOCK'
)
INTERSECT
SELECT c.Client_ID, c.Name, c.Email
FROM Client c
WHERE c.Client_ID IN (
    SELECT p.Client_ID
    FROM       Portfolio   p
    INNER JOIN Investments i ON p.Investment_ID = i.Investment_ID
    WHERE i.Investment_Type = 'MUTUAL_FUND'
);


-- ─────────────────────────────────────────────────────────────
-- Q7: Unified instrument price board (stocks + funds combined)
-- Business question: "What is the combined live price list for
-- all NASDAQ-listed stocks alongside major US mutual funds?"
-- Technique: UNION set operation, INNER JOIN (3 tables)
-- ─────────────────────────────────────────────────────────────
SELECT
    s.Symbol,
    s.Name,
    s.Last_Traded_Price   AS Price,
    'STOCK'               AS Instrument_Type,
    m.Name                AS Exchange
FROM       Stocks  s
INNER JOIN Market  m ON s.Market_ID = m.Market_ID
WHERE m.Name = 'NASDAQ'

UNION

SELECT
    mf.Symbol,
    mf.Name,
    mf.Price,
    'MUTUAL_FUND'         AS Instrument_Type,
    'NYSE'                AS Exchange
FROM Mutual_Funds mf
WHERE mf.Symbol IN ('VFIAX', 'FCNTX', 'TRBCX', 'BGRFX', 'FXAIX')

ORDER BY Instrument_Type, Price DESC;


-- ─────────────────────────────────────────────────────────────
-- Q8: Clients with above-average portfolio market value
-- Business question: "Which clients hold more than the average
-- portfolio value across all clients on the platform?"
-- Technique: Derived-table subquery, scalar subquery in WHERE,
--            INNER + LEFT JOIN (5 tables)
-- ─────────────────────────────────────────────────────────────
SELECT
    c.Name                              AS Client_Name,
    ROUND(pv.Market_Value,         2)   AS Portfolio_Value,
    ROUND(avg_vals.Platform_Avg,   2)   AS Platform_Average,
    ROUND(pv.Market_Value - avg_vals.Platform_Avg, 2) AS Above_Average_By
FROM Client c
INNER JOIN (
    -- derived table: market value per client
    SELECT
        p.Client_ID,
        SUM(p.Quantity * CASE i.Investment_Type
            WHEN 'STOCK'       THEN s.Last_Traded_Price
            WHEN 'MUTUAL_FUND' THEN mf.Price
        END) AS Market_Value
    FROM       Portfolio    p
    INNER JOIN Investments  i  ON p.Investment_ID   = i.Investment_ID
    LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
    LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
    GROUP BY p.Client_ID
) pv ON c.Client_ID = pv.Client_ID
CROSS JOIN (
    -- scalar subquery: platform-wide average
    SELECT AVG(sub.Market_Value) AS Platform_Avg
    FROM (
        SELECT
            p2.Client_ID,
            SUM(p2.Quantity * CASE i2.Investment_Type
                WHEN 'STOCK'       THEN s2.Last_Traded_Price
                WHEN 'MUTUAL_FUND' THEN mf2.Price
            END) AS Market_Value
        FROM       Portfolio    p2
        INNER JOIN Investments  i2  ON p2.Investment_ID   = i2.Investment_ID
        LEFT  JOIN Stocks       s2  ON i2.Stock_ID        = s2.Stock_ID
        LEFT  JOIN Mutual_Funds mf2 ON i2.Mutual_Funds_ID = mf2.Mutual_Funds_ID
        GROUP BY p2.Client_ID
    ) sub
) avg_vals ON TRUE
WHERE pv.Market_Value > avg_vals.Platform_Avg
ORDER BY Portfolio_Value DESC;


-- ─────────────────────────────────────────────────────────────
-- Q9: Full broker tax report — all brokers including inactive
-- Business question: "For each broker, show client tax records
-- with net gain and effective tax rate; include brokers who
-- have no tax filings yet."
-- Technique: RIGHT JOIN (Tax → Broker), INNER JOIN Client,
--            COALESCE, derived rate calculation
-- ─────────────────────────────────────────────────────────────
SELECT
    b.Name                                          AS Broker_Name,
    b.License,
    COALESCE(c.Name, '— no records —')             AS Client_Name,
    t.Tax_Year,
    COALESCE(t.Profit,             0.00)            AS Profit,
    COALESCE(t.Loss,               0.00)            AS Loss,
    ROUND(COALESCE(t.Profit, 0) -
          COALESCE(t.Loss,   0),                 2) AS Net_Gain,
    COALESCE(t.Tax,                0.00)            AS Tax_Paid,
    CASE
        WHEN COALESCE(t.Profit, 0) - COALESCE(t.Loss, 0) > 0
        THEN ROUND((t.Tax /
             NULLIF(t.Profit - t.Loss, 0)) * 100, 2)
        ELSE NULL
    END                                             AS Effective_Tax_Rate_Pct
FROM            Tax    t
INNER JOIN      Client c ON t.Client_ID = c.Client_ID
RIGHT JOIN      Broker b ON t.Broker_ID = b.Broker_ID
ORDER BY b.Name, t.Tax_Year;


-- ─────────────────────────────────────────────────────────────
-- Q10: Complete order-to-transaction audit trail
-- Business question: "For every order placed, show the full
-- context — client, broker, investment, market, and whether it
-- was fulfilled with a transaction or is still pending."
-- Technique: INNER JOIN (5 tables: Orders, Client, Broker,
--            Investments, Market), LEFT JOIN stock_transaction
-- ─────────────────────────────────────────────────────────────
SELECT
    o.Order_ID,
    DATE(o.Order_Date)              AS Order_Date,
    c.Name                          AS Client_Name,
    b.Name                          AS Broker_Name,
    i.Name                          AS Investment,
    i.Investment_Type,
    m.Name                          AS Market,
    o.Status                        AS Order_Status,
    o.Price                         AS Order_Price,
    o.Quantity                      AS Order_Qty,
    COALESCE(st.Transaction_ID, 0)  AS Transaction_ID,
    COALESCE(st.Type, '—')          AS Txn_Type,
    COALESCE(st.Price, 0.00)        AS Txn_Price,
    COALESCE(DATE(st.Transaction_Date), NULL) AS Txn_Date
FROM            Orders          o
INNER JOIN      Client          c  ON o.Client_ID     = c.Client_ID
INNER JOIN      Broker          b  ON o.Broker_ID     = b.Broker_ID
INNER JOIN      Investments     i  ON o.Investment_ID = i.Investment_ID
INNER JOIN      Market          m  ON i.Market_ID     = m.Market_ID
LEFT  JOIN      stock_transaction st ON o.Order_ID    = st.Order_ID
ORDER BY o.Order_Date, o.Order_ID;
