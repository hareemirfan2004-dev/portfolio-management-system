-- ============================================================
-- Portfolio Management System
-- 02_seed.sql  —  Sample data (~10 rows per table)
-- MySQL 8.4
--
-- LOAD ORDER: run AFTER 01_schema.sql, BEFORE 05_triggers.sql.
-- If triggers are already loaded when this file is re-run,
-- trg_transaction_after_insert fires for the SELL transaction and
-- inserts a Tax row, then this file's explicit Tax INSERT fails on
-- the UNIQUE (Client_ID, Broker_ID, Tax_Year) constraint.
--
--   mysql -u root -p portfolio_db < sql/02_seed.sql
-- ============================================================

USE portfolio_db;

-- Clear existing data in reverse dependency order
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE Insights;
TRUNCATE TABLE Documents;
TRUNCATE TABLE Tax;
TRUNCATE TABLE stock_transaction;
TRUNCATE TABLE Orders;
TRUNCATE TABLE Trigger_Price;
TRUNCATE TABLE Watchlist;
TRUNCATE TABLE Portfolio;
TRUNCATE TABLE Investments;
TRUNCATE TABLE IPO;
TRUNCATE TABLE Mutual_Funds;
TRUNCATE TABLE Stocks;
TRUNCATE TABLE Client;
TRUNCATE TABLE Broker;
TRUNCATE TABLE Market;
SET FOREIGN_KEY_CHECKS = 1;

-- ── 1. Market ────────────────────────────────────────────────
-- IDs 1-10
INSERT INTO Market (Market_ID, Name, Location) VALUES
(1,  'New York Stock Exchange',      'New York, USA'),
(2,  'NASDAQ',                       'New York, USA'),
(3,  'London Stock Exchange',        'London, UK'),
(4,  'Bombay Stock Exchange',        'Mumbai, India'),
(5,  'National Stock Exchange India','Mumbai, India'),
(6,  'Toronto Stock Exchange',       'Toronto, Canada'),
(7,  'Australian Securities Exchange','Sydney, Australia'),
(8,  'Shanghai Stock Exchange',      'Shanghai, China'),
(9,  'Hong Kong Exchanges',          'Hong Kong, China'),
(10, 'Euronext',                     'Paris, France');

-- ── 2. Stocks ────────────────────────────────────────────────
-- IDs 1-10  |  Market refs: NYSE=1, NASDAQ=2, BSE=4
INSERT INTO Stocks (Stock_ID, Market_ID, Symbol, Name,               Last_Traded_Price, High_52w,  Low_52w,  High_Day,  Low_Day) VALUES
(1,  2, 'AAPL',     'Apple Inc.',              189.30,  199.62,  124.17,  190.54,  187.45),
(2,  2, 'MSFT',     'Microsoft Corporation',   415.22,  430.82,  219.35,  418.10,  413.76),
(3,  2, 'GOOGL',    'Alphabet Inc.',           172.63,  176.42,  102.21,  173.88,  171.20),
(4,  2, 'AMZN',     'Amazon.com Inc.',         186.57,  189.77,  101.26,  187.90,  185.12),
(5,  2, 'META',     'Meta Platforms Inc.',     505.38,  531.49,  179.68,  508.44,  502.10),
(6,  1, 'JPM',      'JPMorgan Chase & Co.',    200.44,  207.08,  127.77,  201.88,  198.73),
(7,  1, 'GS',       'Goldman Sachs Group',     463.05,  475.30,  293.22,  465.20,  460.10),
(8,  2, 'TSLA',     'Tesla Inc.',              175.22,  299.29,  138.80,  177.40,  173.58),
(9,  4, 'RELIANCE', 'Reliance Industries Ltd', 34.10,   37.50,   25.60,   34.55,   33.80),
(10, 2, 'NVDA',     'NVIDIA Corporation',      875.40,  974.00,  138.84,  881.25,  869.30);

