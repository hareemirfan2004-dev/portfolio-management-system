import os
from flask import Flask, render_template, request, redirect, url_for, flash, session
from functools import wraps
from werkzeug.security import check_password_hash
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

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'admin_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

@app.route('/')
def index():
    if 'admin_id' in session:
        return redirect(url_for('clients'))
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        with get_db() as (conn, cur):
            cur.execute('SELECT Admin_ID, Password_Hash FROM Admins WHERE Username = %s', (username,))
            admin = cur.fetchone()
            if admin and check_password_hash(admin['Password_Hash'], password):
                session['admin_id'] = admin['Admin_ID']
                session['username'] = username
                return redirect(url_for('clients'))
            else:
                flash('Invalid username or password', 'error')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


@app.route('/clients', methods=['GET', 'POST'])
@login_required
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
@login_required
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
@login_required
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
                               (Client_ID, Broker_ID, Investment_ID, Order_Type, Status, Price, Quantity)
                           VALUES (%s, %s, %s, %s, 'PENDING', %s, %s)''',
                        (client_id, broker_id, investment_id, order_type, price, quantity),
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
                   CONCAT(COALESCE(s.Symbol, mf.Symbol), ' — ', i.Name) AS Label,
                   COALESCE(s.Last_Traded_Price, mf.Price) AS Current_Price
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


@app.route('/orders')
@login_required
def orders():
    with get_db() as (conn, cur):
        cur.execute('''
            SELECT o.Order_ID, o.Order_Date, o.Order_Type, o.Status, o.Price, o.Quantity,
                   c.Name AS Client_Name, b.Name AS Broker_Name,
                   COALESCE(s.Symbol, mf.Symbol) AS Symbol,
                   i.Name AS Investment_Name
            FROM Orders o
            INNER JOIN Client c ON o.Client_ID = c.Client_ID
            INNER JOIN Broker b ON o.Broker_ID = b.Broker_ID
            INNER JOIN Investments i ON o.Investment_ID = i.Investment_ID
            LEFT JOIN Stocks s ON i.Stock_ID = s.Stock_ID
            LEFT JOIN Mutual_Funds mf ON i.Mutual_Funds_ID = mf.Mutual_Funds_ID
            ORDER BY o.Status = 'PENDING' DESC, o.Order_Date DESC
        ''')
        all_orders = cur.fetchall()
    return render_template('orders.html', orders=all_orders)


@app.route('/orders/<int:order_id>/execute', methods=['POST'])
@login_required
def execute_order(order_id):
    with get_db() as (conn, cur):
        cur.execute('SELECT * FROM Orders WHERE Order_ID = %s', (order_id,))
        order = cur.fetchone()
        
        if not order:
            flash('Order not found.', 'error')
            return redirect(url_for('orders'))
            
        if order['Status'] != 'PENDING':
            flash('Only PENDING orders can be executed.', 'error')
            return redirect(url_for('orders'))
            
        try:
            # Trigger trg_transaction_after_insert handles the Order Status update,
            # Tax upsert (for SELL), and Insights append.
            cur.execute('''
                INSERT INTO stock_transaction (Order_ID, Client_ID, Broker_ID, Type, Price, Quantity)
                VALUES (%s, %s, %s, %s, %s, %s)
            ''', (
                order['Order_ID'],
                order['Client_ID'],
                order['Broker_ID'],
                order['Order_Type'],
                order['Price'],
                order['Quantity']
            ))
            conn.commit()
            flash(f'Order #{order_id} executed successfully.', 'success')
        except mysql.connector.Error as e:
            flash(f'Database error: {e.msg}', 'error')
            
    return redirect(url_for('orders'))


@app.route('/summary')
@login_required
def summary():
    with get_db() as (conn, cur):
        cur.execute('SELECT * FROM ClientPortfolioSummary ORDER BY Return_Pct DESC')
        rows = cur.fetchall()
    return render_template('summary.html', rows=rows)


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
