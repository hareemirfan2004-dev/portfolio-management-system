-- ============================================================
-- Portfolio Management System
-- 01_schema.sql  —  Database & table definitions
-- MySQL 8.4
-- Run: mysql -u root -p < sql/01_schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS portfolio_db
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE portfolio_db;

-- Drop in reverse dependency order so the file is safely re-runnable
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS Insights;
DROP TABLE IF EXISTS Documents;
DROP TABLE IF EXISTS Tax;
DROP TABLE IF EXISTS stock_transaction;
DROP TABLE IF EXISTS Orders;
DROP TABLE IF EXISTS Trigger_Price;
DROP TABLE IF EXISTS Watchlist;
DROP TABLE IF EXISTS Portfolio;
DROP TABLE IF EXISTS Investments;
DROP TABLE IF EXISTS IPO;
DROP TABLE IF EXISTS Mutual_Funds;
DROP TABLE IF EXISTS Stocks;
DROP TABLE IF EXISTS Client;
DROP TABLE IF EXISTS Broker;
DROP TABLE IF EXISTS Market;
SET FOREIGN_KEY_CHECKS = 1;

-- ── 1. Market ────────────────────────────────────────────────
CREATE TABLE Market (
    Market_ID  INT          AUTO_INCREMENT,
    Name       VARCHAR(100) NOT NULL,
    Location   VARCHAR(100),
    CONSTRAINT pk_market PRIMARY KEY (Market_ID)
);

-- ── 2. Stocks ────────────────────────────────────────────────
CREATE TABLE Stocks (
    Stock_ID           INT           AUTO_INCREMENT,
    Market_ID          INT           NOT NULL,
    Symbol             VARCHAR(10)   NOT NULL,
    Name               VARCHAR(100)  NOT NULL,
    Last_Traded_Price  DECIMAL(15,2),
    High_52w           DECIMAL(15,2),
    Low_52w            DECIMAL(15,2),
    High_Day           DECIMAL(15,2),
    Low_Day            DECIMAL(15,2),
    CONSTRAINT pk_stocks         PRIMARY KEY (Stock_ID),
    CONSTRAINT uq_stocks_symbol  UNIQUE      (Symbol),
    CONSTRAINT fk_stocks_market  FOREIGN KEY (Market_ID) REFERENCES Market (Market_ID),
    CONSTRAINT chk_stocks_prices CHECK (
        (High_52w IS NULL OR Low_52w IS NULL OR High_52w >= Low_52w)
        AND
        (High_Day IS NULL OR Low_Day IS NULL OR High_Day >= Low_Day)
    )
);

-- ── 3. Mutual_Funds ──────────────────────────────────────────
CREATE TABLE Mutual_Funds (
    Mutual_Funds_ID  INT           AUTO_INCREMENT,
    Name             VARCHAR(100)  NOT NULL,
    Symbol           VARCHAR(10)   NOT NULL,
    Price            DECIMAL(15,2),
    CONSTRAINT pk_mutual_funds         PRIMARY KEY (Mutual_Funds_ID),
    CONSTRAINT uq_mutual_funds_symbol  UNIQUE      (Symbol),
    CONSTRAINT chk_mf_price            CHECK (Price IS NULL OR Price > 0)
);

-- ── 4. IPO ───────────────────────────────────────────────────
-- Date_Range from original spec split into Start_Date / End_Date (1NF).
CREATE TABLE IPO (
    IPO_ID      INT           AUTO_INCREMENT,
    Market_ID   INT           NOT NULL,
    Name        VARCHAR(100)  NOT NULL,
    Symbol      VARCHAR(10)   NOT NULL,
    Start_Date  DATE,
    End_Date    DATE,
    Price       DECIMAL(15,2),
    Quantity    INT,
    CONSTRAINT pk_ipo        PRIMARY KEY (IPO_ID),
    CONSTRAINT fk_ipo_market FOREIGN KEY (Market_ID) REFERENCES Market (Market_ID),
    CONSTRAINT chk_ipo_dates CHECK (End_Date   IS NULL OR Start_Date IS NULL OR End_Date >= Start_Date),
    CONSTRAINT chk_ipo_price CHECK (Price      IS NULL OR Price    > 0),
    CONSTRAINT chk_ipo_qty   CHECK (Quantity   IS NULL OR Quantity > 0)
);

-- ── 5. Client ────────────────────────────────────────────────
CREATE TABLE Client (
    Client_ID  INT           AUTO_INCREMENT,
    Name       VARCHAR(100)  NOT NULL,
    Phone      VARCHAR(20),
    Email      VARCHAR(100)  NOT NULL,
    Address    VARCHAR(255),
    CONSTRAINT pk_client       PRIMARY KEY (Client_ID),
    CONSTRAINT uq_client_email UNIQUE      (Email)
);