-- ── 3. Mutual_Funds ──────────────────────────────────────────
-- IDs 1-10
INSERT INTO Mutual_Funds (Mutual_Funds_ID, Name, Symbol, Price) VALUES
(1,  'Vanguard 500 Index Fund Admiral',    'VFIAX', 432.12),
(2,  'Fidelity Contrafund',                'FCNTX', 175.43),
(3,  'T. Rowe Price Blue Chip Growth',     'TRBCX', 156.22),
(4,  'BlackRock Capital Appreciation',     'BGRFX', 121.85),
(5,  'American Funds Growth Fund of Amer', 'AGTHX',  72.40),
(6,  'T. Rowe Price Growth Stock Fund',    'PRGFX',  89.15),
(7,  'Schwab S&P 500 Index Fund',          'SWPPX',  77.64),
(8,  'Fidelity 500 Index Fund',            'FXAIX', 198.32),
(9,  'Dodge & Cox Stock Fund',             'DODGX', 265.18),
(10, 'Oakmark Fund',                       'OAKMX', 112.73);

-- ── 4. IPO ───────────────────────────────────────────────────
-- IDs 1-10  |  Market refs: NYSE=1, NASDAQ=2, NSE=5, BSE=4, ASX=7
INSERT INTO IPO (IPO_ID, Market_ID, Name,                   Symbol,   Start_Date,   End_Date,     Price,  Quantity) VALUES
(1,  2, 'ARM Holdings plc',            'ARM',    '2023-09-13', '2023-09-14',  51.00, 10000000),
(2,  2, 'Maplebear Inc. (Instacart)',  'CART',   '2023-09-18', '2023-09-19',  30.00,  8000000),
(3,  1, 'Klaviyo Inc.',                'KVYO',   '2023-09-19', '2023-09-20',  30.00,  9600000),
(4,  2, 'VinFast Auto Ltd.',           'VFS',    '2023-08-14', '2023-08-15',  10.00, 12000000),
(5,  1, 'Birkenstock Holding plc',     'BIRK',   '2023-10-10', '2023-10-11',  46.00,  7000000),
(6,  5, 'Ola Electric Mobility',       'OLAELEC','2024-08-01', '2024-08-06',  72.00, 50000000),
(7,  2, 'Reddit Inc.',                 'RDDT',   '2024-03-20', '2024-03-21',  34.00, 10000000),
(8,  2, 'Astera Labs Inc.',            'ALAB',   '2024-03-19', '2024-03-20',  36.00,  6000000),
(9,  7, 'BrainChip Holdings Ltd.',     'BRN',    '2021-01-08', '2021-01-12',   0.11,500000000),
(10, 4, 'Hyundai Motor India Ltd.',    'HYUNDAI','2024-10-14', '2024-10-17', 1960.00,  9990000);

-- ── 5. Client ────────────────────────────────────────────────
-- IDs 1-10
INSERT INTO Client (Client_ID, Name,              Phone,          Email,                        Address) VALUES
(1,  'James Harrington',   '+1-212-555-0101', 'j.harrington@email.com',    '14 Lexington Ave, New York, NY'),
(2,  'Sofia Chen',         '+1-415-555-0182', 'sofia.chen@webmail.com',    '88 Market St, San Francisco, CA'),
(3,  'Marcus Williams',    '+1-312-555-0247', 'm.williams@inbox.com',      '321 N Michigan Ave, Chicago, IL'),
(4,  'Emily Patterson',    '+1-617-555-0334', 'emily.p@mailbox.net',       '5 Beacon St, Boston, MA'),
(5,  'Raj Patel',          '+1-972-555-0418', 'raj.patel@netmail.com',     '900 Commerce St, Dallas, TX'),
(6,  'Laura Schmidt',      '+1-206-555-0521', 'laura.schmidt@post.com',    '200 Pine St, Seattle, WA'),
(7,  'David Kim',          '+1-404-555-0619', 'david.kim@mmail.com',       '755 Peachtree St, Atlanta, GA'),
(8,  'Priya Sharma',       '+1-305-555-0712', 'priya.sharma@mailme.com',   '1800 Brickell Ave, Miami, FL'),
(9,  'Carlos Mendez',      '+1-602-555-0838', 'c.mendez@quickmail.com',    '4000 N Central Ave, Phoenix, AZ'),
(10, 'Natasha Brooks',     '+1-503-555-0945', 'n.brooks@onlinemail.com',   '1200 SW Broadway, Portland, OR');

