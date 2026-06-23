import os
from flask import Flask, render_template, request, redirect, url_for, flash
import mysql.connector
from db import get_db

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY', 'dev-only-secret-change-in-prod')


# ── Template filters ──────────────────────────────────────────────────────────

@app.template_filter('money')
def money_filter(value):
    """Format a decimal as 1,234.56  (no sign, no currency symbol)."""
    if value is None:
        return '—'
    return f'{float(value):,.2f}'


@app.template_filter('pl')
def pl_filter(value):
    """Format a P&L decimal as +$1,234.56 or -$1,234.56."""
    if value is None:
        return '—'
    f = float(value)
    sign = '+' if f >= 0 else '-'
    return f'{sign}${abs(f):,.2f}'


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return redirect(url_for('clients'))


@app.route('/clients', methods=['GET', 'POST'])
def clients():
    error = None

    if request.method == 'POST':
        name    = request.form.get('name', '').strip()
        email   = request.form.get('email', '').strip()
        phone   = request.form.get('phone', '').strip() or None
        address = request.form.get('address', '').strip() or None

        if not name or not email:
            error = 'Name and Email are required.'
        else:
            try:
                with get_db() as (conn, cur):
                    cur.execute(
                        'INSERT INTO Client (Name, Email, Phone, Address)'
                        ' VALUES (%s, %s, %s, %s)',
                        (name, email, phone, address),
                    )
                    conn.commit()
                flash(f'Client "{name}" added successfully.', 'success')
                return redirect(url_for('clients'))
            except mysql.connector.IntegrityError:
                error = f'A client with email "{email}" is already registered.'
            except mysql.connector.Error as e:
                error = e.msg

    with get_db() as (conn, cur):
        cur.execute('SELECT Client_ID, Name, Email, Phone FROM Client ORDER BY Name')
        rows = cur.fetchall()

    return render_template('clients.html', clients=rows, error=error)


@app.route('/clients/<int:client_id>/portfolio')
def portfolio(client_id):
    with get_db() as (conn, cur):
        cur.execute(
            'SELECT Client_ID, Name, Email FROM Client WHERE Client_ID = %s',
            (client_id,),
        )
        client = cur.fetchone()
        if not client:
            flash('Client not found.', 'error')
            return redirect(url_for('clients'))

        cur.execute('''
            SELECT
                COALESCE(s.Symbol, mf.Symbol)                              AS Symbol,
                i.Name                                                      AS Investment_Name,
                i.Investment_Type,
                p.Quantity,
                p.Average_Price,
                ROUND(CASE i.Investment_Type
                    WHEN 'STOCK'       THEN s.Last_Traded_Price
                    WHEN 'MUTUAL_FUND' THEN mf.Price
                END, 2)                                                     AS Current_Price,
                ROUND((CASE i.Investment_Type
                    WHEN 'STOCK'       THEN s.Last_Traded_Price
                    WHEN 'MUTUAL_FUND' THEN mf.Price
                END - p.Average_Price) * p.Quantity, 2)                     AS Unrealized_PL
            FROM       Portfolio    p
            INNER JOIN Investments  i  ON p.Investment_ID   = i.Investment_ID
            LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
            LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
            WHERE p.Client_ID = %s
            ORDER BY Symbol
        ''', (client_id,))
        holdings = cur.fetchall()

    return render_template('portfolio.html', client=client, holdings=holdings)


@app.route('/orders/new', methods=['GET', 'POST'])
def place_order():
    error = None

    if request.method == 'POST':
        client_id     = request.form.get('client_id')
        broker_id     = request.form.get('broker_id')
        investment_id = request.form.get('investment_id')
        order_type    = request.form.get('type')
        price         = request.form.get('price')
        quantity      = request.form.get('quantity')

        if not all([client_id, broker_id, investment_id, order_type, price, quantity]):
            error = 'All fields are required.'
        else:
            try:
                with get_db() as (conn, cur):
                    cur.execute(
                        '''INSERT INTO Orders
                               (Client_ID, Broker_ID, Investment_ID, Status, Price, Quantity)
                           VALUES (%s, %s, %s, 'PENDING', %s, %s)''',
                        (client_id, broker_id, investment_id, price, quantity),
                    )
                    conn.commit()
                    order_id = cur.lastrowid
                flash(f'Order #{order_id} placed (PENDING).', 'success')
                return redirect(url_for('place_order'))
            except mysql.connector.Error as e:
                error = e.msg

    with get_db() as (conn, cur):
        cur.execute('SELECT Client_ID, Name FROM Client ORDER BY Name')
        all_clients = cur.fetchall()

        cur.execute('SELECT Broker_ID, Name FROM Broker ORDER BY Name')
        brokers = cur.fetchall()

        cur.execute('''
            SELECT i.Investment_ID,
                   CONCAT(COALESCE(s.Symbol, mf.Symbol), ' — ', i.Name) AS Label
            FROM       Investments  i
            LEFT  JOIN Stocks       s  ON i.Stock_ID        = s.Stock_ID
            LEFT  JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
            ORDER BY i.Name
        ''')
        investments = cur.fetchall()

    preselect_client = request.args.get('client_id', '')
    return render_template(
        'order.html',
        clients=all_clients,
        brokers=brokers,
        investments=investments,
        preselect_client=preselect_client,
        error=error,
    )


@app.route('/summary')
def summary():
    with get_db() as (conn, cur):
        cur.execute('SELECT * FROM ClientPortfolioSummary ORDER BY Return_Pct DESC')
        rows = cur.fetchall()
    return render_template('summary.html', rows=rows)


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