-- ── 6. Broker ────────────────────────────────────────────────
CREATE TABLE Broker (
    Broker_ID  INT          AUTO_INCREMENT,
    Name       VARCHAR(100) NOT NULL,
    License    VARCHAR(50)  NOT NULL,
    CONSTRAINT pk_broker          PRIMARY KEY (Broker_ID),
    CONSTRAINT uq_broker_license  UNIQUE      (License)
);

-- ── 7. Investments ───────────────────────────────────────────
-- Supertype for Stock and Mutual Fund holdings.
-- Exactly one of Stock_ID / Mutual_Funds_ID must be non-null (chk_inv_exclusive).
CREATE TABLE Investments (
    Investment_ID    INT                          AUTO_INCREMENT,
    Market_ID        INT                          NOT NULL,
    Investment_Type  ENUM('STOCK','MUTUAL_FUND')  NOT NULL,
    Name             VARCHAR(100)                 NOT NULL,
    Stock_ID         INT,
    Mutual_Funds_ID  INT,
    CONSTRAINT pk_investments      PRIMARY KEY (Investment_ID),
    CONSTRAINT fk_inv_market       FOREIGN KEY (Market_ID)       REFERENCES Market       (Market_ID),
    CONSTRAINT fk_inv_stock        FOREIGN KEY (Stock_ID)        REFERENCES Stocks       (Stock_ID),
    CONSTRAINT fk_inv_mutualfund   FOREIGN KEY (Mutual_Funds_ID) REFERENCES Mutual_Funds (Mutual_Funds_ID),
    CONSTRAINT chk_inv_exclusive   CHECK (
        (Investment_Type = 'STOCK' AND Stock_ID IS NOT NULL AND Mutual_Funds_ID IS NULL)
        OR
        (Investment_Type = 'MUTUAL_FUND' AND Stock_ID IS NULL AND Mutual_Funds_ID IS NOT NULL)
    )
);

-- ── 8. Portfolio ─────────────────────────────────────────────
CREATE TABLE Portfolio (
    Portfolio_ID   INT            AUTO_INCREMENT,
    Client_ID      INT            NOT NULL,
    Investment_ID  INT            NOT NULL,
    Average_Price  DECIMAL(15,2),
    Quantity       INT,
    CONSTRAINT pk_portfolio             PRIMARY KEY (Portfolio_ID),
    CONSTRAINT fk_portfolio_client      FOREIGN KEY (Client_ID)    REFERENCES Client      (Client_ID),
    CONSTRAINT fk_portfolio_investment  FOREIGN KEY (Investment_ID) REFERENCES Investments (Investment_ID),
    CONSTRAINT uq_portfolio_client_inv  UNIQUE      (Client_ID, Investment_ID),
    CONSTRAINT chk_portfolio_qty        CHECK (Quantity      IS NULL OR Quantity      > 0),
    CONSTRAINT chk_portfolio_avg_price  CHECK (Average_Price IS NULL OR Average_Price > 0)
);

-- ── 9. Watchlist ─────────────────────────────────────────────
CREATE TABLE Watchlist (
    Watchlist_ID   INT  AUTO_INCREMENT,
    Client_ID      INT  NOT NULL,
    Investment_ID  INT  NOT NULL,
    CONSTRAINT pk_watchlist             PRIMARY KEY (Watchlist_ID),
    CONSTRAINT fk_watchlist_client      FOREIGN KEY (Client_ID)    REFERENCES Client      (Client_ID),
    CONSTRAINT fk_watchlist_investment  FOREIGN KEY (Investment_ID) REFERENCES Investments (Investment_ID)
);

-- ── 10. Trigger_Price ────────────────────────────────────────
CREATE TABLE Trigger_Price (
    Alert_ID           INT                             AUTO_INCREMENT,
    Watchlist_ID       INT                             NOT NULL,
    Trigger_Condition  ENUM('ABOVE','BELOW','EQUALS')  NOT NULL,
    Trigger_Price      DECIMAL(15,2)                   NOT NULL,
    Notification_Type  ENUM('EMAIL','SMS','PUSH')       NOT NULL,
    CONSTRAINT pk_trigger_price     PRIMARY KEY (Alert_ID),
    CONSTRAINT fk_trigger_watchlist FOREIGN KEY (Watchlist_ID) REFERENCES Watchlist (Watchlist_ID),
    CONSTRAINT chk_trigger_price    CHECK (Trigger_Price > 0)
);

-- ── 11. Orders ───────────────────────────────────────────────
CREATE TABLE Orders (
    Order_ID       INT                                     AUTO_INCREMENT,
    Client_ID      INT                                     NOT NULL,
    Broker_ID      INT                                     NOT NULL,
    Investment_ID  INT                                     NOT NULL,
    Order_Type     ENUM('BUY','SELL')                      NOT NULL,
    Status         ENUM('PENDING','EXECUTED','CANCELLED')  NOT NULL DEFAULT 'PENDING',
    Price          DECIMAL(15,2),
    Quantity       INT,
    Order_Date     DATETIME                                NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_orders             PRIMARY KEY (Order_ID),
    CONSTRAINT fk_orders_client      FOREIGN KEY (Client_ID)    REFERENCES Client      (Client_ID),
    CONSTRAINT fk_orders_broker      FOREIGN KEY (Broker_ID)    REFERENCES Broker      (Broker_ID),
    CONSTRAINT fk_orders_investment  FOREIGN KEY (Investment_ID) REFERENCES Investments (Investment_ID),
    CONSTRAINT chk_orders_price      CHECK (Price    IS NULL OR Price    > 0),
    CONSTRAINT chk_orders_qty        CHECK (Quantity IS NULL OR Quantity > 0)
);