-- ── 6. Broker ────────────────────────────────────────────────
-- IDs 1-10
INSERT INTO Broker (Broker_ID, Name,                           License) VALUES
(1,  'Morgan Stanley Wealth Management', 'FINRA-MS-001-2018'),
(2,  'Charles Schwab & Co.',             'FINRA-CS-002-2017'),
(3,  'Fidelity Investments',             'FINRA-FI-003-2019'),
(4,  'TD Ameritrade Inc.',               'FINRA-TD-004-2016'),
(5,  'E*TRADE Securities LLC',           'FINRA-ET-005-2018'),
(6,  'Interactive Brokers LLC',          'FINRA-IB-006-2015'),
(7,  'Vanguard Brokerage Services',      'FINRA-VB-007-2020'),
(8,  'Merrill Lynch Pierce Fenner',      'FINRA-ML-008-2014'),
(9,  'Raymond James Financial',          'FINRA-RJ-009-2019'),
(10, 'Goldman Sachs Private Wealth',     'FINRA-GS-010-2013');

-- ── 7. Investments ───────────────────────────────────────────
-- IDs 1-10
-- Rows 1-7: STOCK type (Stock_ID set, Mutual_Funds_ID NULL)
-- Rows 8-10: MUTUAL_FUND type (Mutual_Funds_ID set, Stock_ID NULL)
INSERT INTO Investments (Investment_ID, Market_ID, Investment_Type, Name,                          Stock_ID, Mutual_Funds_ID) VALUES
(1,  2, 'STOCK',       'Apple Inc.',                          1,    NULL),
(2,  2, 'STOCK',       'Microsoft Corporation',               2,    NULL),
(3,  2, 'STOCK',       'Alphabet Inc.',                       3,    NULL),
(4,  2, 'STOCK',       'Amazon.com Inc.',                     4,    NULL),
(5,  2, 'STOCK',       'Meta Platforms Inc.',                 5,    NULL),
(6,  1, 'STOCK',       'JPMorgan Chase & Co.',                6,    NULL),
(7,  2, 'STOCK',       'Tesla Inc.',                          8,    NULL),
(8,  1, 'MUTUAL_FUND', 'Vanguard 500 Index Fund Admiral',     NULL, 1),
(9,  1, 'MUTUAL_FUND', 'Fidelity Contrafund',                 NULL, 2),
(10, 1, 'MUTUAL_FUND', 'T. Rowe Price Blue Chip Growth',      NULL, 3);

-- ── 8. Portfolio ─────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-8, Investment refs 1-10
INSERT INTO Portfolio (Portfolio_ID, Client_ID, Investment_ID, Average_Price, Quantity) VALUES
(1,   1,  1,  165.40,  50),   -- James holds AAPL
(2,   1,  2,  348.75,  30),   -- James holds MSFT
(3,   2,  3,  148.20,  20),   -- Sofia holds GOOGL
(4,   2,  8,  398.50,  15),   -- Sofia holds VFIAX fund
(5,   3,  4,  155.80,  25),   -- Marcus holds AMZN
(6,   4,  5,  382.00,  10),   -- Emily holds META
(7,   5,  6,  172.30,  40),   -- Raj holds JPM
(8,   6,  7,  220.45,  35),   -- Laura holds TSLA
(9,   7,  9,  158.60,  20),   -- David holds FCNTX fund
(10,  8, 10,  141.80,  12);   -- Priya holds TRBCX fund

-- ── 9. Watchlist ─────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-10, Investment refs 1-10
INSERT INTO Watchlist (Watchlist_ID, Client_ID, Investment_ID) VALUES
(1,   1,  5),   -- James watching META
(2,   1,  7),   -- James watching TSLA
(3,   2,  1),   -- Sofia watching AAPL
(4,   3,  2),   -- Marcus watching MSFT
(5,   4,  3),   -- Emily watching GOOGL
(6,   5,  4),   -- Raj watching AMZN
(7,   6, 10),   -- Laura watching TRBCX
(8,   7,  6),   -- David watching JPM
(9,   8,  8),   -- Priya watching VFIAX
(10,  9,  9);   -- Carlos watching FCNTX

