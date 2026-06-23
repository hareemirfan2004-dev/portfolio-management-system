-- ============================================================
-- Portfolio Management System
-- 06_cursors.sql  —  Stored procedure with cursor
-- MySQL 8.4
-- Run:     mysql -u root -p portfolio_db < sql/06_cursors.sql
-- Execute: CALL sp_portfolio_value_report();
-- ============================================================

USE portfolio_db;

DROP PROCEDURE IF EXISTS sp_portfolio_value_report;

DELIMITER $$

-- ------------------------------------------------------------
-- sp_portfolio_value_report
--
-- Uses a cursor to walk every Client row one at a time.
-- For each client it computes:
--   • cost basis   (what they paid)
--   • market value (what it is worth today)
--   • unrealized P&L and return %
--   • a risk-band label
-- Running totals are accumulated across iterations and emitted
-- as a second result set (platform-wide summary) at the end.
--
-- Result sets
--   1. Per-client portfolio snapshot, ranked by market value
--   2. Platform-wide aggregate (one row)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_portfolio_value_report()
BEGIN

    -- ── 1. Variable declarations ─────────────────────────────
    -- Rule: all DECLAREs must come first, before any executable
    -- statement.  Order within DECLAREs: variables → cursors → handlers.

    -- Cursor target variables — one per column fetched
    DECLARE v_client_id     INT;
    DECLARE v_client_name   VARCHAR(100);

    -- Per-client computed values (reset each iteration)
    DECLARE v_holdings      INT           DEFAULT 0;
    DECLARE v_cost_basis    DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_market_value  DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_unrealized_pl DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_return_pct    DECIMAL(8,2)  DEFAULT 0.00;
    DECLARE v_risk_band     VARCHAR(20);

    -- Platform-wide running totals (accumulated across all iterations)
    DECLARE v_total_clients INT           DEFAULT 0;
    DECLARE v_profitable    INT           DEFAULT 0;
    DECLARE v_total_cost    DECIMAL(15,2) DEFAULT 0.00;
    DECLARE v_total_mktval  DECIMAL(15,2) DEFAULT 0.00;

    -- Loop-exit sentinel: the NOT FOUND handler flips this to 1
    DECLARE v_done          TINYINT       DEFAULT 0;


    -- ── 2. Cursor declaration ────────────────────────────────
    -- Selects every client in primary-key order.
    -- The cursor is read-only; no FOR UPDATE lock is needed.
    DECLARE cur_clients CURSOR FOR
        SELECT Client_ID, Name
        FROM   Client
        ORDER  BY Client_ID;


    -- ── 3. Handler declaration ───────────────────────────────
    -- CONTINUE handler: when FETCH runs out of rows MySQL raises
    -- the NOT FOUND condition.  CONTINUE means execution resumes
    -- on the next statement (the IF v_done check), not an exit.
    -- Must be declared AFTER cursors and BEFORE executable code.
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;


    -- ── 4. Temp table to accumulate per-client results ───────
    -- We build the full report in memory, then emit one clean
    -- SELECT at the end instead of many individual SELECTs.
    DROP   TEMPORARY TABLE IF EXISTS tmp_portfolio_report;
    CREATE TEMPORARY TABLE tmp_portfolio_report (
        Client_ID      INT,
        Client_Name    VARCHAR(100),
        Holdings       INT,
        Cost_Basis     DECIMAL(15,2),
        Market_Value   DECIMAL(15,2),
        Unrealized_PL  DECIMAL(15,2),
        Return_Pct     DECIMAL(8,2),
        Risk_Band      VARCHAR(20)
    );


    -- ── 5. OPEN cursor ───────────────────────────────────────
    -- Executes the SELECT query and positions the cursor before
    -- the first row.  No rows are fetched yet.
    OPEN cur_clients;


    -- ── 6. Fetch loop ────────────────────────────────────────
    client_loop: LOOP

        -- FETCH advances the cursor by one row and loads column
        -- values into the declared target variables.
        -- When no row remains, NOT FOUND fires → v_done = 1.
        FETCH cur_clients INTO v_client_id, v_client_name;

        -- Always check the sentinel immediately after FETCH.
        -- LEAVE exits the named loop (not the procedure).
        IF v_done = 1 THEN
            LEAVE client_loop;
        END IF;


        -- ── 6a. Compute this client's portfolio metrics ──────
        -- A single SELECT INTO replaces multiple queries.
        -- COALESCE guards against clients who have no holdings.
        SELECT
            COUNT(p.Portfolio_ID),
            ROUND(COALESCE(SUM(p.Quantity * p.Average_Price), 0), 2),
            ROUND(COALESCE(SUM(
                p.Quantity *
                CASE i.Investment_Type
                    WHEN 'STOCK'       THEN s.Last_Traded_Price
                    WHEN 'MUTUAL_FUND' THEN mf.Price
                END
            ), 0), 2)
        INTO
            v_holdings,
            v_cost_basis,
            v_market_value
        FROM       Portfolio    p
        INNER JOIN Investments  i  ON p.Investment_ID   = i.Investment_ID
        LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
        LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
        WHERE p.Client_ID = v_client_id;

        -- Null-guard: if the client has no Portfolio rows the
        -- aggregate functions return NULL, not 0.
        SET v_holdings     = COALESCE(v_holdings,     0);
        SET v_cost_basis   = COALESCE(v_cost_basis,   0.00);
        SET v_market_value = COALESCE(v_market_value, 0.00);


        -- ── 6b. Derived metrics ──────────────────────────────
        SET v_unrealized_pl = v_market_value - v_cost_basis;

        SET v_return_pct =
            CASE
                WHEN v_cost_basis > 0
                THEN ROUND((v_unrealized_pl / v_cost_basis) * 100, 2)
                ELSE 0.00
            END;


        -- ── 6c. Risk-band classification (per iteration) ─────
        SET v_risk_band =
            CASE
                WHEN v_holdings    =  0  THEN 'No Holdings'
                WHEN v_return_pct >= 15  THEN 'High Gain'
                WHEN v_return_pct >=  0  THEN 'Modest Gain'
                WHEN v_return_pct >= -10 THEN 'Minor Loss'
                ELSE                          'Significant Loss'
            END;


        -- ── 6d. Accumulate platform-wide running totals ──────
        -- These variables survive across loop iterations and
        -- are used in the summary result set after the loop.
        SET v_total_clients = v_total_clients + 1;
        SET v_total_cost    = v_total_cost    + v_cost_basis;
        SET v_total_mktval  = v_total_mktval  + v_market_value;

        IF v_unrealized_pl >= 0 THEN
            SET v_profitable = v_profitable + 1;
        END IF;


        -- ── 6e. Persist this client's row ────────────────────
        INSERT INTO tmp_portfolio_report VALUES (
            v_client_id,
            v_client_name,
            v_holdings,
            v_cost_basis,
            v_market_value,
            v_unrealized_pl,
            v_return_pct,
            v_risk_band
        );

    END LOOP client_loop;


    -- ── 7. CLOSE cursor ──────────────────────────────────────
    -- Releases server-side cursor resources.
    -- Always close every cursor you open.
    CLOSE cur_clients;


    -- ── 8. Result set 1: per-client snapshot ─────────────────
    SELECT
        Client_ID,
        Client_Name,
        Holdings,
        Cost_Basis,
        Market_Value,
        Unrealized_PL,
        CONCAT(Return_Pct, ' %') AS Return_Pct,
        Risk_Band
    FROM  tmp_portfolio_report
    ORDER BY Market_Value DESC;


    -- ── 9. Result set 2: platform-wide summary ───────────────
    -- Built entirely from variables accumulated in the loop —
    -- no extra query against the base tables is needed.
    SELECT
        v_total_clients                                        AS Total_Clients,
        v_profitable                                          AS Clients_In_Profit,
        v_total_clients - v_profitable                        AS Clients_At_Loss,
        ROUND(v_total_cost,   2)                              AS Platform_Cost_Basis,
        ROUND(v_total_mktval, 2)                              AS Platform_Market_Value,
        ROUND(v_total_mktval - v_total_cost, 2)               AS Platform_Unrealized_PL,
        CONCAT(
            ROUND(
                (v_total_mktval - v_total_cost)
                / NULLIF(v_total_cost, 0) * 100, 2),
            ' %')                                             AS Platform_Return_Pct;


    -- ── 10. Cleanup ──────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_portfolio_report;

END$$

DELIMITER ;