-- ── 12. stock_transaction ────────────────────────────────────
-- Named stock_transaction to avoid MySQL reserved word TRANSACTION.
-- Order_ID is nullable: a transaction may exist without a linked order.
CREATE TABLE stock_transaction (
    Transaction_ID    INT                 AUTO_INCREMENT,
    Order_ID          INT,
    Client_ID         INT                 NOT NULL,
    Broker_ID         INT                 NOT NULL,
    Type              ENUM('BUY','SELL')  NOT NULL,
    Price             DECIMAL(15,2)       NOT NULL,
    Quantity          INT                 NOT NULL,
    Transaction_Date  DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_stock_transaction PRIMARY KEY (Transaction_ID),
    CONSTRAINT fk_txn_order         FOREIGN KEY (Order_ID)  REFERENCES Orders (Order_ID),
    CONSTRAINT fk_txn_client        FOREIGN KEY (Client_ID) REFERENCES Client (Client_ID),
    CONSTRAINT fk_txn_broker        FOREIGN KEY (Broker_ID) REFERENCES Broker (Broker_ID),
    CONSTRAINT chk_txn_price        CHECK (Price > 0),
    CONSTRAINT chk_txn_qty          CHECK (Quantity > 0)
);

-- ── 13. Tax ──────────────────────────────────────────────────
-- Tax_ID added (original had no PK).
-- Tax_Year added so a client can have one record per broker per fiscal year.
CREATE TABLE Tax (
    Tax_ID     INT            AUTO_INCREMENT,
    Client_ID  INT            NOT NULL,
    Broker_ID  INT            NOT NULL,
    Tax_Year   YEAR           NOT NULL,
    Profit     DECIMAL(15,2),
    Loss       DECIMAL(15,2),
    Tax        DECIMAL(15,2),
    CONSTRAINT pk_tax        PRIMARY KEY (Tax_ID),
    CONSTRAINT fk_tax_client FOREIGN KEY (Client_ID) REFERENCES Client (Client_ID),
    CONSTRAINT fk_tax_broker FOREIGN KEY (Broker_ID) REFERENCES Broker (Broker_ID),
    CONSTRAINT uq_tax_year   UNIQUE  (Client_ID, Broker_ID, Tax_Year),
    CONSTRAINT chk_tax_value CHECK (Tax    IS NULL OR Tax    >= 0),
    CONSTRAINT chk_tax_profit CHECK (Profit IS NULL OR Profit >= 0),
    CONSTRAINT chk_tax_loss  CHECK (Loss   IS NULL OR Loss   >= 0)
);

-- ── 14. Documents ────────────────────────────────────────────
CREATE TABLE Documents (
    Documents_ID   INT          AUTO_INCREMENT,
    Client_ID      INT          NOT NULL,
    Broker_ID      INT          NOT NULL,
    Document_Type  VARCHAR(50),
    Date_Uploaded  DATE,
    CONSTRAINT pk_documents   PRIMARY KEY (Documents_ID),
    CONSTRAINT fk_docs_client FOREIGN KEY (Client_ID) REFERENCES Client (Client_ID),
    CONSTRAINT fk_docs_broker FOREIGN KEY (Broker_ID) REFERENCES Broker (Broker_ID)
);

-- ── 15. Insights ─────────────────────────────────────────────
-- Insight_ID added (original had no PK).
-- Stock_ID and Mutual_Funds_ID are both nullable: an insight may be market-level only.
CREATE TABLE Insights (
    Insight_ID       INT            AUTO_INCREMENT,
    Client_ID        INT            NOT NULL,
    Market_ID        INT            NOT NULL,
    Stock_ID         INT,
    Mutual_Funds_ID  INT,
    Profit           DECIMAL(15,2),
    Loss             DECIMAL(15,2),
    Total_PL         DECIMAL(15,2),
    CONSTRAINT pk_insights             PRIMARY KEY (Insight_ID),
    CONSTRAINT fk_insights_client      FOREIGN KEY (Client_ID)       REFERENCES Client       (Client_ID),
    CONSTRAINT fk_insights_market      FOREIGN KEY (Market_ID)       REFERENCES Market       (Market_ID),
    CONSTRAINT fk_insights_stock       FOREIGN KEY (Stock_ID)        REFERENCES Stocks       (Stock_ID),
    CONSTRAINT fk_insights_mutualfund  FOREIGN KEY (Mutual_Funds_ID) REFERENCES Mutual_Funds (Mutual_Funds_ID)
);