-- ── 10. Trigger_Price ────────────────────────────────────────
-- IDs 1-10  |  Watchlist refs 1-10
INSERT INTO Trigger_Price (Alert_ID, Watchlist_ID, Trigger_Condition, Trigger_Price, Notification_Type) VALUES
(1,   1, 'ABOVE', 525.00,  'EMAIL'),   -- Alert if META > 525
(2,   2, 'BELOW', 150.00,  'SMS'),     -- Alert if TSLA < 150
(3,   3, 'ABOVE', 200.00,  'PUSH'),    -- Alert if AAPL > 200
(4,   4, 'BELOW', 400.00,  'EMAIL'),   -- Alert if MSFT < 400
(5,   5, 'ABOVE', 180.00,  'SMS'),     -- Alert if GOOGL > 180
(6,   6, 'BELOW', 175.00,  'EMAIL'),   -- Alert if AMZN < 175
(7,   7, 'ABOVE', 165.00,  'PUSH'),    -- Alert if TRBCX > 165
(8,   8, 'ABOVE', 210.00,  'EMAIL'),   -- Alert if JPM > 210
(9,   9, 'BELOW', 415.00,  'SMS'),     -- Alert if VFIAX < 415
(10, 10, 'ABOVE', 185.00,  'PUSH');    -- Alert if FCNTX > 185

-- ── 11. Orders ───────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-10, Broker refs 1-10, Investment refs 1-10
-- Orders 1-8: EXECUTED (will receive stock_transaction records)
-- Order 9: PENDING, Order 10: CANCELLED
INSERT INTO Orders (Order_ID, Client_ID, Broker_ID, Investment_ID, Order_Type, Status,      Price,   Quantity, Order_Date) VALUES
(1,   1,  1,  1, 'BUY',  'EXECUTED',  175.50,  50, '2023-01-15 09:30:00'),  -- James BUY AAPL
(2,   1,  1,  2, 'BUY',  'EXECUTED',  380.00,  30, '2023-02-20 10:15:00'),  -- James BUY MSFT
(3,   2,  2,  3, 'BUY',  'EXECUTED',  160.00,  20, '2023-03-10 11:00:00'),  -- Sofia BUY GOOGL
(4,   2,  2,  8, 'BUY',  'EXECUTED',  410.00,  15, '2023-03-15 14:30:00'),  -- Sofia BUY VFIAX
(5,   3,  3,  4, 'BUY',  'EXECUTED',  170.00,  25, '2023-04-05 09:45:00'),  -- Marcus BUY AMZN
(6,   4,  4,  5, 'BUY',  'EXECUTED',  452.00,  10, '2023-05-12 10:30:00'),  -- Emily BUY META
(7,   5,  5,  6, 'BUY',  'EXECUTED',  185.00,  40, '2023-06-18 11:15:00'),  -- Raj BUY JPM
(8,   6,  6,  7, 'SELL', 'EXECUTED',  220.00,  20, '2023-07-22 13:00:00'),  -- Laura SELL TSLA
(9,   7,  7,  9, 'BUY',  'PENDING',   175.00,   8, '2024-01-10 09:00:00'),  -- David pending FCNTX (assuming BUY)
(10,  8,  8, 10, 'SELL', 'CANCELLED', 155.00,   5, '2024-01-12 10:30:00');  -- Priya cancelled TRBCX (assuming SELL)

-- ── 12. stock_transaction ────────────────────────────────────
-- IDs 1-10  |  Order refs 1-8 (EXECUTED only); rows 9-10 have NULL Order_ID
-- Client and Broker must match the referenced order for data consistency
INSERT INTO stock_transaction (Transaction_ID, Order_ID, Client_ID, Broker_ID, Type,   Price,   Quantity, Transaction_Date) VALUES
(1,   1,  1,  1, 'BUY',  175.50, 50, '2023-01-15 09:31:04'),
(2,   2,  1,  1, 'BUY',  380.00, 30, '2023-02-20 10:16:22'),
(3,   3,  2,  2, 'BUY',  160.00, 20, '2023-03-10 11:01:55'),
(4,   4,  2,  2, 'BUY',  410.00, 15, '2023-03-15 14:31:08'),
(5,   5,  3,  3, 'BUY',  170.00, 25, '2023-04-05 09:46:30'),
(6,   6,  4,  4, 'BUY',  452.00, 10, '2023-05-12 10:31:17'),
(7,   7,  5,  5, 'BUY',  185.00, 40, '2023-06-18 11:16:44'),
(8,   8,  6,  6, 'SELL', 220.00, 20, '2023-07-22 13:01:59'),
(9,  NULL, 9,  9, 'BUY',  265.18, 10, '2023-08-30 09:15:00'),  -- manual / off-platform trade
(10, NULL,10, 10, 'SELL',  89.15,  5, '2023-09-14 14:45:00');  -- manual / off-platform trade

