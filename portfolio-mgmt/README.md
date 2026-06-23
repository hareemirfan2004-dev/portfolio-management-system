# Portfolio Management System

A financial management database for a brokerage firm, built as a DBMS course project.

## Overview

This system models the core operations of a brokerage firm: managing client accounts, tracking stock holdings, recording buy/sell transactions, and generating portfolio reports. The database layer is the primary focus, with a lightweight Flask web app serving as the interface.

## Tech Stack

| Layer    | Technology        |
|----------|-------------------|
| Database | MySQL 8.4         |
| Backend  | Flask (Python)    |
| Driver   | mysql-connector-python |

## Project Structure

```
portfolio-mgmt/
├── sql/
│   ├── schema/       # CREATE TABLE statements, constraints, indexes
│   ├── queries/      # SELECT queries, joins, aggregations, views
│   ├── triggers/     # Audit logs, auto-updates, business rules
│   └── seed/         # Sample data for testing
├── docs/
│   ├── er_diagram/   # ER diagram notes and exports
│   └── normalization/ # Normalization analysis (1NF → BCNF)
├── app/              # Flask application (routes, templates, DB connector)
├── CLAUDE.md         # Tech decisions and dev notes
├── .gitignore
└── README.md
```

## Setup

### Prerequisites
- MySQL 8.4 running locally
- Python 3.x
- pip

### Database
```bash
mysql -u root -p < sql/schema/create_tables.sql
mysql -u root -p < sql/seed/sample_data.sql
```

### App
```bash
cd app
pip install -r requirements.txt
python app.py
```

## Features (Planned)
- Client and account management
- Portfolio holdings tracker
- Buy/sell transaction recording
- Gain/loss calculations
- Broker and commission tracking
