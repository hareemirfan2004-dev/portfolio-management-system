# ER Diagram — Portfolio Management System

```mermaid
erDiagram
    Market {
        int Market_ID PK
        varchar Name
        varchar Location
    }
    Stocks {
        int Stock_ID PK
        int Market_ID FK
        varchar Symbol UK
        varchar Name
        decimal Last_Traded_Price
        decimal High_52w
        decimal Low_52w
        decimal High_Day
        decimal Low_Day
    }
    Mutual_Funds {
        int Mutual_Funds_ID PK
        varchar Name
        varchar Symbol UK
        decimal Price
    }
    IPO {
        int IPO_ID PK
        int Market_ID FK
        varchar Name
        varchar Symbol
        date Start_Date
        date End_Date
        decimal Price
        int Quantity
    }
    Client {
        int Client_ID PK
        varchar Name
        varchar Phone
        varchar Email UK
        varchar Address
    }
    Broker {
        int Broker_ID PK
        varchar Name
        varchar License UK
    }
    Investments {
        int Investment_ID PK
        int Market_ID FK
        enum Investment_Type
        varchar Name
        int Stock_ID FK "nullable - XOR with Mutual_Funds_ID"
        int Mutual_Funds_ID FK "nullable - XOR with Stock_ID"
    }
    Portfolio {
        int Portfolio_ID PK
        int Client_ID FK
        int Investment_ID FK
        decimal Average_Price
        int Quantity
    }
    Watchlist {
        int Watchlist_ID PK
        int Client_ID FK
        int Investment_ID FK
    }
    Trigger_Price {
        int Alert_ID PK
        int Watchlist_ID FK
        enum Trigger_Condition
        decimal Trigger_Price
        enum Notification_Type
    }
    Orders {
        int Order_ID PK
        int Client_ID FK
        int Broker_ID FK
        int Investment_ID FK
        enum Status
        decimal Price
        int Quantity
        datetime Order_Date
    }
    stock_transaction {
        int Transaction_ID PK
        int Order_ID FK "nullable"
        int Client_ID FK
        int Broker_ID FK
        enum Type
        decimal Price
        datetime Transaction_Date
    }
    Tax {
        int Tax_ID PK
        int Client_ID FK
        int Broker_ID FK
        year Tax_Year
        decimal Profit
        decimal Loss
        decimal Tax
    }
    Documents {
        int Documents_ID PK
        int Client_ID FK
        int Broker_ID FK
        varchar Document_Type
        date Date_Uploaded
    }
    Insights {
        int Insight_ID PK
        int Client_ID FK
        int Market_ID FK
        int Stock_ID FK "nullable"
        int Mutual_Funds_ID FK "nullable"
        decimal Profit
        decimal Loss
        decimal Total_PL
    }

    Market            ||--o{ Stocks            : "lists"
    Market            ||--o{ IPO               : "hosts"
    Market            ||--o{ Investments       : "contains"
    Market            ||--o{ Insights          : "scopes"
    Stocks            ||--o{ Investments       : "typed as"
    Mutual_Funds      ||--o{ Investments       : "typed as"
    Investments       ||--o{ Portfolio         : "held in"
    Investments       ||--o{ Watchlist         : "watched via"
    Investments       ||--o{ Orders            : "ordered"
    Client            ||--o{ Portfolio         : "owns"
    Client            ||--o{ Watchlist         : "maintains"
    Client            ||--o{ Orders            : "places"
    Client            ||--o{ stock_transaction : "executes"
    Client            ||--o{ Tax               : "liable for"
    Client            ||--o{ Documents         : "has"
    Client            ||--o{ Insights          : "receives"
    Broker            ||--o{ Orders            : "handles"
    Broker            ||--o{ stock_transaction : "processes"
    Broker            ||--o{ Tax               : "reports"
    Broker            ||--o{ Documents         : "manages"
    Watchlist         ||--o{ Trigger_Price     : "alerts"
    Orders            ||--o{ stock_transaction : "fulfilled by"
    Stocks            ||--o{ Insights          : "covers"
    Mutual_Funds      ||--o{ Insights          : "covers"
```

## Notes

- **Investments XOR constraint:** exactly one of `Stock_ID` / `Mutual_Funds_ID` must be non-null (`chk_inv_exclusive`). Mermaid shows both FK lines; the constraint is enforced at the DB level.
- **`stock_transaction.Order_ID` is nullable:** a transaction may exist without a linked order (manual trade). The line shown is `Orders ||--o{ stock_transaction` — zero-or-more transactions per order.
- **`Insights.Stock_ID` / `Mutual_Funds_ID` are nullable:** an insight may be market-level only.
- **`stock_transaction`** is named to avoid the MySQL reserved word `TRANSACTION`.