-- ── 13. Tax ──────────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-10, Broker refs 1-10
-- Unique on (Client_ID, Broker_ID, Tax_Year)
INSERT INTO Tax (Tax_ID, Client_ID, Broker_ID, Tax_Year, Profit,     Loss,     Tax) VALUES
(1,   1,  1, 2023, 12500.00,  3200.00,  1867.50),
(2,   2,  2, 2023,  8300.00,  1500.00,  1020.00),
(3,   3,  3, 2023, 21000.00,  4800.00,  2430.00),
(4,   4,  4, 2023,  5600.00,   900.00,   735.00),
(5,   5,  5, 2023, 33000.00,  7200.00,  3862.50),
(6,   6,  6, 2023,  9100.00,  2100.00,  1050.00),
(7,   7,  7, 2023, 14500.00,  3300.00,  1710.00),
(8,   8,  8, 2023,  6200.00,  1100.00,   787.50),
(9,   9,  9, 2022, 18700.00,  4000.00,  2205.00),
(10, 10, 10, 2022, 11200.00,  2600.00,  1312.50);

-- ── 14. Documents ────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-10, Broker refs 1-10
INSERT INTO Documents (Documents_ID, Client_ID, Broker_ID, Document_Type,        Date_Uploaded) VALUES
(1,   1,  1, 'KYC Verification',       '2023-01-10'),
(2,   2,  2, 'Account Agreement',      '2023-02-14'),
(3,   3,  3, 'KYC Verification',       '2023-03-01'),
(4,   4,  4, 'Tax Form W-9',           '2023-04-08'),
(5,   5,  5, 'Account Statement',      '2023-06-30'),
(6,   6,  6, 'Trade Confirmation',     '2023-07-23'),
(7,   7,  7, 'Account Agreement',      '2023-08-01'),
(8,   8,  8, 'KYC Verification',       '2023-09-05'),
(9,   9,  9, 'Account Statement',      '2023-10-15'),
(10, 10, 10, 'Tax Form W-9',           '2023-12-01');

-- ── 15. Insights ─────────────────────────────────────────────
-- IDs 1-10  |  Client refs 1-10, Market refs 1-2
-- Rows 1-7: scoped to a stock (Stock_ID set, Mutual_Funds_ID NULL)
-- Rows 8-10: scoped to a mutual fund (Mutual_Funds_ID set, Stock_ID NULL)
INSERT INTO Insights (Insight_ID, Client_ID, Market_ID, Stock_ID, Mutual_Funds_ID, Profit,    Loss,     Total_PL) VALUES
(1,   1,  2,  1, NULL,  12050.00,     0.00,  12050.00),  -- James: AAPL gain
(2,   1,  2,  2, NULL,   9645.00,     0.00,   9645.00),  -- James: MSFT gain
(3,   2,  2,  3, NULL,   4860.00,   500.00,   4360.00),  -- Sofia: GOOGL net
(4,   2,  1,  NULL, 1,   5055.00,     0.00,   5055.00),  -- Sofia: VFIAX fund gain
(5,   3,  2,  4, NULL,   7855.00,  1000.00,   6855.00),  -- Marcus: AMZN net
(6,   4,  2,  5, NULL,  12380.00,  2000.00,  10380.00),  -- Emily: META net
(7,   5,  1,  6, NULL,   5682.00,   800.00,   4882.00),  -- Raj: JPM net
(8,   6,  2,  8, NULL,    500.00,  2000.00,  -1500.00),  -- Laura: TSLA loss
(9,   7,  1,  NULL, 2,   3366.00,     0.00,   3366.00),  -- David: FCNTX fund gain
(10,  8,  1,  NULL, 3,   2175.60,   300.00,   1875.60);  -- Priya: TRBCX fund net
